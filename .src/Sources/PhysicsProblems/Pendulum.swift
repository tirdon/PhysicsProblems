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
		self.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(shape: .circle(radius: 0.26))
		self.components[VectorComponent.self] = VectorComponent(vector: .circle(radius: 0.25))
		self.components[RenderStyleComponent.self] = RenderStyleComponent(color: .bob)
	}
}

public extension Entity {
	var pendulumAnimation: PendulumPhysicsComponent? {
		get { components[PendulumPhysicsComponent.self] }
		set { components[PendulumPhysicsComponent.self] = newValue }
	}
}

public struct PendulumPhysicsComponent: Component {
	public var length: Float
	public var baseAngle: Float
	public var amplitude: Float
	public var period: Float
	public var elapsed: Float

	public init(
		length: Float = 1,
		baseAngle: Float = 0,
		amplitude: Float = 0.28,
		period: Float = 2.4,
		elapsed: Float = 0
	) {
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

		for entity in scene.performQuery(.has(PendulumPhysicsComponent.self)) {
			guard var animation = entity.pendulumAnimation else { continue }

			if scene.draggedEntity == entity {
				continue
			}
			if scene.hoveredEntity == entity,
			   entity.interaction?.pauseAnimationOnHover == true {
				continue
			}
			
			// Calculate old phase and relative position to find the implicit pivot
			let oldPhase = sin((animation.elapsed / animation.period) * Float.pi * 2)
			let oldAngle = animation.baseAngle + animation.amplitude * oldPhase
			let oldRelativePos = SIMD3<Float>(
				sin(oldAngle),
				-cos(oldAngle),
				0
			) * animation.length

			animation.elapsed += boundedDelta
			
			// Calculate new phase and relative position
			let newPhase = sin((animation.elapsed / animation.period) * Float.pi * 2)
			let newAngle = animation.baseAngle + animation.amplitude * newPhase
			let newRelativePos = SIMD3<Float>(
				sin(newAngle),
				-cos(newAngle),
				0
			) * animation.length

			if var transform = entity.transform {
				let dynamicPivot = transform.position - oldRelativePos
				transform.position = dynamicPivot + newRelativePos
				entity.transform = transform
			}

			entity.pendulumAnimation = animation
		}
	}
}
