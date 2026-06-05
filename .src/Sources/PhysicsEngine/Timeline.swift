//
//  Timeline.swift
//  PhysicsProblems
//

import Foundation

// MARK: - Timeline

/// Controls playback of keyframe-based AnimationClips. Excludes system animations.
@MainActor public class Timeline {
	private var history: [AnimationClip] = []
	private var queue: [AnimationClip] = []
	private var current: ClipState?
	private var clipIndex: Int = 0
	public private(set) var isPaused: Bool = false

	private var begunClips: Set<ObjectIdentifier> = []
	private var waitContinuations: [CheckedContinuation<Void, Never>] = []

	public init() {}

	// MARK: - Queue

	public func enqueue(_ clip: AnimationClip) {
		queue.append(clip)
		history.append(clip)
	}

	public var isIdle: Bool {
		current == nil && queue.isEmpty
	}

	public func addWait(_ continuation: CheckedContinuation<Void, Never>) {
		waitContinuations.append(continuation)
	}

	// MARK: - Advance

	/// Advances the timeline by `deltaTime`. Called each frame by AnimationSystem.
	public func advance(deltaTime: Float, in scene: SceneWorld) {
		guard !isPaused else { return }

		// Dequeue next clip if needed
		if current == nil, !queue.isEmpty {
			let clip = queue.removeFirst()
			if !begunClips.contains(ObjectIdentifier(clip)) {
				clip.begin(in: scene)
				begunClips.insert(ObjectIdentifier(clip))
			}
			current = ClipState(clip: clip, elapsed: 0)
			clipIndex = history.count - queue.count - 1
		}

		guard var state = current else { return }

		state.elapsed += deltaTime
		state.clip.apply(at: state.elapsed)

		if state.elapsed >= state.clip.duration {
			current = nil
			if queue.isEmpty {
				for cont in waitContinuations {
					cont.resume()
				}
				waitContinuations.removeAll()
			}
		} else {
			current = state
		}
	}

	// MARK: - Playback Control

	public func togglePause() {
		isPaused.toggle()
	}

	public func setPaused(_ paused: Bool) {
		isPaused = paused
	}

	/// Seek to a global time across all recorded clips.
	public func seek(to globalTime: Float, in scene: SceneWorld) {
		guard !history.isEmpty else { return }
		
		let totalDur = duration
		let clampedTarget = max(0, min(globalTime, totalDur))
		let currentGlobal = currentTime

		// Find target index and local time
		var targetIndex = history.count - 1
		var targetLocalTime: Float = 0
		var acc: Float = 0
		for (i, clip) in history.enumerated() {
			if acc + clip.duration > clampedTarget || (i == history.count - 1 && acc + clip.duration >= clampedTarget) {
				targetIndex = i
				targetLocalTime = clampedTarget - acc
				break
			}
			acc += clip.duration
		}
		if targetIndex == history.count {
			targetIndex = history.count - 1
			targetLocalTime = history.last!.duration
		}

		// Find current index
		var currentIndex = history.count - 1
		var accCur: Float = 0
		for (i, clip) in history.enumerated() {
			if accCur + clip.duration > currentGlobal || (i == history.count - 1 && accCur + clip.duration >= currentGlobal) {
				currentIndex = i
				break
			}
			accCur += clip.duration
		}
		if currentIndex == history.count {
			currentIndex = history.count - 1
		}

		// Apply state changes to recreate correct scene state
		if targetIndex > currentIndex {
			// Fast-forward: apply intermediate clips
			for i in currentIndex...targetIndex {
				let clip = history[i]
				if !begunClips.contains(ObjectIdentifier(clip)) {
					clip.begin(in: scene)
					begunClips.insert(ObjectIdentifier(clip))
				}
				if i < targetIndex {
					clip.apply(at: clip.duration)
				} else {
					clip.apply(at: targetLocalTime)
				}
			}
		} else if targetIndex < currentIndex {
			// Rewind: undo intermediate clips in reverse
			for i in (targetIndex...currentIndex).reversed() {
				let clip = history[i]
				if !begunClips.contains(ObjectIdentifier(clip)) {
					clip.begin(in: scene)
					begunClips.insert(ObjectIdentifier(clip))
				}
				if i > targetIndex {
					clip.apply(at: 0)
				} else {
					clip.apply(at: targetLocalTime)
				}
			}
		} else {
			// Same clip scrub
			let clip = history[targetIndex]
			if !begunClips.contains(ObjectIdentifier(clip)) {
				clip.begin(in: scene)
				begunClips.insert(ObjectIdentifier(clip))
			}
			clip.apply(at: targetLocalTime)
		}

		// Update state and queue
		clipIndex = targetIndex
		let targetClip = history[targetIndex]
		if targetLocalTime >= targetClip.duration && targetIndex == history.count - 1 {
			current = nil
			queue = []
			clipIndex = history.count
		} else {
			current = ClipState(clip: targetClip, elapsed: targetLocalTime)
			queue = Array(history.dropFirst(targetIndex + 1))
		}
	}

	// MARK: - State

	/// Total duration of all recorded clips.
	public var duration: Float {
		history.reduce(0) { $0 + $1.duration }
	}

	/// Current playback time across all clips.
	public var currentTime: Float {
		var time: Float = 0
		for i in 0..<clipIndex {
			if i < history.count {
				time += history[i].duration
			}
		}
		if let state = current {
			time += state.elapsed
		}
		return time
	}

	/// Snapshot of the timeline state for the JS bridge.
	public var state: TimelineState {
		var clips: [TimelineClipInfo] = []
		var offset: Float = 0
		for (index, clip) in history.enumerated() {
			var tracks: [TimelineTrackInfo] = []
			for track in clip.tracks {
				let keyframeTimes: [Float] = [0, track.duration]
				tracks.append(TimelineTrackInfo(
					keyPath: track.keyPath,
					duration: track.duration,
					keyframeTimes: keyframeTimes
				))
			}
			clips.append(TimelineClipInfo(
				index: index,
				startTime: offset,
				duration: clip.duration,
				tracks: tracks,
				isCurrent: index == clipIndex && current != nil
			))
			offset += clip.duration
		}

		return TimelineState(
			clips: clips,
			totalDuration: duration,
			currentTime: currentTime,
			isPaused: isPaused
		)
	}

	// MARK: - Private

	private struct ClipState {
		let clip: AnimationClip
		var elapsed: Float
	}
}

// MARK: - Timeline State

public struct TimelineTrackInfo {
	public let keyPath: String
	public let duration: Float
	public let keyframeTimes: [Float]
}

public struct TimelineClipInfo {
	public let index: Int
	public let startTime: Float
	public let duration: Float
	public let tracks: [TimelineTrackInfo]
	public let isCurrent: Bool
}

public struct TimelineState {
	public let clips: [TimelineClipInfo]
	public let totalDuration: Float
	public let currentTime: Float
	public let isPaused: Bool
}
