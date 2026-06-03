//
//  Engine.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

@MainActor public class Engine: @unchecked Sendable {
	public private(set) var scenes: [SceneWorld] = []

	public init() {}

	@discardableResult
	public init(_ callback: @escaping @MainActor (SceneWorld) async -> Void) {
		let scene = SceneWorld()
		// Register built-in systems
		scene.registerSystem(AnimationSystem.self)
		scenes.append(scene)
		Task {
			await callback(scene)
		}
	}

	public func newScene() -> SceneWorld {
		let scene = SceneWorld()
		scene.registerSystem(AnimationSystem.self)
		scenes.append(scene)
		return scene
	}

	/// Get the first (primary) scene
	public var primaryScene: SceneWorld? {
		scenes.first
	}
}
