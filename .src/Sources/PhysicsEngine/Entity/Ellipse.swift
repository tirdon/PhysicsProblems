//
//  Ellipse.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 3/6/2569 BE.
//

public class Ellipse: Entity {
	public var vector: VectorComponent? {
		get { components[VectorComponent.self] }
		set { components[VectorComponent.self] = newValue }
	}

	public var style: RenderStyleComponent? {
		get { components[RenderStyleComponent.self] }
		set { components[RenderStyleComponent.self] = newValue }
	}

	@discardableResult
	public func color(_ color: Color) -> Self {
		if var s = style {
			s.color = color
			style = s
		} else {
			style = RenderStyleComponent(color: color)
		}
		return self
	}

	public override init() {
		super.init()
	}
}

public class Circle: Ellipse {
	public override init() {
		super.init()
		// Default circle vector
		self.vector = VectorComponent(vector: .circle(radius: 0.12))
		self.style = RenderStyleComponent(color: .bob)
	}
}
