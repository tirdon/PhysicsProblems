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
	public var scale: SIMD3<Float>

	public init(position: SIMD3<Float> = .zero, orientation: SIMD4<Float> = .identity, scale: SIMD3<Float> = .one) {
		self.position = position
		self.orientation = orientation
		self.scale = scale
	}
}

public struct VectorComponent: Component {
	public enum Vector {
		case path(VectorPath)
		case circle(radius: Float)
		case ellipse(major: Float, minor: Float)
		case line(start: Anchor, end: Anchor, width: Float)
		case arrow(start: Anchor, end: Anchor, shaftWidth: Float, headLength: Float, headWidth: Float, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil)
		case rect(width: Float, height: Float)
		case polygon(points: [SIMD3<Float>])
		case arc(radius: Float, startAngle: Float, endAngle: Float)
		case wall(start: Anchor, end: Anchor, spacing: Float, face: Unit)

		public var path: VectorPath {
			switch self {
			case .path(let path):
				return path
			case .circle(let radius):
				return .circle(radius: radius)
			case .ellipse(let major, let minor):
				return .ellipse(major: major, minor: minor)
			case .line(let start, let end, let width):
				return .line(start: start, end: end, width: width)
			case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth, let tipShape, let tailShape):
				return .arrow(
					start: start,
					end: end,
					shaftWidth: shaftWidth,
					headLength: headLength,
					headWidth: headWidth,
					tipShape: tipShape,
					tailShape: tailShape
				)
			case .rect(let width, let height):
				return .rect(width: width, height: height)
			case .polygon(let points):
				return .polygon(points: points)
			case .arc(let radius, let startAngle, let endAngle):
				return .arc(radius: radius, startAngle: startAngle, endAngle: endAngle)
			case .wall(let start, let end, let spacing, let face):
				return .wall(start: start, end: end, spacing: spacing, face: face)
			}
		}
	}
	public var path: VectorPath
	public var segments: Int8 = 64

	public var vector: Vector {
		get { .path(path) }
		set { path = newValue.path }
	}

	public init(vector: Vector, segments: Int8 = 64) {
		self.path = vector.path
		self.segments = segments
	}

	public init(path: VectorPath, segments: Int8 = 64) {
		self.path = path
		self.segments = segments
	}
}

public enum StrokeStyle: String {
	case solid
	case dashed
	case dotted
}

public enum StrokeCap: String {
	case butt
	case round
	case square
}

public struct RenderStyleComponent: Component {
	public var color: Color
	public var opacity: Float
	public var hoverColor: Color?
	public var strokeColor: Color?
	public var strokeWidth: Float
	public var strokeStyle: StrokeStyle
	public var strokeCap: StrokeCap

	public init(color: Color, opacity: Float = 1, hoverColor: Color? = nil, strokeColor: Color? = nil, strokeWidth: Float = 1, strokeStyle: StrokeStyle = .solid, strokeCap: StrokeCap = .butt) {
		self.color = color
		self.opacity = opacity
		self.hoverColor = hoverColor
		self.strokeColor = strokeColor
		self.strokeWidth = strokeWidth
		self.strokeStyle = strokeStyle
		self.strokeCap = strokeCap
	}
}

public enum ShadingMode: String {
	case flat
	case smooth
}

public struct MeshComponent: Component {
	public var vertices: [SIMD3<Float>]
	public var normals: [SIMD3<Float>]
	public var indices: [UInt16]
	public var shading: ShadingMode

	public init(vertices: [SIMD3<Float>], normals: [SIMD3<Float>] = [], indices: [UInt16] = [], shading: ShadingMode = .smooth) {
		self.vertices = vertices
		self.normals = normals
		self.indices = indices
		self.shading = shading
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

public struct PhysicsBodyComponent: Component {
	public enum Shape {
		case circle(radius: Float)
		case rect(width: Float, height: Float)
		case ellipse(major: Float, minor: Float)
		case boundingBox(width: Float, height: Float, depth: Float)
		case boundingSphere(radius: Float)
	}
	public var shape: Shape
	public var offset: SIMD3<Float>

	public init(shape: Shape, offset: SIMD3<Float> = .zero) {
		self.shape = shape
		self.offset = offset
	}
}

public struct BoundingVisualizerComponent: Component {
	public weak var target: Entity?
	public init(target: Entity? = nil) {
		self.target = target
	}
}
