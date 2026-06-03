//
//  Helper.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

// MARK: - Anchor

public enum Anchor {
	case point(SIMD3<Float>)
	case entity(Entity, direction: Unit = .trailing, offset: Float = 0)

	public func resolve() -> SIMD3<Float> {
		switch self {
		case .point(let point):
			return point
		case .entity(let entity, let directionUnit, let offset):
			let direction = directionUnit.vector
			let basePos = entity.transform?.position ?? .zero
			var sizeOffset: SIMD3<Float> = .zero
			if let body = entity.components[PhysicsBodyComponent.self] {
				switch body.shape {
				case .circle(let radius):
					sizeOffset = direction * radius
				case .ellipse(let major, let minor):
					sizeOffset = SIMD3<Float>(direction.x * major, direction.y * minor, direction.z)
				case .rect(let width, let height):
					sizeOffset = SIMD3<Float>(direction.x * width / 2, direction.y * height / 2, direction.z)
				}
			}
			return basePos + sizeOffset + (direction * offset)
		}
	}
}

// MARK: - SIMD Helpers

public extension BinaryFloatingPoint {
	var i: SIMD3<Float> { SIMD3(Float(self), 0, 0) }
	var j: SIMD3<Float> { SIMD3(0, Float(self), 0) }
	var k: SIMD3<Float> { SIMD3(0, 0, Float(self)) }
}

public extension BinaryInteger {
	var i: SIMD3<Float> { SIMD3(Float(self), 0, 0) }
	var j: SIMD3<Float> { SIMD3(0, Float(self), 0) }
	var k: SIMD3<Float> { SIMD3(0, 0, Float(self)) }
}

public extension SIMD3 where Scalar == Float {
	static let origin = SIMD3<Float>.zero

	var length: Float {
		sqrt(x * x + y * y + z * z)
	}

	var lengthSquared: Float {
		x * x + y * y + z * z
	}

	var normalized: SIMD3<Float> {
		let len = length
		guard len > 0.000001 else { return .zero }
		return self / len
	}

	func distance(to other: SIMD3<Float>) -> Float {
		(self - other).length
	}

	var xy: SIMD2<Float> {
		SIMD2(x, y)
	}
	
	static let i: SIMD3<Float> = 1.i
	static let j: SIMD3<Float> = 1.j
	static let k: SIMD3<Float> = 1.k
}

public extension SIMD4 where Scalar == Float {
	// MARK: - Quaternion functionality (mimicking simd_quatf)
	
	static let identity = SIMD4<Float>(0, 0, 0, 1)

	init(angle: Float, axis: SIMD3<Float>) {
		let halfAngle = angle * 0.5
		let s = sin(halfAngle)
		let c = cos(halfAngle)
		let normalizedAxis = axis.normalized
		self.init(normalizedAxis.x * s, normalizedAxis.y * s, normalizedAxis.z * s, c)
	}

	var conjugate: SIMD4<Float> {
		SIMD4<Float>(-x, -y, -z, w)
	}

	var inverse: SIMD4<Float> {
		let lenSq = x*x + y*y + z*z + w*w
		guard lenSq > 0.000001 else { return self }
		return conjugate / lenSq
	}

	static func *(lhs: SIMD4<Float>, rhs: SIMD4<Float>) -> SIMD4<Float> {
		let x1 = lhs.x, y1 = lhs.y, z1 = lhs.z, w1 = lhs.w
		let x2 = rhs.x, y2 = rhs.y, z2 = rhs.z, w2 = rhs.w
		
		return SIMD4<Float>(
			w1*x2 + x1*w2 + y1*z2 - z1*y2,
			w1*y2 - x1*z2 + y1*w2 + z1*x2,
			w1*z2 + x1*y2 - y1*x2 + z1*w2,
			w1*w2 - x1*x2 - y1*y2 - z1*z2
		)
	}
	
	func act(_ v: SIMD3<Float>) -> SIMD3<Float> {
		let qVec = SIMD3<Float>(x, y, z)
		let uv = cross(qVec, v)
		let uuv = cross(qVec, uv)
		return v + ((uv * w) + uuv) * 2.0
	}
}

public func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
	SIMD3<Float>(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	)
}

public struct Unit: Sendable {
	public let vector: SIMD3<Float>

	public init(vector: SIMD3<Float>) {
		self.vector = vector.normalized
	}

	public static let top = Unit(vector: .init(0, 1, 0))
	public static let bottom = Unit(vector: .init(0, -1, 0))
	public static let forward = Unit(vector: .init(0, 0, 1))
	public static let backward = Unit(vector: .init(0, 0, -1))
	public static let trailing = Unit(vector: .init(1, 0, 0))
	public static let leading = Unit(vector: .init(-1, 0, 0))
}

// MARK: - Math Utilities

public func clamp(_ value: Float, min minimum: Float, max maximum: Float) -> Float {
	Swift.max(minimum, Swift.min(maximum, value))
}

public func distanceFromPointToSegment(_ point: SIMD3<Float>, _ start: SIMD3<Float>, _ end: SIMD3<Float>) -> Float {
	let segment = end - start
	let lengthSq = (segment * segment).sum()
	guard lengthSq > 0.000001 else {
		return point.distance(to: start)
	}
	let diff = point - start
	let dot = (diff * segment).sum()
	let t = clamp(dot / lengthSq, min: 0, max: 1)
	let projection = start + segment * t
	return point.distance(to: projection)
}

// MARK: - Render Primitives

public enum ArrowShape: String {
	case triangle
	case kite
	case circle
	case curvedTriangle = "curved_triangle"
}

public enum RenderPrimitive {
	case circle(center: SIMD3<Float>, radius: Float, color: Color)
	case ellipse(center: SIMD3<Float>, major: Float, minor: Float, rotation: Float, color: Color)
	case line(start: SIMD3<Float>, end: SIMD3<Float>, width: Float, color: Color)
	case arrow(start: SIMD3<Float>, end: SIMD3<Float>, shaftWidth: Float, headLength: Float, headWidth: Float, tipShape: ArrowShape?, tailShape: ArrowShape?, color: Color)
	case rect(center: SIMD3<Float>, width: Float, height: Float, rotation: Float, color: Color)
	case polygon(points: [SIMD3<Float>], color: Color)
	case arc(center: SIMD3<Float>, radius: Float, startAngle: Float, endAngle: Float, color: Color)
}

public struct SceneSnapshot {
	public var primitives: [RenderPrimitive]

	public init(primitives: [RenderPrimitive] = []) {
		self.primitives = primitives
	}
}


