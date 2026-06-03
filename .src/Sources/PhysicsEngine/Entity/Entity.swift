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
	public var transform: TransformComponent? {
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

	@MainActor public func shift(_ offset: SIMD3<Float>, duration: Float = 1.0) -> AnimationClip {
		AnimationClip(entity: self, target: offset, isRelative: true, duration: duration)
	}

	@MainActor public func move(to position: SIMD3<Float>, duration: Float = 1.0) -> AnimationClip {
		AnimationClip(entity: self, target: position, isRelative: false, duration: duration)
	}
	
	@MainActor public func edge(to corner: Unit, duration: Float = 1.0) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(EdgeTrack(entity: self, direction: corner.vector, padding: 0.1, duration: duration))
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

public class PathEntity: Entity {
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
