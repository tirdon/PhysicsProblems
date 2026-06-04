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
	open var transform: TransformComponent? {
		get { components[TransformComponent.self] }
		set { components[TransformComponent.self] = newValue }
	}

	open var bounding: PhysicsBodyComponent? {
		get { components[PhysicsBodyComponent.self] }
		set { components[PhysicsBodyComponent.self] = newValue }
	}

	// mesh and path are in the inheritance

	open var interaction: InteractionComponent? {
		get { components[InteractionComponent.self] }
		set { components[InteractionComponent.self] = newValue }
	}

	open var revealOnHover: RevealOnHoverComponent? {
		get { components[RevealOnHoverComponent.self] }
		set { components[RevealOnHoverComponent.self] = newValue }
	}

	// MARK: Alignment
	
	open var position: SIMD3<Float> {
		get { transform?.position ?? .zero }
		set { 
			if var t = transform {
				t.position = newValue
				transform = t
			} else {
				transform = TransformComponent(position: newValue)
			}
		}
	}
	
	open var rotation: Float {
		get { 
			guard let t = transform else { return 0 }
			return 2 * atan2(t.orientation.z, t.orientation.w)
		}
		set { 
			if var t = transform {
				let localAxis = t.orientation.act(SIMD3<Float>(0, 0, 1))
				t.orientation = SIMD4<Float>(angle: newValue, axis: localAxis)
				transform = t
			} else {
				transform = TransformComponent(orientation: SIMD4<Float>(angle: newValue, axis: SIMD3<Float>(0, 0, 1)))
			}
		}
	}
	
	open var magnification: SIMD3<Float> {
		get { transform?.scale ?? .one }
		set { 
			if var t = transform {
				t.scale = newValue
				transform = t
			} else {
				transform = TransformComponent(scale: newValue)
			}
		}
	}
	
	@discardableResult
	public func next(to other: Entity, relative: Unit = .trailing, offset: Float = 0.0) -> Self {
		let direction = relative.vector
		let basePos = other.transform?.position ?? .zero
		
		let otherBounds = Self.entityBounds(of: other)
		let selfBounds = Self.entityBounds(of: self)
		
		let otherCenter = (otherBounds.min + otherBounds.max) / 2
		let selfCenter = (selfBounds.min + selfBounds.max) / 2
		
		var targetPos = basePos
		
		if direction.x > 0 {
			targetPos.x += otherBounds.max.x - selfBounds.min.x
		} else if direction.x < 0 {
			targetPos.x += otherBounds.min.x - selfBounds.max.x
		} else {
			targetPos.x += otherCenter.x - selfCenter.x
		}
		
		if direction.y > 0 {
			targetPos.y += otherBounds.max.y - selfBounds.min.y
		} else if direction.y < 0 {
			targetPos.y += otherBounds.min.y - selfBounds.max.y
		} else {
			targetPos.y += otherCenter.y - selfCenter.y
		}
		
		if direction.z > 0 {
			targetPos.z += otherBounds.max.z - selfBounds.min.z
		} else if direction.z < 0 {
			targetPos.z += otherBounds.min.z - selfBounds.max.z
		} else {
			targetPos.z += otherCenter.z - selfCenter.z
		}
		
		var t = self.transform ?? TransformComponent(position: .zero)
		t.position = targetPos + (direction * offset)
		self.transform = t
		return self
	}
	
	@discardableResult
	public func places(at position: SIMD3<Float>) -> Self {
		var t = self.transform ?? TransformComponent(position: position)
		t.position = position
		self.transform = t
		return self
	}
	
	/// Returns the local min and max bounds of an entity from its PhysicsBodyComponent or VectorComponent,
	/// scaled by the entity's transform scale.
	public static func entityBounds(of entity: Entity) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
		var minBounds: SIMD3<Float> = .zero
		var maxBounds: SIMD3<Float> = .zero
		
		if let body = entity.components[PhysicsBodyComponent.self] {
			let offset = body.offset
			switch body.shape {
			case .circle(let r):
				minBounds = SIMD3<Float>(-r, -r, 0) + offset
				maxBounds = SIMD3<Float>(r, r, 0) + offset
			case .ellipse(let major, let minor):
				minBounds = SIMD3<Float>(-major, -minor, 0) + offset
				maxBounds = SIMD3<Float>(major, minor, 0) + offset
			case .rect(let w, let h):
				minBounds = SIMD3<Float>(-w/2, -h/2, 0) + offset
				maxBounds = SIMD3<Float>(w/2, h/2, 0) + offset
			case .boundingBox(let w, let h, let d):
				minBounds = SIMD3<Float>(-w/2, -h/2, -d/2) + offset
				maxBounds = SIMD3<Float>(w/2, h/2, d/2) + offset
			case .boundingSphere(let r):
				minBounds = SIMD3<Float>(-r, -r, -r) + offset
				maxBounds = SIMD3<Float>(r, r, r) + offset
			}
		} else if let vector = entity.components[VectorComponent.self] {
			if let bounds = vector.path.bounds() {
				minBounds = SIMD3<Float>(bounds.min.x, bounds.min.y, 0)
				maxBounds = SIMD3<Float>(bounds.max.x, bounds.max.y, 0)
			}
		}
		let scale = entity.transform?.scale ?? .one
		return (minBounds * scale, maxBounds * scale)
	}

	/// Returns the size of an entity based on its bounds.
	public static func entitySize(of entity: Entity) -> SIMD2<Float> {
		let bounds = entityBounds(of: entity)
		return SIMD2<Float>(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
	}
	
	/// Creates a visual representation of the entity's bounding box.
	/// Note: This returns a new entity. You must add it to the scene or a group, and its position will not automatically update if the parent entity moves unless it's grouped.
	public func createVisualBounds() -> Entity {
		let size = Self.entitySize(of: self)
		let bounds = Self.entityBounds(of: self)
		let center = (bounds.min + bounds.max) / 2
		
		// Using a Rectangle path to draw the bound
		let visual = PathEntity()
		visual.vector = VectorComponent(vector: .rect(width: size.x, height: size.y))
		visual.position = self.position + center
		visual.components[RenderStyleComponent.self] = RenderStyleComponent(color: .clear, strokeColor: .green, strokeWidth: 2)
		visual.components[BoundingVisualizerComponent.self] = BoundingVisualizerComponent(target: self)
		return visual
	}
	

	// MARK: - Geometric Bounds Properties
	
	open var minX: Float { position.x + Self.entityBounds(of: self).min.x }
	open var midX: Float { position.x + (Self.entityBounds(of: self).min.x + Self.entityBounds(of: self).max.x) / 2 }
	open var maxX: Float { position.x + Self.entityBounds(of: self).max.x }
	
	open var minY: Float { position.y + Self.entityBounds(of: self).min.y }
	open var midY: Float { position.y + (Self.entityBounds(of: self).min.y + Self.entityBounds(of: self).max.y) / 2 }
	open var maxY: Float { position.y + Self.entityBounds(of: self).max.y }
	
	open var minZ: Float { position.z + Self.entityBounds(of: self).min.z }
	open var midZ: Float { position.z + (Self.entityBounds(of: self).min.z + Self.entityBounds(of: self).max.z) / 2 }
	open var maxZ: Float { position.z + Self.entityBounds(of: self).max.z }

	// MARK: Animation Builders

	@MainActor public func shift(_ offset: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		AnimationClip(entity: self, target: offset, isRelative: true, duration: duration, easing: easing)
	}

	@MainActor public func move(to position: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		AnimationClip(entity: self, target: position, isRelative: false, duration: duration, easing: easing)
	}
	
	@MainActor public func edge(to corner: Unit, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(EdgeTrack(entity: self, direction: corner.vector, padding: 0.1, duration: duration, easing: easing))
		return clip
	}

	@MainActor public func scale(to target: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(ScaleTrack(entity: self, target: target, isRelative: false, duration: duration, easing: easing))
		return clip
	}

	@MainActor public func scale(by factor: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(ScaleTrack(entity: self, target: factor, isRelative: true, duration: duration, easing: easing))
		return clip
	}

	@MainActor public func rotate(to orientation: SIMD4<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: orientation, isRelative: false, duration: duration, easing: easing))
		return clip
	}
	
	@MainActor public func rotate(by orientation: SIMD4<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: orientation, isRelative: true, duration: duration, easing: easing))
		return clip
	}
	
	@MainActor public func rotate(angle: Float, axis: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth, pivot: Anchor? = nil) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: SIMD4<Float>(angle: angle, axis: axis), isRelative: true, duration: duration, easing: easing, pivot: pivot))
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

