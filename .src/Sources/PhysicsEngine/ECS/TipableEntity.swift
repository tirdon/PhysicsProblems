//
//  TipableEntity.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 2/6/2569 BE.
//

public class Arrow: Arc {
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
	}
}

//MARK: Curve
public class CurvedArrow: Arc {
	public init(radius: Float, startAngle: Float, endAngle: Float, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil) {
		super.init(radius: radius, startAngle: startAngle, endAngle: endAngle)
		// Curved arrow shares Arc geometry, but needs arrowheads. 
		// For now we map it to arc vector.
	}
	
	public override init() {
		super.init(radius: 0.2, startAngle: 0, endAngle: .pi)
	}
}
