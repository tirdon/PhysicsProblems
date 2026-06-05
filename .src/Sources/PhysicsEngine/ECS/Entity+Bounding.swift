//
//  Entity+Bounding.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 5/6/2569 BE.
//

open class BoundingEntity: PathEntity {
	public weak var target: Entity?

	public init(target: Entity) {
		self.target = target
		super.init()
		
		let size = Entity.entitySize(of: target)
		let bounds = Entity.entityBounds(of: target)
		let center = (bounds.min + bounds.max) / 2
		
		// Using a Rectangle path to draw the bound
		self.vector = VectorComponent(vector: .rect(width: size.x, height: size.y))
		self.position = target.position + center
		self.components[RenderStyleComponent.self] = RenderStyleComponent(color: .clear, strokeColor: .green, strokeWidth: 2)
		self.components[BoundingVisualizerComponent.self] = BoundingVisualizerComponent(target: target)
	}
	
	// MARK: Geometric Bounds Properties
	
	open var minX: Float { position.x + Entity.entityBounds(of: self).min.x }
	open var midX: Float { let b = Entity.entityBounds(of: self); return position.x + (b.min.x + b.max.x) / 2 }
	open var maxX: Float { position.x + Entity.entityBounds(of: self).max.x }
	
	open var minY: Float { position.y + Entity.entityBounds(of: self).min.y }
	open var midY: Float { let b = Entity.entityBounds(of: self); return position.y + (b.min.y + b.max.y) / 2 }
	open var maxY: Float { position.y + Entity.entityBounds(of: self).max.y }
	
	open var minZ: Float { position.z + Entity.entityBounds(of: self).min.z }
	open var midZ: Float { let b = Entity.entityBounds(of: self); return position.z + (b.min.z + b.max.z) / 2 }
	open var maxZ: Float { position.z + Entity.entityBounds(of: self).max.z }
}