// MARK: - Entity inheritances
public class MeshEntity: Entity {
	public var mesh: MeshComponent? {
		get { components[MeshComponent.self] }
		set { components[MeshComponent.self] = newValue }
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
}

open class PathEntity: Entity {
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

	@discardableResult
	public func stroke(_ color: Color, width: Float = 1.0) -> Self {
		if var s = style {
			s.strokeColor = color
			s.strokeWidth = width
			style = s
		} else {
			style = RenderStyleComponent(color: .clear, strokeColor: color, strokeWidth: width)
		}
		return self
	}

	@discardableResult
	public func stroke(style strokeStyle: StrokeStyle) -> Self {
		if var s = style {
			s.strokeStyle = strokeStyle
			style = s
		} else {
			style = RenderStyleComponent(color: .clear, strokeStyle: strokeStyle)
		}
		return self
	}

	@discardableResult
	public func stroke(cap: StrokeCap) -> Self {
		if var s = style {
			s.strokeCap = cap
			style = s
		} else {
			style = RenderStyleComponent(color: .clear, strokeCap: cap)
		}
		return self
	}

}

open class Group: Entity, Collection, ExpressibleByArrayLiteral, Sequence {
	public var elements: [Entity] = []

	public init(elements: [Entity] = []) {
		super.init()
		self.elements = elements
		updatePhysicsBody()
	}
	
