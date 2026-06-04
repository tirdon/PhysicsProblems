//
//  Scene.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

public struct Camera {
	public var transform: TransformComponent
	public var fov: Float

	public init(position: SIMD3<Float> = SIMD3<Float>(0, 0, 10), orientation: SIMD4<Float> = .identity, fov: Float = 60) {
		self.transform = TransformComponent(position: position, orientation: orientation)
		self.fov = fov
	}

	public mutating func look(at target: SIMD3<Float>) {
		let forward = SIMD3<Float>(0, 0, -1)
		let direction = (target - transform.position).normalized
		let dotProd = (forward.x * direction.x) + (forward.y * direction.y) + (forward.z * direction.z)
		if dotProd < -0.9999 {
			transform.orientation = SIMD4<Float>(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
		} else {
			let axis = cross(forward, direction)
			if axis.length > 0.0001 {
				let angle = acos(dotProd)
				transform.orientation = SIMD4<Float>(angle: angle, axis: axis.normalized)
			} else {
				transform.orientation = .identity
			}
		}
	}

	public mutating func orbit(about pivot: SIMD3<Float>, angle: Float, axis: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) {
		let offset = transform.position - pivot
		let orbitRotation = SIMD4<Float>(angle: angle, axis: axis.normalized)
		let newOffset = orbitRotation.act(offset)
		transform.position = pivot + newOffset
		look(at: pivot)
	}
}

@MainActor public class SceneWorld {
	private(set) public var entities: [Entity] = []
	private var systems: Set<AnySystem> = []

	public private(set) var viewportId: String?
	public var size: SIMD2<Float> = .init(10, 10)
	public var camera: Camera = Camera()
	public private(set) var hoveredEntity: Entity?
	public private(set) var draggedEntity: Entity?
	private var dragOffset: SIMD3<Float> = .zero

	public func setViewport(id: String?) {
		self.viewportId = id
	}

	// Animation timeline
	private var animationQueue: [AnimationClip] = []
	private var currentClip: AnimationClipState?

	private var waitContinuations: [CheckedContinuation<Void, Never>] = []
	
	private var pausedSystemTimers: [ObjectIdentifier: Float] = [:]
	private var pauseContinuations: [ObjectIdentifier: [CheckedContinuation<Void, Never>]] = [:]

	public init() {}

	// MARK: - Entity Management

	public func add(_ entity: some Entity) {
		if let pathEntity = entity as? PathEntity, pathEntity.style == nil {
			let colors: [Color] = [.red, .green, .blue, .orange, .purple, .cyan, .magenta, .teal, .indigo, .yellow]
			pathEntity.color(colors[self.entities.count % colors.count])
		}
		self.entities.append(entity)
	}

	// MARK: - System Registration

	public func registerSystem<T: System>(_ systemType: T.Type) {
		self.systems.insert(AnySystem(T()))
	}

	// MARK: - Query

	public func performQuery(_ query: EntityQuery) -> [Entity] {
		self.entities.filter(query.predicate)
	}

	// MARK: - System Control

	public func pause<T: System>(system: T.Type, for duration: Float = 1) async {
		let id = ObjectIdentifier(T.self)
		pausedSystemTimers[id] = (pausedSystemTimers[id] ?? 0) + duration
		if duration <= 0 { return }
		
		await withCheckedContinuation { continuation in
			pauseContinuations[id, default: []].append(continuation)
		}
	}

	// MARK: - Update

	public func update(deltaTime: Float) {
		let context = SceneUpdateContext(scene: self, deltaTime: deltaTime)
		
		var finishedPauses: [ObjectIdentifier] = []
		for (id, time) in pausedSystemTimers {
			let newTime = time - deltaTime
			if newTime <= 0 {
				finishedPauses.append(id)
			} else {
				pausedSystemTimers[id] = newTime
			}
		}
		
		for id in finishedPauses {
			pausedSystemTimers.removeValue(forKey: id)
			if let continuations = pauseContinuations.removeValue(forKey: id) {
				for cont in continuations {
					cont.resume()
				}
			}
		}

		for systemWrapper in self.systems {
			if pausedSystemTimers[systemWrapper.id] != nil { continue }
			systemWrapper.system.update(context: context)
		}
	}

	// MARK: - Animation Timeline

	public func play(_ clip: AnimationClip) {
		animationQueue.append(clip)
	}

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
			clip.begin(in: self)
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

			if let vectorComponent = entity.components[VectorComponent.self] {
				switch vectorComponent.vector {
				case .circle(let radius):
					if let transform = entity.transform {
						primitives.append(.circle(center: transform.position, radius: radius, style: style))
					}
				case .ellipse(let major, let minor):
					if let transform = entity.transform {
						// For now, assume 0 rotation since it requires extracting from quaternion
						primitives.append(.ellipse(center: transform.position, major: major, minor: minor, rotation: 0, style: style))
					}
				case .line(let start, let end, let width):
					primitives.append(.line(
						start: start.resolve(),
						end: end.resolve(),
						width: width,
						style: style
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
						style: style
					))
				case .rect(let width, let height):
					if let transform = entity.transform {
						primitives.append(.rect(center: transform.position, width: width, height: height, rotation: 0, style: style))
					}
				case .polygon(let points):
					if let transform = entity.transform {
						let absolutePoints = points.map { $0 + transform.position }
						primitives.append(.polygon(points: absolutePoints, style: style))
					}
				case .arc(let radius, let startAngle, let endAngle):
					if let transform = entity.transform {
						primitives.append(.arc(center: transform.position, radius: radius, startAngle: startAngle, endAngle: endAngle, style: style))
					}
				case .wall(let start, let end, let spacing, let faceUnit):
					let face = entity.transform?.orientation.act(faceUnit.vector) ?? faceUnit.vector
					primitives.append(.wall(
						start: start.resolve(),
						end: end.resolve(),
						spacing: spacing,
						face: face,
						style: style
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
				case .rect(let width, let height):
					if let transform = entity.transform {
						let dx = abs(point.x - transform.position.x)
						let dy = abs(point.y - transform.position.y)
						if dx <= (width * 0.5) + interaction.hitPadding && dy <= (height * 0.5) + interaction.hitPadding {
							return entity
						}
					}
				case .polygon(let points):
					if let transform = entity.transform {
						var minX: Float = .greatestFiniteMagnitude
						var maxX: Float = -.greatestFiniteMagnitude
						var minY: Float = .greatestFiniteMagnitude
						var maxY: Float = -.greatestFiniteMagnitude
						for p in points {
							minX = min(minX, p.x)
							maxX = max(maxX, p.x)
							minY = min(minY, p.y)
							maxY = max(maxY, p.y)
						}
						let localPoint = point - transform.position
						if localPoint.x >= minX - interaction.hitPadding && localPoint.x <= maxX + interaction.hitPadding &&
						   localPoint.y >= minY - interaction.hitPadding && localPoint.y <= maxY + interaction.hitPadding {
							return entity
						}
					}
				case .arc(let radius, _, _):
					if let transform = entity.transform {
						let hitRadius = radius + interaction.hitPadding
						if point.distance(to: transform.position) <= hitRadius {
							return entity
						}
					}
				case .wall(let start, let end, _, _):
					let distance = distanceFromPointToSegment(point, start.resolve(), end.resolve())
					if distance <= 0.1 + interaction.hitPadding {
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
