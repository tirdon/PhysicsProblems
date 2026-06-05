//
//  Entity+SimpleGeometry.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

import Foundation

//MARK: Arc
public class Arc: PathEntity {
	public var radius: Float {
		didSet { updateVector() }
	}
	public var startAngle: Float {
		didSet { updateVector() }
	}
	public var endAngle: Float {
		didSet { updateVector() }
	}
	
	private func updateVector() {
		self.vector = VectorComponent(vector: .arc(radius: radius, startAngle: startAngle, endAngle: endAngle))
	}
	
	public var start: SIMD3<Float> {
		let rot = self.rotation
		let s = self.transform?.scale ?? .one
		let lx = radius * cos(startAngle) * s.x
		let ly = radius * sin(startAngle) * s.y
		return position + SIMD3<Float>(lx * cos(rot) - ly * sin(rot), lx * sin(rot) + ly * cos(rot), 0)
	}
	
	public var target: SIMD3<Float> {
		let rot = self.rotation
		let s = self.transform?.scale ?? .one
		let lx = radius * cos(endAngle) * s.x
		let ly = radius * sin(endAngle) * s.y
		return position + SIMD3<Float>(lx * cos(rot) - ly * sin(rot), lx * sin(rot) + ly * cos(rot), 0)
	}

	public init(radius: Float, startAngle: Float, endAngle: Float) {
		self.radius = radius
		self.startAngle = startAngle
		self.endAngle = endAngle
		super.init()
		updateVector()
	}

	public convenience init(at: SIMD3<Float>, target: SIMD3<Float>, radius: Float, largeArc: Bool = false, sweep: Bool = true) {
		let params = calculateArcParameters(at: at, target: target, radius: radius, largeArc: largeArc, sweep: sweep)
		self.init(radius: params.actualRadius, startAngle: params.startAngle, endAngle: params.endAngle)
		self.position = params.center
	}

	public convenience init(at: Anchor, target: Anchor, radius: Float, largeArc: Bool = false, sweep: Bool = true) {
		self.init(at: at.resolve(), target: target.resolve(), radius: radius, largeArc: largeArc, sweep: sweep)
	}

	public override init() {
		self.radius = 0.1
		self.startAngle = 0
		self.endAngle = .pi
		super.init()
		updateVector()
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
	public init(at: Anchor, target: Anchor, spacing: Float = 0.1, face: Unit = .top) {
		super.init()
		self.vector = VectorComponent(vector: .wall(start: at, end: target, spacing: spacing, face: face))
	}

	public convenience init(at: SIMD3<Float>, target: SIMD3<Float>, spacing: Float = 0.1, face: Unit = .top) {
		self.init(at: .point(at), target: .point(target), spacing: spacing, face: face)
	}
	
	public override convenience init() {
		self.init(at: SIMD3<Float>(-1, 0, 0), target: SIMD3<Float>(1, 0, 0))
	}
}