	public required convenience init(arrayLiteral elements: Entity...) {
		self.init(elements: elements)
	}
	
	open override var transform: TransformComponent? {
		didSet {
			propagateTransform(oldTransform: oldValue, newTransform: transform)
		}
	}
	
	private func propagateTransform(oldTransform: TransformComponent?, newTransform: TransformComponent?) {
		let oldPosition = oldTransform?.position ?? .zero
		let oldScale = oldTransform?.scale ?? .one
		let newPosition = newTransform?.position ?? .zero
		let newScale = newTransform?.scale ?? .one
		
		let deltaPos = newPosition - oldPosition
		let scaleRatio = newScale / oldScale
		
		if deltaPos != .zero || scaleRatio != .one {
			for element in elements {
				if element.components[BoundingVisualizerComponent.self] != nil { continue }
				if var elementTransform = element.transform {
					if scaleRatio != .one {
						let localPos = elementTransform.position - oldPosition
						elementTransform.position = oldPosition + localPos * scaleRatio
						elementTransform.scale *= scaleRatio
					}
					if deltaPos != .zero {
						elementTransform.position += deltaPos
					}
					element.transform = elementTransform
				}
			}
		}
	}
	
	// MARK: Physics Body
	
	/// Computes the minimum axis-aligned bounding rectangle that contains all
	/// child elements and sets this Group's `PhysicsBodyComponent` to that rect.
	public func updatePhysicsBody() {
		guard !elements.isEmpty else {
			components[PhysicsBodyComponent.self] = nil
			return
		}
		
		var minX: Float = .greatestFiniteMagnitude
		var minY: Float = .greatestFiniteMagnitude
		var maxX: Float = -.greatestFiniteMagnitude
		var maxY: Float = -.greatestFiniteMagnitude
		
		for element in elements {
			let pos = element.transform?.position ?? .zero
			let bounds = Self.entityBounds(of: element)
			
			minX = Swift.min(minX, pos.x + bounds.min.x)
			maxX = Swift.max(maxX, pos.x + bounds.max.x)
			minY = Swift.min(minY, pos.y + bounds.min.y)
			maxY = Swift.max(maxY, pos.y + bounds.max.y)
		}
		
		let width = maxX - minX
		let height = maxY - minY
		let center = SIMD3<Float>((minX + maxX)/2, (minY + maxY)/2, 0)
		let offset = center - (self.transform?.position ?? .zero)
		
		components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
			shape: .rect(width: width, height: height),
			offset: offset
		)
	}
	
	/// Returns the size of an element based on its PhysicsBodyComponent or VectorComponent,
	/// scaled by the element's transform scale.
	private static func elementSize(of entity: Entity) -> SIMD2<Float> {
		var size: SIMD2<Float> = .zero
		if let body = entity.components[PhysicsBodyComponent.self] {
			switch body.shape {
			case .circle(let r): size = SIMD2<Float>(r * 2, r * 2)
			case .ellipse(let major, let minor): size = SIMD2<Float>(major * 2, minor * 2)
			case .rect(let w, let h): size = SIMD2<Float>(w, h)
			case .boundingBox(let w, let h, _): size = SIMD2<Float>(w, h)
			case .boundingSphere(let r): size = SIMD2<Float>(r * 2, r * 2)
			}
		} else if let vector = entity.components[VectorComponent.self] {
			if let bounds = vector.path.bounds() {
				size = SIMD2<Float>(
					bounds.max.x - bounds.min.x,
					bounds.max.y - bounds.min.y
				)
			}
		}
		let scale = entity.transform?.scale ?? .one
		return SIMD2<Float>(size.x * scale.x, size.y * scale.y)
	}
	
	// MARK: Collection Conformance
	open var startIndex: Int { elements.startIndex }
	open var endIndex: Int { elements.endIndex }
	
	public subscript(position: Int) -> Entity {
		return elements[position]
	}
	
	public func index(after i: Int) -> Int {
		return elements.index(after: i)
	}
	
	// MARK: Sequence Conformance
	public func makeIterator() -> IndexingIterator<[Entity]> {
		return elements.makeIterator()
	}
}
