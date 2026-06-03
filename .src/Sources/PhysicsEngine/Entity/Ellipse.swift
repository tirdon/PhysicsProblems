//
//  Ellipse.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

public class Ellipse: PathEntity {
	
	public init(major: Float, minor: Float) {
		super.init()
	}
	
	public override init() {
		super.init()
		self.vector = VectorComponent(vector: .circle(radius: 0.12))
		self.style = RenderStyleComponent(color: .green)
	}
}

public class Circle: Ellipse {
	public override init() {
		super.init()
		// Default circle vector
	}
}
