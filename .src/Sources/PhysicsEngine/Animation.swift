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

public enum Easing {
	case linear
	case easeIn
	case easeOut
	case easeInOut
	case easeInOutQuad
	case easeInOutCubic
	case smooth
	case doubleSmooth
	case sigmoid(steepness: Float)
	case expo
	case easeInElastic
	case easeOutElastic
	case wiggle(oscillations: Float)
	case bounce
	case spring(damping: Float, stiffness: Float)
	case custom(@Sendable (Float) -> Float)
	
	public func apply(_ t: Float) -> Float {
		switch self {
		case .linear:
			return t
		case .easeInOut:
			return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
		case .easeIn:
			return t * t
		case .easeOut:
			return t * (2 - t)
		case .easeInOutQuad:
			return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
		case .easeInOutCubic:
			return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
		case .smooth:
			return t * t * (3 - 2 * t)
		case .doubleSmooth:
			return t * t * t * (t * (t * 6 - 15) + 10)
		case .sigmoid(let steepness):
			let val = 1 / (1 + exp(-steepness * (t - 0.5)))
			let minV = 1 / (1 + exp(steepness * 0.5))
			let maxV = 1 / (1 + exp(-steepness * 0.5))
			return (val - minV) / (maxV - minV)
		case .expo:
			return t == 0 ? 0 : (t == 1 ? 1 : (t < 0.5 ? pow(2, 20 * t - 10) / 2 : (2 - pow(2, -20 * t + 10)) / 2))
		case .easeInElastic:
			let c4 = (2 * Float.pi) / 3
			return t == 0 ? 0 : (t == 1 ? 1 : -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c4))
		case .easeOutElastic:
			let c4 = (2 * Float.pi) / 3
			return t == 0 ? 0 : (t == 1 ? 1 : pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1)
		case .wiggle(let oscillations):
			return sin(t * Float.pi * 2 * oscillations)
		case .bounce:
			let n1: Float = 7.5625
			let d1: Float = 2.75
			if t < 1 / d1 {
				return n1 * t * t
			} else if t < 2 / d1 {
				let t2 = t - 1.5 / d1
				return n1 * t2 * t2 + 0.75
			} else if t < 2.5 / d1 {
				let t2 = t - 2.25 / d1
				return n1 * t2 * t2 + 0.9375
			} else {
				let t2 = t - 2.625 / d1
				return n1 * t2 * t2 + 0.984375
			}
		case .spring(let damping, let stiffness):
			return 1 - exp(-damping * 10 * t) * cos(stiffness * 10 * t)
		case .custom(let fn):
			return fn(t)
		}
	}
}

@MainActor public protocol AnimationTrack {
	var duration: Float { get }
	var easing: Easing { get }
	func begin(in scene: SceneWorld)
	func apply(at time: Float)
}

public extension AnimationTrack {
	var easing: Easing { .smooth }
}

//MARK: - Clip
@MainActor public class AnimationClip {
	public var tracks: [AnimationTrack] = []
	public var duration: Float {
		tracks.map { $0.duration }.max() ?? 0
	}

	public init(tracks: [AnimationTrack] = []) {
		self.tracks = tracks
	}
	
