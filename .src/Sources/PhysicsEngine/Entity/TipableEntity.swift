//
//  TipableEntity.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 2/6/2569 BE.
//

public class Arrow: Entity {
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

	public init(tip: ArrowShape?, tail: ArrowShape?) {
		super.init()
		self.vector = VectorComponent(vector: .arrow(
			start: .point(.zero),
			end: .point(SIMD3<Float>(0, -1, 0)),
			shaftWidth: 0.025,
			headLength: 0.12,
			headWidth: 0.11,
			tipShape: tip,
			tailShape: tail
		))
		self.style = RenderStyleComponent(color: .pivot)
	}

	public override init() {
		super.init()
		self.vector = VectorComponent(vector: .arrow(
			start: .point(.zero),
			end: .point(SIMD3<Float>(0, -1, 0)),
			shaftWidth: 0.025,
			headLength: 0.12,
			headWidth: 0.11,
			tipShape: .triangle,
			tailShape: nil
		))
		self.style = RenderStyleComponent(color: .pivot)
	}
}

public class Line: Arrow {
	public override init() {
		super.init()
		// Override with a line vector instead of arrow
		self.vector = VectorComponent(vector: .line(
			start: .point(.zero),
			end: .point(SIMD3<Float>(0, -1, 0)),
			width: 0.018
		))
		self.style = RenderStyleComponent(color: .string)
	}
}
