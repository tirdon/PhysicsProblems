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

@MainActor public protocol AnimationTrack {
	var duration: Float { get }
	func begin(in scene: SceneWorld)
	func apply(at time: Float)
}

@MainActor public class KeyframeTrack<Value>: AnimationTrack {
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

	@MainActor public func begin(in scene: SceneWorld) {}

	@MainActor public func apply(at time: Float) {
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

@MainActor public class TranslationTrack: AnimationTrack {
	public let entity: Entity
	public let duration: Float
	public var startPosition: SIMD3<Float> = .zero
	public var endPosition: SIMD3<Float> = .zero

	public init(entity: Entity, duration: Float) {
		self.entity = entity
		self.duration = duration
	}

	@MainActor public func begin(in scene: SceneWorld) {
		startPosition = entity.transform?.position ?? .zero
	}

	@MainActor public func apply(at time: Float) {
		let t = duration > 0 ? clamp(time / duration, min: 0, max: 1) : 1
		let easedT = t * t * (3 - 2 * t)
		let currentPos = startPosition + (endPosition - startPosition) * easedT
		
		if var transform = entity.transform {
			transform.position = currentPos
			entity.transform = transform
		} else {
			entity.transform = TransformComponent(position: currentPos)
		}
	}
}

@MainActor public class MoveTrack: TranslationTrack {
	public let target: SIMD3<Float>
	public let isRelative: Bool

	public init(entity: Entity, target: SIMD3<Float>, isRelative: Bool, duration: Float) {
		self.target = target
		self.isRelative = isRelative
		super.init(entity: entity, duration: duration)
	}

	@MainActor public override func begin(in scene: SceneWorld) {
		super.begin(in: scene)
		endPosition = isRelative ? startPosition + target : target
	}
}

@MainActor public class DelayTrack: AnimationTrack {
	public let duration: Float

	public init(duration: Float) {
		self.duration = duration
	}

	@MainActor public func begin(in scene: SceneWorld) {}
	@MainActor public func apply(at time: Float) {}
}

@MainActor public class AnimationClip {
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

	@MainActor public func begin(in scene: SceneWorld) {
		for track in tracks {
			track.begin(in: scene)
		}
	}

	@MainActor public func apply(at time: Float) {
		for track in tracks {
			track.apply(at: min(time, track.duration))
		}
	}
}

@MainActor public class EdgeTrack: TranslationTrack {
	public let direction: SIMD3<Float>
	public let padding: Float

	public init(entity: Entity, direction: SIMD3<Float>, padding: Float, duration: Float) {
		self.direction = direction
		self.padding = padding
		super.init(entity: entity, duration: duration)
	}

	@MainActor public override func begin(in scene: SceneWorld) {
		super.begin(in: scene)
		
		var w: Float = 0
		var h: Float = 0
		if let body = entity.components[PhysicsBodyComponent.self] {
			switch body.shape {
			case .circle(let radius):
				w = radius
				h = radius
			case .ellipse(let major, let minor):
				w = major
				h = minor
			case .rect(let width, let height):
				w = width / 2
				h = height / 2
			}
		}
		
		let minX = -scene.size.x / 2 + w + padding
		let maxX = scene.size.x / 2 - w - padding
		let minY = -scene.size.y / 2 + h + padding
		let maxY = scene.size.y / 2 - h - padding
		
		var targetPos = startPosition
		if direction.x > 0 { targetPos.x = maxX }
		else if direction.x < 0 { targetPos.x = minX }
		else { targetPos.x = 0 }
		
		if direction.y > 0 { targetPos.y = maxY }
		else if direction.y < 0 { targetPos.y = minY }
		else { targetPos.y = 0 }
		
		if direction.z > 0 { targetPos.z = 0 }
		
		endPosition = targetPos
	}
}
