//
//  Scene.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

@MainActor public class SceneWorld {
	private(set) public var entities: [Entity] = []
	private var systems: [System] = []

	public private(set) var viewportId: String?
	public private(set) var hoveredEntity: Entity?
	public private(set) var draggedEntity: Entity?
	private var dragOffset: SIMD3<Float> = .zero

	public func setViewport(id: String?) {
		self.viewportId = id
	}

	// Animation timeline
	private var animationQueue: [AnimationClip] = []
	private var currentClip: AnimationClipState?

	public init() {}

	// MARK: - Entity Management

	public func add(_ entity: some Entity) {
		self.entities.append(entity)
	}

	// MARK: - System Registration

	public func registerSystem(_ system: some System) {
		self.systems.append(system)
	}

	// MARK: - Query

	public func performQuery(_ query: EntityQuery) -> [Entity] {
		self.entities.filter(query.predicate)
	}

	// MARK: - Update

	public func update(deltaTime: Float) {
		let context = SceneUpdateContext(scene: self, deltaTime: deltaTime)
		for system in self.systems {
			system.update(context: context)
		}
	}

	// MARK: - Animation Timeline

	public func play(_ clip: AnimationClip) {
		animationQueue.append(clip)
	}

	private var waitContinuations: [CheckedContinuation<Void, Never>] = []

	public func wait(second: Float = 1) async {
		if second > 0 {
			let delayClip = AnimationClip()
			delayClip.addTrack(DelayTrack(duration: second))
			animationQueue.append(delayClip)
		}

		if currentClip == nil && animationQueue.isEmpty {
			return
		}
		await withCheckedContinuation { continuation in
			waitContinuations.append(continuation)
		}
	}

	/// Called by AnimationSystem each frame to drive animations
	public func advanceAnimations(deltaTime: Float) {
		// If no current clip, dequeue next
		if currentClip == nil, !animationQueue.isEmpty {
			let clip = animationQueue.removeFirst()
			clip.begin()
			currentClip = AnimationClipState(
				clip: clip,
				elapsed: 0
			)
		}

		guard var state = currentClip else { return }

		state.elapsed += deltaTime
		state.clip.apply(at: state.elapsed)

		if state.elapsed >= state.clip.duration {
			currentClip = nil
			if animationQueue.isEmpty {
				for cont in waitContinuations {
					cont.resume()
				}
				waitContinuations.removeAll()
			}
		} else {
			currentClip = state
		}
	}

	// MARK: - Input Handling

	public func pointerMoved(to point: SIMD3<Float>) {
		if let draggedEntity {
			if var transform = draggedEntity.transform {
				transform.position = point + dragOffset
				draggedEntity.transform = transform
			}
			hoveredEntity = draggedEntity
			return
		}
		hoveredEntity = hitTest(point)
	}

	public func pointerDown(at point: SIMD3<Float>) {
		guard let entity = hitTest(point),
			  entity.interaction?.draggable == true,
			  let position = entity.transform?.position
		else {
			hoveredEntity = nil
			draggedEntity = nil
			return
		}
		hoveredEntity = entity
		draggedEntity = entity
		dragOffset = position - point
	}

	public func pointerUp(at point: SIMD3<Float>) {
		if let dragged = draggedEntity {
			dragged.interaction?.onDragEnd?(dragged)
		}
		draggedEntity = nil
		dragOffset = .zero
		hoveredEntity = hitTest(point)
	}

	// MARK: - Snapshot

	public func snapshot() -> SceneSnapshot {
		var primitives: [RenderPrimitive] = []
		primitives.reserveCapacity(entities.count)

		for entity in entities {
			let style = effectiveStyle(for: entity)
			guard style.opacity > 0.001 else { continue }
			let color = style.color.with(opacity: style.opacity)

			if let vectorComponent = entity.components[VectorComponent.self] {
				switch vectorComponent.vector {
				case .circle(let radius):
					if let transform = entity.transform {
						primitives.append(.circle(center: transform.position, radius: radius, color: color))
					}
				case .ellipse(let major, let minor):
					if let transform = entity.transform {
						// For now, assume 0 rotation since it requires extracting from quaternion
						primitives.append(.ellipse(center: transform.position, major: major, minor: minor, rotation: 0, color: color))
					}
				case .line(let start, let end, let width):
					primitives.append(.line(
						start: start.resolve(),
						end: end.resolve(),
						width: width,
						color: color
					))
				case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth, let tipShape, let tailShape):
					primitives.append(.arrow(
						start: start.resolve(),
						end: end.resolve(),
						shaftWidth: shaftWidth,
						headLength: headLength,
						headWidth: headWidth,
						tipShape: tipShape,
						tailShape: tailShape,
						color: color
					))
				}
			}
		}

		return SceneSnapshot(primitives: primitives)
	}

	// MARK: - Hit Testing

	public func hitTest(_ point: SIMD3<Float>) -> Entity? {
		for entity in entities.reversed() {
			guard let interaction = entity.interaction,
				  interaction.hoverable || interaction.draggable else {
				continue
			}

			if let physicsBody = entity.components[PhysicsBodyComponent.self], let transform = entity.transform {
				switch physicsBody.shape {
				case .circle(let radius):
					let hitRadius = radius + interaction.hitPadding
					if point.distance(to: transform.position) <= hitRadius {
						return entity
					}
				case .ellipse(let major, let minor):
					let dx = abs(point.x - transform.position.x)
					let dy = abs(point.y - transform.position.y)
					// Simple bounding box hit test for now
					if dx <= major + interaction.hitPadding && dy <= minor + interaction.hitPadding {
						return entity
					}
				case .rect(let width, let height):
					let dx = abs(point.x - transform.position.x)
					let dy = abs(point.y - transform.position.y)
					if dx <= (width * 0.5) + interaction.hitPadding && dy <= (height * 0.5) + interaction.hitPadding {
						return entity
					}
				}
				continue
			}

			if let vectorComponent = entity.components[VectorComponent.self] {
				switch vectorComponent.vector {
				case .circle(let radius):
					if let transform = entity.transform {
						let hitRadius = radius + interaction.hitPadding
						if point.distance(to: transform.position) <= hitRadius {
							return entity
						}
					}
				case .ellipse(let major, let minor):
					if let transform = entity.transform {
						let dx = abs(point.x - transform.position.x)
						let dy = abs(point.y - transform.position.y)
						if dx <= major + interaction.hitPadding && dy <= minor + interaction.hitPadding {
							return entity
						}
					}
				case .line(let start, let end, let width):
					let distance = distanceFromPointToSegment(point, start.resolve(), end.resolve())
					if distance <= width * 0.5 + interaction.hitPadding {
						return entity
					}
				case .arrow(let start, let end, _, _, let headWidth, _, _):
					let distance = distanceFromPointToSegment(point, start.resolve(), end.resolve())
					if distance <= headWidth * 0.5 + interaction.hitPadding {
						return entity
					}
				}
			}
		}
		return nil
	}

	// MARK: - Private

	private func effectiveStyle(for entity: Entity) -> RenderStyleComponent {
		var style = entity.components[RenderStyleComponent.self] ?? RenderStyleComponent(color: .white)
		if let trigger = entity.revealOnHover?.trigger {
			let visible = hoveredEntity == trigger || draggedEntity == trigger
			style.opacity = visible ? 1 : 0
		}
		if (hoveredEntity == entity || draggedEntity == entity), let hoverColor = style.hoverColor {
			style.color = hoverColor
		}
		return style
	}


}

// MARK: - Animation State (private)

private struct AnimationClipState {
	let clip: AnimationClip
	var elapsed: Float
}
