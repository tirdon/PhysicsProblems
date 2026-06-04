//
//  SimpleGeometry.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

//MARK: Arc
public class Arc: PathEntity {
	public init(radius: Float, startAngle: Float, endAngle: Float) {
		super.init()
		self.vector = VectorComponent(vector: .arc(radius: radius, startAngle: startAngle, endAngle: endAngle))
	}

	public override init() {
		super.init()
		self.vector = VectorComponent(vector: .arc(radius: 0.1, startAngle: 0, endAngle: .pi))
	}
}


public class Ellipse: Arc {
	public init(major: Float, minor: Float) {
		super.init(radius: major, startAngle: 0, endAngle: 2 * .pi)
		self.vector = VectorComponent(vector: .ellipse(major: major, minor: minor))
		self.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(shape: .ellipse(major: major, minor: minor))
	}
	
	public override init() {
		super.init()
		self.vector = VectorComponent(vector: .circle(radius: 1.0))
	}
}

public class Circle: Ellipse {
	public override init() {
		super.init()
		// Default circle vector
	}
}

//MARK: Polygram
public class Polygon: PathEntity {
	public init(points: [SIMD3<Float>]) {
		super.init()
		self.vector = VectorComponent(vector: .polygon(points: points))
	}
	
	public override init() {
		super.init()
		self.vector = VectorComponent(vector: .polygon(points: []))
	}
}

//MARK: Quadrilateral
public class Rectangle: Polygon {
	public init(width: Float, height: Float) {
		let w2 = width / 2
		let h2 = height / 2
		super.init(points: [
			SIMD3<Float>(-w2, -h2, 0),
			SIMD3<Float>(w2, -h2, 0),
			SIMD3<Float>(w2, h2, 0),
			SIMD3<Float>(-w2, h2, 0)
		])
		self.vector = VectorComponent(vector: .rect(width: width, height: height))
		self.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(shape: .rect(width: width, height: height))
	}
	
	public override convenience init() {
		self.init(width: 0.2, height: 0.2)
	}
}

public class Square: Rectangle {
	public init(side: Float) {
		super.init(width: side, height: side)
	}
}

public class Kite: Polygon {
	public init(width: Float, height: Float) {
		let w2 = width / 2
		let h2 = height / 2
		super.init(points: [
			SIMD3<Float>(0, -h2, 0),
			SIMD3<Float>(w2, 0, 0),
			SIMD3<Float>(0, h2, 0),
			SIMD3<Float>(-w2, 0, 0)
		])
	}
	
	public override convenience init() {
		self.init(width: 0.2, height: 0.4)
	}
}

//MARK: Triangle
public class Triangle: Polygon {
	public init(base: Float, height: Float) {
		let b2 = base / 2
		let h2 = height / 2
		super.init(points: [
			SIMD3<Float>(-b2, -h2, 0),
			SIMD3<Float>(b2, -h2, 0),
			SIMD3<Float>(0, h2, 0)
		])
	}
	
	public override convenience init() {
		self.init(base: 0.2, height: 0.2)
	}
}

//MARK: Wall
public class Wall: PathEntity {
	public init(start: Anchor, end: Anchor, spacing: Float = 0.1, face: Unit = .top) {
		super.init()
		self.vector = VectorComponent(vector: .wall(start: start, end: end, spacing: spacing, face: face))
	}

	public convenience init(start: SIMD3<Float>, end: SIMD3<Float>, spacing: Float = 0.1, face: Unit = .top) {
		self.init(start: .point(start), end: .point(end), spacing: spacing, face: face)
	}
	
	public override convenience init() {
		self.init(start: SIMD3<Float>(-1, 0, 0), end: SIMD3<Float>(1, 0, 0))
	}
}