	public init(entity: Entity, target: SIMD3<Float>, isRelative: Bool, duration: Float, easing: Easing = .smooth) {
		self.tracks = [MoveTrack(entity: entity, target: target, isRelative: isRelative, duration: duration, easing: easing)]
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

extension AnimationClip: @preconcurrency CustomDebugStringConvertible {
	@MainActor public var debugDescription: String {
		return "AnimationClip(duration: \(duration), tracks: \(tracks.count))"
	}
}

//MARK: - Track

@MainActor public class KeyframeTrack<Value>: AnimationTrack {
	public let entity: Entity
	public let duration: Float
	public var keyframes: [Keyframe<Value>]
	public let easing: Easing
	private let interpolate: (Value, Value, Float) -> Value
	private let applyValue: (Entity, Value) -> Void

	public init(entity: Entity, duration: Float, easing: Easing = .smooth, keyframes: [Keyframe<Value>] = [], interpolate: @escaping (Value, Value, Float) -> Value, applyValue: @escaping (Entity, Value) -> Void) {
		self.entity = entity
		self.duration = duration
		self.easing = easing
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
				let easedT = easing.apply(t)
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
	public let easing: Easing
	public var startPosition: SIMD3<Float> = .zero
	public var endPosition: SIMD3<Float> = .zero

	public init(entity: Entity, duration: Float, easing: Easing = .smooth) {
		self.entity = entity
		self.duration = duration
		self.easing = easing
	}

	@MainActor public func begin(in scene: SceneWorld) {
		startPosition = entity.transform?.position ?? .zero
	}

	@MainActor public func apply(at time: Float) {
		let t = duration > 0 ? clamp(time / duration, min: 0, max: 1) : 1
		let easedT = easing.apply(t)
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

	public init(entity: Entity, target: SIMD3<Float>, isRelative: Bool, duration: Float, easing: Easing = .smooth) {
		self.target = target
		self.isRelative = isRelative
		super.init(entity: entity, duration: duration, easing: easing)
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

@MainActor public class EdgeTrack: TranslationTrack {
	public let direction: SIMD3<Float>
	public let padding: Float

	public init(entity: Entity, direction: SIMD3<Float>, padding: Float, duration: Float, easing: Easing = .smooth) {
		self.direction = direction
		self.padding = padding
		super.init(entity: entity, duration: duration, easing: easing)
	}

	@MainActor public override func begin(in scene: SceneWorld) {
		super.begin(in: scene)
		
		let bounds = Entity.entityBounds(of: entity)
		
		let minX = -scene.size.x / 2 - bounds.min.x + padding
		let maxX = scene.size.x / 2 - bounds.max.x - padding
		let minY = -scene.size.y / 2 - bounds.min.y + padding
		let maxY = scene.size.y / 2 - bounds.max.y - padding
		
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

@MainActor public class ScaleTrack: AnimationTrack {
	public let entity: Entity
	public let duration: Float
	public let easing: Easing
	public let targetScale: SIMD3<Float>
	public let isRelative: Bool
	public var startScale: SIMD3<Float> = .one
	public var endScale: SIMD3<Float> = .one

	public init(entity: Entity, target: SIMD3<Float>, isRelative: Bool, duration: Float, easing: Easing = .smooth) {
		self.entity = entity
		self.targetScale = target
		self.isRelative = isRelative
		self.duration = duration
		self.easing = easing
	}

	@MainActor public func begin(in scene: SceneWorld) {
		startScale = entity.transform?.scale ?? .one
		if isRelative {
			endScale = startScale * targetScale
		} else {
			endScale = targetScale
		}
	}

	@MainActor public func apply(at time: Float) {
		let t = duration > 0 ? clamp(time / duration, min: 0, max: 1) : 1
		let easedT = easing.apply(t)
		let currentScale = startScale + (endScale - startScale) * easedT
		
		if var transform = entity.transform {
			transform.scale = currentScale
			entity.transform = transform
		} else {
			entity.transform = TransformComponent(scale: currentScale)
		}
	}
}

@MainActor public class RotationTrack: AnimationTrack {
	public let entity: Entity
	public let duration: Float
	public let easing: Easing
	public let targetOrientation: SIMD4<Float>
	public let isRelative: Bool
	public let pivot: Anchor?
	public var startOrientation: SIMD4<Float> = .identity
	public var endOrientation: SIMD4<Float> = .identity
	public var startPosition: SIMD3<Float> = .zero
	public var pivotPosition: SIMD3<Float> = .zero

	public init(entity: Entity, target: SIMD4<Float>, isRelative: Bool, duration: Float, easing: Easing = .smooth, pivot: Anchor? = nil) {
		self.entity = entity
		self.targetOrientation = target
		self.isRelative = isRelative
		self.duration = duration
		self.easing = easing
		self.pivot = pivot
	}

	@MainActor public func begin(in scene: SceneWorld) {
		startOrientation = entity.transform?.orientation ?? .identity
		if isRelative {
			endOrientation = startOrientation * targetOrientation
		} else {
			endOrientation = targetOrientation
		}
		
		if let pivot = pivot {
			startPosition = entity.transform?.position ?? .zero
			pivotPosition = pivot.resolve()
		}
	}

	@MainActor public func apply(at time: Float) {
		let t = duration > 0 ? clamp(time / duration, min: 0, max: 1) : 1
		let easedT = easing.apply(t)
		let currentOrientation = startOrientation.slerp(to: endOrientation, t: easedT)
		
		if var transform = entity.transform {
			transform.orientation = currentOrientation
			if pivot != nil {
				let delta = currentOrientation * startOrientation.inverse
				let offset = startPosition - pivotPosition
				transform.position = pivotPosition + delta.act(offset)
			}
			entity.transform = transform
		} else {
			entity.transform = TransformComponent(orientation: currentOrientation)
		}
	}
}
