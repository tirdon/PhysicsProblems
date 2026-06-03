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
	case entity(Entity, direction: SIMD3<Float> = .trailing, offset: Float = 0)

	public func resolve() -> SIMD3<Float> {
		switch self {
		case .point(let point):
			return point
		case .entity(let entity, var direction, let offset):
			direction = direction.normalized
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
	
	static var up: SIMD3<Float> { .init(0, 1, 0) }
	static var down: SIMD3<Float> { .init(0, -1, 0) }
	static var forward: SIMD3<Float> { .init(0, 0, 1) }
	static var backward: SIMD3<Float> { .init(0, 0, -1) }
	static var right: SIMD3<Float> { .init(1, 0, 0) }
	static var left: SIMD3<Float> { .init(-1, 0, 0) }
	static var trailing: SIMD3<Float> { .init(1, 0, 0) }
	static var leading: SIMD3<Float> { .init(-1, 0, 0) }
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
}

public struct SceneSnapshot {
	public var primitives: [RenderPrimitive]

	public init(primitives: [RenderPrimitive] = []) {
		self.primitives = primitives
	}
}


