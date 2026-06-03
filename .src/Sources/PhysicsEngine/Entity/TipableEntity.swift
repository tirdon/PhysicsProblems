//
//  TipableEntity.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 2/6/2569 BE.
//

public class Arrow: PathEntity {
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
		self.style = RenderStyleComponent(color: .white)
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
		self.style = RenderStyleComponent(color: .white)
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
		self.style = RenderStyleComponent(color: .white)
	}
}
