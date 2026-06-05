//
//  Entity+Group.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 5/6/2569 BE.
//

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
