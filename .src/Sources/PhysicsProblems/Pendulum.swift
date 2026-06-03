//
//  Pendulum.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import PhysicsEngine
import Foundation

class Pendulum: Entity {
	override public init() {
		super.init()
		self.components[VectorComponent.self] = VectorComponent(vector: .circle(radius: 0.25))
		self.components[RenderStyleComponent.self] = RenderStyleComponent(color: .bob)
	}
}

public extension Entity {
	var pendulumAnimation: PendulumAnimationComponent? {
		get { components[PendulumAnimationComponent.self] }
		set { components[PendulumAnimationComponent.self] = newValue }
	}
}

public struct PendulumAnimationComponent: Component {
	public var pivot: SIMD3<Float>
	public var length: Float
	public var baseAngle: Float
	public var amplitude: Float
	public var period: Float
	public var elapsed: Float

	public init(
		pivot: SIMD3<Float> = .zero,
		length: Float = 1,
		baseAngle: Float = 0,
		amplitude: Float = 0.28,
		period: Float = 2.4,
		elapsed: Float = 0
	) {
		self.pivot = pivot
		self.length = length
		self.baseAngle = baseAngle
		self.amplitude = amplitude
		self.period = period
		self.elapsed = elapsed
	}
}

public struct PendulumAnimationSystem: System {
	public init() {}

	public func update(context: SceneUpdateContext) {
		let boundedDelta = clamp(context.deltaTime, min: 0, max: 0.05)
		let scene = context.scene

		for entity in scene.performQuery(.has(PendulumAnimationComponent.self)) {
			guard var animation = entity.pendulumAnimation else { continue }

			if scene.draggedEntity == entity {
				continue
			}
			if scene.hoveredEntity == entity,
			   entity.interaction?.pauseAnimationOnHover == true {
				continue
			}

			animation.elapsed += boundedDelta
			let phase = sin((animation.elapsed / animation.period) * Float.pi * 2)
			let angle = animation.baseAngle + animation.amplitude * phase

			if var transform = entity.transform {
				transform.position = animation.pivot + SIMD3<Float>(
					sin(angle),
					-cos(angle),
					0
				) * animation.length
				entity.transform = transform
			}

			entity.pendulumAnimation = animation
		}
	}
}
