//
//  TipableEntity.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 2/6/2569 BE.
//
import Foundation

public class Arrow: Arc {
	fileprivate var _localStart: SIMD3<Float> = .zero
	fileprivate var _localTarget: SIMD3<Float> = SIMD3<Float>(0, -1, 0)
	
	public init(tip: ArrowShape?, tail: ArrowShape?) {
		super.init()
		self.vector = VectorComponent(vector: .arrow(
			start: .point(_localStart),
			end: .point(_localTarget),
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
			start: .point(_localStart),
			end: .point(_localTarget),
			shaftWidth: 0.025,
			headLength: 0.12,
			headWidth: 0.11,
			tipShape: .triangle,
			tailShape: nil
		))
	}
	
	public override var start: SIMD3<Float> {
		let rot = self.rotation
		let s = self.transform?.scale ?? .one
		return position + SIMD3<Float>(_localStart.x * cos(rot) * s.x - _localStart.y * sin(rot) * s.y, _localStart.x * sin(rot) * s.x + _localStart.y * cos(rot) * s.y, 0)
	}
	
	public override var target: SIMD3<Float> {
		let rot = self.rotation
		let s = self.transform?.scale ?? .one
		return position + SIMD3<Float>(_localTarget.x * cos(rot) * s.x - _localTarget.y * sin(rot) * s.y, _localTarget.x * sin(rot) * s.x + _localTarget.y * cos(rot) * s.y, 0)
	}
	
	public func updatePoints(start: SIMD3<Float>, target: SIMD3<Float>) {
		self._localStart = start
		self._localTarget = target
	}
}

public class Line: Arrow {
	public init(start: SIMD3<Float>,end target: SIMD3<Float>) {
		super.init()
		self.updatePoints(start: start, target: target)
		self.vector = VectorComponent(vector: .line(
			start: .point(start),
			end: .point(target),
			width: 0.018
		))
	}
	
	public init(start: Entity,end target: Entity) {
		super.init()
		self.updatePoints(start: start.position, target: target.position)
		self.vector = VectorComponent(vector: .line(
			start: .point(start.position),
			end: .point(target.position),
			width: 0.018
		))
	}
	
	public override init() {
		super.init()
		self.updatePoints(start: .zero, target: SIMD3<Float>(0, -1, 0))
		// Override with a line vector instead of arrow
		self.vector = VectorComponent(vector: .line(
			start: .point(.zero),
			end: .point(SIMD3<Float>(0, -1, 0)),
			width: 0.018
		))
	}

	public var length: Float {
		get {
			let d = _localTarget - _localStart
			return sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
		}
		set {
			let d = _localTarget - _localStart
			let dist = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
			let dir = dist == 0 ? SIMD3<Float>(0, -1, 0) : SIMD3<Float>(d.x / dist, d.y / dist, d.z / dist)
			let newTarget = _localStart + dir * newValue
			self.updatePoints(start: _localStart, target: newTarget)
			self.vector = VectorComponent(vector: .line(
				start: .point(_localStart),
				end: .point(_localTarget),
				width: 0.018
			))
		}
	}
}

//MARK: Curve
public class CurvedArrow: Arc {
	public init(radius: Float, startAngle: Float, endAngle: Float, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil) {
		super.init(radius: radius, startAngle: startAngle, endAngle: endAngle)
		// Curved arrow shares Arc geometry, but needs arrowheads. 
		// For now we map it to arc vector.
	}

	public convenience init(at: SIMD3<Float>, target: SIMD3<Float>, radius: Float, largeArc: Bool = false, sweep: Bool = true, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil) {
		let params = calculateArcParameters(at: at, target: target, radius: radius, largeArc: largeArc, sweep: sweep)
		self.init(radius: params.actualRadius, startAngle: params.startAngle, endAngle: params.endAngle, tipShape: tipShape, tailShape: tailShape)
		self.position = params.center
	}

	public convenience init(at: Anchor, target: Anchor, radius: Float, largeArc: Bool = false, sweep: Bool = true, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil) {
		self.init(at: at.resolve(), target: target.resolve(), radius: radius, largeArc: largeArc, sweep: sweep, tipShape: tipShape, tailShape: tailShape)
	}
	
	public override init() {
		super.init(radius: 0.2, startAngle: 0, endAngle: .pi)
	}
}
