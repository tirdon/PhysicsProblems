//
//  Component.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

// MARK: - Component Protocol
public protocol Component {}


// MARK: - ComponentSet
public struct ComponentSet {
	private var storage: [ObjectIdentifier: Component] = [:]

	public init() {}

	public subscript<T: Component>(componentType: T.Type) -> T? {
		get { storage[ObjectIdentifier(componentType)] as? T }
		set {
			if let newValue {
				storage[ObjectIdentifier(componentType)] = newValue
			} else {
				storage.removeValue(forKey: ObjectIdentifier(componentType))
			}
		}
	}

	public func exists(_ componentType: (some Component).Type) -> Bool {
		storage[ObjectIdentifier(componentType)] != nil
	}

	public mutating func set(_ component: some Component) {
		storage[ObjectIdentifier(type(of: component))] = component
	}

	public mutating func remove<T: Component>(_ componentType: T.Type) {
		storage.removeValue(forKey: ObjectIdentifier(componentType))
	}
}

// MARK: - Components

public struct TransformComponent: Component {
	public var position: SIMD3<Float>
	public var orientation: SIMD4<Float>

	public init(position: SIMD3<Float> = .zero, orientation: SIMD4<Float> = .identity) {
		self.position = position
		self.orientation = orientation
	}
}

public struct VectorComponent: Component {
	public enum Vector {
		case circle(radius: Float)
		case ellipse(major: Float, minor: Float)
		case line(start: Anchor, end: Anchor, width: Float)
		case arrow(start: Anchor, end: Anchor, shaftWidth: Float, headLength: Float, headWidth: Float, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil)
		case rect(width: Float, height: Float)
		case polygon(points: [SIMD3<Float>])
		case arc(radius: Float, startAngle: Float, endAngle: Float)
		case wall(start: Anchor, end: Anchor, spacing: Float, face: Unit)
	}
	public var vector: Vector

	public init(vector: Vector) {
		self.vector = vector
	}
}

public struct RenderStyleComponent: Component {
	public var color: Color
	public var opacity: Float
	public var hoverColor: Color?

	public init(color: Color, opacity: Float = 1, hoverColor: Color? = nil) {
		self.color = color
		self.opacity = opacity
		self.hoverColor = hoverColor
	}
}

public struct InteractionComponent: Component {
	public var hoverable: Bool
	public var draggable: Bool
	public var pauseAnimationOnHover: Bool
	public var hitPadding: Float
	public var onDragEnd: ((Entity) -> Void)?

	public init(hoverable: Bool = false, draggable: Bool = false, pauseAnimationOnHover: Bool = false, hitPadding: Float = 0, onDragEnd: ((Entity) -> Void)? = nil) {
		self.hoverable = hoverable
		self.draggable = draggable
		self.pauseAnimationOnHover = pauseAnimationOnHover
		self.hitPadding = hitPadding
		self.onDragEnd = onDragEnd
	}
}

public struct RevealOnHoverComponent: Component {
	public var trigger: Entity

	public init(trigger: Entity) {
		self.trigger = trigger
	}
}

public struct RevealOnTapComponent: Component {
	public var trigger: Entity

	public init(trigger: Entity) {
		self.trigger = trigger
	}
}

public struct PhysicsBodyComponent: Component {
	public enum Shape {
		case circle(radius: Float)
		case rect(width: Float, height: Float)
		case ellipse(major: Float, minor: Float)
	}
	public var shape: Shape

	public init(shape: Shape) {
		self.shape = shape
	}
}

public struct PhysicsMotionComponent: Component {
	public init() {}
}
