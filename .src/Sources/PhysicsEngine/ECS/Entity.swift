//
//  Entity.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

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
	public var visualBounds: BoundingEntity {
		BoundingEntity(target: self)
	}

	// MARK: Animation Builders

	

	// MARK: Hashable
	public static func == (lhs: Entity, rhs: Entity) -> Bool {
		lhs.id == rhs.id
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

//MARK: - Transformation
extension Entity {
	
}


//MARK: - Animation Builders
@MainActor
extension Entity {
	public func shift(_ offset: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		AnimationClip(entity: self, target: offset, isRelative: true, duration: duration, easing: easing)
	}

	public func move(to position: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		AnimationClip(entity: self, target: position, isRelative: false, duration: duration, easing: easing)
	}
	
	public func edge(to corner: Unit, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(EdgeTrack(entity: self, direction: corner.vector, padding: 0.1, duration: duration, easing: easing))
		return clip
	}

	public func scale(to target: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(ScaleTrack(entity: self, target: target, isRelative: false, duration: duration, easing: easing))
		return clip
	}

	public func scale(by factor: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(ScaleTrack(entity: self, target: factor, isRelative: true, duration: duration, easing: easing))
		return clip
	}

	public func rotate(to orientation: SIMD4<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: orientation, isRelative: false, duration: duration, easing: easing))
		return clip
	}
	
	public func rotate(by orientation: SIMD4<Float>, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: orientation, isRelative: true, duration: duration, easing: easing))
		return clip
	}
	
	public func rotate(angle: Float, axis: SIMD3<Float>, duration: Float = 1.0, easing: Easing = .smooth, pivot: Anchor? = nil) -> AnimationClip {
		let clip = AnimationClip()
		clip.addTrack(RotationTrack(entity: self, target: SIMD4<Float>(angle: angle, axis: axis), isRelative: true, duration: duration, easing: easing, pivot: pivot))
		return clip
	}
}
