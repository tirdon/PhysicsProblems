//
//  System.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

// MARK: - System Protocol
@MainActor public protocol System {
	init()
	func update(context: SceneUpdateContext)
}

public struct AnySystem: Hashable {
	public let id: ObjectIdentifier
	public let system: any System

	public init<T: System>(_ system: T) {
		self.id = ObjectIdentifier(T.self)
		self.system = system
	}

	public static func == (lhs: AnySystem, rhs: AnySystem) -> Bool {
		return lhs.id == rhs.id
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

public struct SceneUpdateContext {
	public let scene: SceneWorld
	public let deltaTime: Float

	public init(scene: SceneWorld, deltaTime: Float) {
		self.scene = scene
		self.deltaTime = deltaTime
	}
}

// MARK: - Built-in Systems

public class PhysicsSystem: System {
	required public init() {}

	public func update(context: SceneUpdateContext) {
		// Placeholder for physics simulation
	}
}

/// Drives queued animations forward each frame
public struct AnimationSystem: System {
	public init() {}

	public func update(context: SceneUpdateContext) {
		let scene = context.scene
		scene.advanceAnimations(deltaTime: context.deltaTime)
	}
}

/// Automatically updates visual bounding boxes to follow their targets
public struct BoundingVisualizerSystem: System {
	public init() {}

	public func update(context: SceneUpdateContext) {
		let scene = context.scene
		for visual in scene.performQuery(.has(BoundingVisualizerComponent.self)) {
			if let target = visual.components[BoundingVisualizerComponent.self]?.target {
				let bounds = Entity.entityBounds(of: target)
				let center = (bounds.min + bounds.max) / 2
				visual.position = target.position + center
				
				let size = Entity.entitySize(of: target)
				if var vector = visual.components[VectorComponent.self] {
					vector.path = .rect(width: size.x, height: size.y)
					visual.components[VectorComponent.self] = vector
				}
			}
		}
	}
}
