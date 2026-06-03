//
//  System.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

// MARK: - System Protocol
@MainActor public protocol System {
	func update(context: SceneUpdateContext)
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
	public init() {}

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
