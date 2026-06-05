//
//  Entity+Path.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 5/6/2569 BE.
//

open class PathEntity: Entity {
	public var vector: VectorComponent? {
		get { components[VectorComponent.self] }
		set { components[VectorComponent.self] = newValue }
	}

	public var style: RenderStyleComponent? {
		get { components[RenderStyleComponent.self] }
		set { components[RenderStyleComponent.self] = newValue }
	}
	
	@discardableResult
	private func mutateStyle(_ modify: (inout RenderStyleComponent) -> Void) -> Self {
		var s = style ?? RenderStyleComponent(color: .clear)
		modify(&s)
		style = s
		return self
	}

	@discardableResult
	public func color(_ color: Color) -> Self {
		mutateStyle { $0.color = color }
	}
	
	@discardableResult
	public func opacity(_ opacity: Float) -> Self {
		mutateStyle { $0.opacity = opacity }
	}

	@discardableResult
	public func stroke(_ color: Color, width: Float = 1.0) -> Self {
		mutateStyle { $0.strokeColor = color; $0.strokeWidth = width }
	}

	@discardableResult
	public func stroke(style strokeStyle: StrokeStyle) -> Self {
		mutateStyle { $0.strokeStyle = strokeStyle }
	}

	@discardableResult
	public func stroke(cap: StrokeCap) -> Self {
		mutateStyle { $0.strokeCap = cap }
	}
}
