//
//  Entity.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

//MARK: - Entity
open class Entity: Hashable, Identifiable {
	public let id: UUID = UUID()
	public var components = ComponentSet()

	public init() {
		self.transform = TransformComponent(position: .zero)
	}

	// MARK: Component Accessors
	open var transform: TransformComponent? {
		get { components[TransformComponent.self] }
		set { components[TransformComponent.self] = newValue }
	}

	// mesh and path are in the inheritance

	public var interaction: InteractionComponent? {
		get { components[InteractionComponent.self] }
		set { components[InteractionComponent.self] = newValue }
	}

	public var revealOnHover: RevealOnHoverComponent? {
		get { components[RevealOnHoverComponent.self] }
		set { components[RevealOnHoverComponent.self] = newValue }
	}

	// MARK: Alignment
	
	open var position: SIMD3<Float> {
		get { transform?.position ?? .zero }
		set { 
			if var t = transform {
				t.position = newValue
				transform = t
			} else {
				transform = TransformComponent(position: newValue)
			}
		}
	}
	
	open var rotation: Float {
		get { 
			guard let t = transform else { return 0 }
			return 2 * atan2(t.orientation.z, t.orientation.w)
		}
		set { 
			if var t = transform {
				let localAxis = t.orientation.act(SIMD3<Float>(0, 0, 1))
				t.orientation = SIMD4<Float>(angle: newValue, axis: localAxis)
				transform = t
			} else {
				transform = TransformComponent(orientation: SIMD4<Float>(angle: newValue, axis: SIMD3<Float>(0, 0, 1)))
			}
		}
	}
	
	open var magnification: SIMD3<Float> {
		get { transform?.scale ?? .one }
		set { 
			if var t = transform {
				t.scale = newValue
				transform = t
			} else {
				transform = TransformComponent(scale: newValue)
			}
		}
	}
	
	public func next(to other: Entity, relative: Unit = .trailing, offset: Float) {
		let direction = relative.vector
		let basePos = other.transform?.position ?? .zero
		var sizeOffset: SIMD3<Float> = .zero
		
		if let body = other.components[PhysicsBodyComponent.self] {
			switch body.shape {
			case .circle(let radius):
				sizeOffset += direction * radius
			case .ellipse(let major, let minor):
				sizeOffset += SIMD3<Float>(direction.x * major, direction.y * minor, direction.z)
			case .rect(let width, let height):
				sizeOffset += SIMD3<Float>(direction.x * width / 2, direction.y * height / 2, direction.z)
			}
		}
		
		if let body = self.components[PhysicsBodyComponent.self] {
			switch body.shape {
			case .circle(let radius):
				sizeOffset += direction * radius
			case .ellipse(let major, let minor):
				sizeOffset += SIMD3<Float>(direction.x * major, direction.y * minor, direction.z)
			case .rect(let width, let height):
				sizeOffset += SIMD3<Float>(direction.x * width / 2, direction.y * height / 2, direction.z)
			}
		}
		
		var t = self.transform ?? TransformComponent(position: .zero)
		t.position = basePos + sizeOffset + (direction * offset)
		self.transform = t
	}
	

	// MARK: Animation Builders

	@MainActor public func shift(_ offset: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		AnimationClip(entity: self, target: offset, isRelative: true, duration: duration, easing: easing)
	}

	@MainActor public func move(to position: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		AnimationClip(entity: self, target: position, isRelative: false, duration: duration, easing: easing)
	}
	
	@MainActor public func edge(to corner: Unit, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(EdgeTrack(entity: self, direction: corner.vector, padding: 0.1, duration: duration, easing: easing))
		return clip
	}

	@MainActor public func scale(to target: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(ScaleTrack(entity: self, target: target, isRelative: false, duration: duration, easing: easing))
		return clip
	}

	@MainActor public func scale(by factor: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(ScaleTrack(entity: self, target: factor, isRelative: true, duration: duration, easing: easing))
		return clip
	}

	@MainActor public func rotate(to orientation: SIMD4<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: orientation, isRelative: false, duration: duration, easing: easing))
		return clip
	}
	
	@MainActor public func rotate(by orientation: SIMD4<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: orientation, isRelative: true, duration: duration, easing: easing))
		return clip
	}
	
	@MainActor public func rotate(angle: Float, axis: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth, pivot: Anchor? = nil) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: SIMD4<Float>(angle: angle, axis: axis), isRelative: true, duration: duration, easing: easing, pivot: pivot))
		return clip
	}

	// MARK: Hashable
	public static func == (lhs: Entity, rhs: Entity) -> Bool {
		lhs.id == rhs.id
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

public class MeshEntity: Entity {
	
}

open class PathEntity: Entity {
	public var vector: VectorComponent? {
		get { components[VectorComponent.self] }
		set { components[VectorComponent.self] = newValue }
	}

	public var style: RenderStyleComponent? {
		get { components[RenderStyleComponent.self] }
		set { components[RenderStyleComponent.self] = newValue }
	}
	
	@discardableResult
	public func color(_ color: Color) -> Self {
		if var s = style {
			s.color = color
			style = s
		} else {
			style = RenderStyleComponent(color: color)
		}
		return self
	}
	
	@discardableResult
	public func opacity(_ opacity: Float) -> Self {
		if var s = style {
			s.opacity = opacity
			style = s
		}
		return self
	}

	@discardableResult
	public func stroke(_ color: Color, width: Float = 1.0) -> Self {
		if var s = style {
			s.strokeColor = color
			s.strokeWidth = width
			style = s
		} else {
			style = RenderStyleComponent(color: .clear, strokeColor: color, strokeWidth: width)
		}
		return self
	}

	@discardableResult
	public func stroke(style strokeStyle: StrokeStyle) -> Self {
		if var s = style {
			s.strokeStyle = strokeStyle
			style = s
		} else {
			style = RenderStyleComponent(color: .clear, strokeStyle: strokeStyle)
		}
		return self
	}

	@discardableResult
	public func stroke(cap: StrokeCap) -> Self {
		if var s = style {
			s.strokeCap = cap
			style = s
		} else {
			style = RenderStyleComponent(color: .clear, strokeCap: cap)
		}
		return self
	}
}

// MARK: - EntityQuery
public struct EntityQuery {
	public let predicate: (Entity) -> Bool

	public init(predicate: @escaping (Entity) -> Bool) {
		self.predicate = predicate
	}

	public static func has<T: Component>(_ type: T.Type) -> EntityQuery {
		EntityQuery { $0.components.exists(type) }
	}

	public static func has<A: Component, B: Component>(_ a: A.Type, _ b: B.Type) -> EntityQuery {
		EntityQuery { $0.components.exists(a) && $0.components.exists(b) }
	}
}
