//
//  Engine.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

@MainActor public class Engine: @unchecked Sendable {
	public private(set) var scenes: [SceneWorld] = []

	public init() {}

	private func makeScene() -> SceneWorld {
		let scene = SceneWorld()
		scene.registerSystem(AnimationSystem.self)
		scene.registerSystem(BoundingVisualizerSystem.self)
		scenes.append(scene)
		return scene
	}

	@discardableResult
	public init(_ callback: @escaping @MainActor (SceneWorld) async -> Void) {
		let scene = makeScene()
		Task {
			await callback(scene)
		}
	}

	public func newScene() -> SceneWorld {
		makeScene()
	}

	/// Get the first (primary) scene
	public var primary: SceneWorld? {
		scenes.first
	}
}
