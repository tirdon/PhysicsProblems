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

	public init() {}

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


	// MARK: Animation Builders

	public func shift(_ offset: SIMD3<Float>, duration: Float = 1.0) -> AnimationClip {
		AnimationClip(entity: self, target: offset, isRelative: true, duration: duration)
	}

	public func move(to position: SIMD3<Float>, duration: Float = 1.0) -> AnimationClip {
		AnimationClip(entity: self, target: position, isRelative: false, duration: duration)
	}

	// MARK: Hashable
	public static func == (lhs: Entity, rhs: Entity) -> Bool {
		lhs.id == rhs.id
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
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
