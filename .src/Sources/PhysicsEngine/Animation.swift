//
//  Animation.swift
//  PhysicsProblems
//

import Foundation

public struct Keyframe<Value> {
	public var time: Float
	public var value: Value
	public init(time: Float, value: Value) {
		self.time = time
		self.value = value
	}
}

public protocol AnimationTrack {
	var duration: Float { get }
	func begin()
	func apply(at time: Float)
}

public class KeyframeTrack<Value>: AnimationTrack {
	public let entity: Entity
	public let duration: Float
	public var keyframes: [Keyframe<Value>]
	private let interpolate: (Value, Value, Float) -> Value
	private let applyValue: (Entity, Value) -> Void

	public init(entity: Entity, duration: Float, keyframes: [Keyframe<Value>] = [], interpolate: @escaping (Value, Value, Float) -> Value, applyValue: @escaping (Entity, Value) -> Void) {
		self.entity = entity
		self.duration = duration
		self.keyframes = keyframes.sorted { $0.time < $1.time }
		self.interpolate = interpolate
		self.applyValue = applyValue
	}

	public func begin() {}

	public func apply(at time: Float) {
		guard !keyframes.isEmpty else { return }
		if keyframes.count == 1 {
			applyValue(entity, keyframes[0].value)
			return
		}

		let first = keyframes.first!
		let last = keyframes.last!

		if time <= first.time {
			applyValue(entity, first.value)
			return
		}
		if time >= last.time {
			applyValue(entity, last.value)
			return
		}

		for i in 0..<(keyframes.count - 1) {
			let k1 = keyframes[i]
			let k2 = keyframes[i+1]
			if time >= k1.time && time <= k2.time {
				let segmentDuration = k2.time - k1.time
				let t = segmentDuration > 0 ? (time - k1.time) / segmentDuration : 0
				let easedT = t * t * (3 - 2 * t)
				let val = interpolate(k1.value, k2.value, easedT)
				applyValue(entity, val)
				return
			}
		}
	}
}

public class MoveTrack: AnimationTrack {
	public let entity: Entity
	public let duration: Float
	public let target: SIMD3<Float>
	public let isRelative: Bool
	private var startPosition: SIMD3<Float> = .zero

	public init(entity: Entity, target: SIMD3<Float>, isRelative: Bool, duration: Float) {
		self.entity = entity
		self.target = target
		self.isRelative = isRelative
		self.duration = duration
	}

	public func begin() {
		startPosition = entity.transform?.position ?? .zero
	}

	public func apply(at time: Float) {
		let t = duration > 0 ? clamp(time / duration, min: 0, max: 1) : 1
		let easedT = t * t * (3 - 2 * t)
		let endPosition = isRelative ? startPosition + target : target
		let currentPos = startPosition + (endPosition - startPosition) * easedT
		
		if var transform = entity.transform {
			transform.position = currentPos
			entity.transform = transform
		} else {
			entity.transform = TransformComponent(position: currentPos)
		}
	}
}

public class DelayTrack: AnimationTrack {
	public let duration: Float

	public init(duration: Float) {
		self.duration = duration
	}

	public func begin() {}
	public func apply(at time: Float) {}
}

public class AnimationClip {
	public var tracks: [AnimationTrack] = []
	public var duration: Float {
		tracks.map { $0.duration }.max() ?? 0
	}

	public init(tracks: [AnimationTrack] = []) {
		self.tracks = tracks
	}
    
	public init(entity: Entity, target: SIMD3<Float>, isRelative: Bool, duration: Float) {
		self.tracks = [MoveTrack(entity: entity, target: target, isRelative: isRelative, duration: duration)]
	}

	public func addTrack(_ track: AnimationTrack) {
		tracks.append(track)
	}

	public func begin() {
		for track in tracks {
			track.begin()
		}
	}

	public func apply(at time: Float) {
		for track in tracks {
			track.apply(at: min(time, track.duration))
		}
	}
}
