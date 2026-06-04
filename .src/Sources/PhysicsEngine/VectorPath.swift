//
//  VectorPath.swift
//  PhysicsProblems
//

import Foundation

public struct RasterizedVectorContour {
	public var points: [SIMD3<Float>]
	public var isClosed: Bool

	public init(points: [SIMD3<Float>], isClosed: Bool) {
		self.points = points
		self.isClosed = isClosed
	}
}

public struct VectorPath {
	public enum BooleanOperation {
		case union
		case intersection
		case difference
		case symmetricDifference
	}

	public enum WindingMode: String {
		case nonZero = "non_zero"
		case evenOdd = "even_odd"
	}

	public enum CoordinateSpace {
		case local
		case world
	}

	public enum Drawing {
		case fill
		case stroke(width: Float)
	}

	public enum Element {
		case move(to: Anchor)
		case line(to: Anchor)
		case quadraticCurve(to: Anchor, control: Anchor)
		case cubicCurve(to: Anchor, control1: Anchor, control2: Anchor)
		case ellipse(center: Anchor, major: Float, minor: Float, rotation: Float, startAngle: Float, endAngle: Float)
		case arrow(start: Anchor, end: Anchor, shaftWidth: Float, headLength: Float, headWidth: Float, tipShape: ArrowShape?, tailShape: ArrowShape?)
		case wall(start: Anchor, end: Anchor, spacing: Float, face: Unit)
		case close
	}

	public enum BezierSegment {
		case line(to: Anchor)
		case quadraticCurve(to: Anchor, control: Anchor)
		case cubicCurve(to: Anchor, control1: Anchor, control2: Anchor)
	}

	public var elements: [Element]
	public var coordinateSpace: CoordinateSpace
	public var drawing: Drawing
	public var windingMode: WindingMode

	public init(elements: [Element], coordinateSpace: CoordinateSpace = .local, drawing: Drawing = .fill, windingMode: WindingMode = .nonZero) {
		self.elements = elements
		self.coordinateSpace = coordinateSpace
		self.drawing = drawing
		self.windingMode = windingMode
	}

	public var strokeWidth: Float? {
		if case .stroke(let width) = drawing {
			return width
		}
		return nil
	}

	public func rasterize(curveSteps: Int = 32) -> [SIMD3<Float>] {
		rasterizedContours(curveSteps: curveSteps).flatMap(\.points)
	}

	public func rasterize(sampleCount: Int, curveSteps: Int = 32) -> [SIMD3<Float>] {
		let contours = rasterizedContours(curveSteps: curveSteps)
		let points = contours.flatMap(\.points)
		let closed = contours.first?.isClosed ?? false
		return Self.resample(points, count: sampleCount, closed: closed)
	}

	public func rasterizedContours(curveSteps: Int = 32) -> [RasterizedVectorContour] {
		let safeSteps = max(curveSteps, 1)
		var contours: [RasterizedVectorContour] = []
		var current: [SIMD3<Float>] = []
		var contourStart: SIMD3<Float>?
		var currentPoint: SIMD3<Float>?

		func finishCurrent(closed: Bool = false) {
			guard !current.isEmpty else { return }
			contours.append(RasterizedVectorContour(points: current, isClosed: closed))
			current.removeAll()
			contourStart = nil
			currentPoint = nil
		}

		for element in elements {
			switch element {
			case .move(let anchor):
				finishCurrent()
				let point = anchor.resolve()
				current = [point]
				contourStart = point
				currentPoint = point

			case .line(let anchor):
				let point = anchor.resolve()
				if current.isEmpty {
					current = [point]
					contourStart = point
				} else {
					current.append(point)
				}
				currentPoint = point

			case .quadraticCurve(let anchor, let control):
				let end = anchor.resolve()
				let controlPoint = control.resolve()
				let start = currentPoint ?? controlPoint
				if current.isEmpty {
					current = [start]
					contourStart = start
				}
				for step in 1...safeSteps {
					let t = Float(step) / Float(safeSteps)
					current.append(Self.quadraticPoint(start: start, control: controlPoint, end: end, t: t))
				}
				currentPoint = end

			case .cubicCurve(let anchor, let control1, let control2):
				let end = anchor.resolve()
				let c1 = control1.resolve()
				let c2 = control2.resolve()
				let start = currentPoint ?? c1
				if current.isEmpty {
					current = [start]
					contourStart = start
				}
				for step in 1...safeSteps {
					let t = Float(step) / Float(safeSteps)
					current.append(Self.cubicPoint(start: start, control1: c1, control2: c2, end: end, t: t))
				}
				currentPoint = end

			case .ellipse(let center, let major, let minor, let rotation, let startAngle, let endAngle):
				let points = Self.ellipsePoints(
					center: center.resolve(),
					major: major,
					minor: minor,
					rotation: rotation,
					startAngle: startAngle,
					endAngle: endAngle,
					curveSteps: safeSteps
				)
				if current.isEmpty {
					current = points
					contourStart = points.first
				} else {
					current.append(contentsOf: points)
				}
				currentPoint = points.last

			case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth, let tipShape, let tailShape):
				finishCurrent()
				contours.append(contentsOf: Self.arrowContours(
					start: start.resolve(),
					end: end.resolve(),
					shaftWidth: shaftWidth,
					headLength: headLength,
					headWidth: headWidth,
					tipShape: tipShape,
					tailShape: tailShape,
					curveSteps: safeSteps
				))

			case .wall(let start, let end, let spacing, let face):
				finishCurrent()
				contours.append(contentsOf: Self.wallContours(
					start: start.resolve(),
					end: end.resolve(),
					spacing: spacing,
					face: face.vector
				))

			case .close:
				if let first = contourStart {
					currentPoint = first
				}
				finishCurrent(closed: true)
			}
		}

		finishCurrent()
		return contours
	}

	public func bounds(curveSteps: Int = 32) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
		let points = rasterize(curveSteps: curveSteps)
		guard var minPoint = points.first, var maxPoint = points.first else { return nil }
		for point in points.dropFirst() {
			minPoint.x = min(minPoint.x, point.x)
			minPoint.y = min(minPoint.y, point.y)
			minPoint.z = min(minPoint.z, point.z)
			maxPoint.x = max(maxPoint.x, point.x)
			maxPoint.y = max(maxPoint.y, point.y)
			maxPoint.z = max(maxPoint.z, point.z)
		}
		return (minPoint, maxPoint)
	}

	public func interpolated(to target: VectorPath, progress: Float, samples: Int = 64) -> VectorPath {
		let count = max(samples, 2)
		let t = clamp(progress, min: 0, max: 1)
		let sourcePoints = rasterize(sampleCount: count)
		let targetPoints = target.rasterize(sampleCount: count)
		let points = zip(sourcePoints, targetPoints).map { source, target in
			source + (target - source) * t
		}
		let isClosed = (rasterizedContours().first?.isClosed ?? false) || (target.rasterizedContours().first?.isClosed ?? false)
		return VectorPath.contour(points: points, isClosed: isClosed, coordinateSpace: coordinateSpace, drawing: isClosed ? .fill : drawing, windingMode: windingMode)
	}

	public func contains(_ point: SIMD3<Float>, tolerance: Float = 0.001, curveSteps: Int = 32) -> Bool {
		let contours = rasterizedContours(curveSteps: curveSteps)
		switch drawing {
		case .fill:
			var evenOddInside = false
			var nonZeroWinding = 0
			for contour in contours where contour.isClosed && contour.points.count >= 3 {
				if tolerance > 0, Self.point(point, isWithin: tolerance, of: contour) {
					return true
				}
				switch windingMode {
				case .evenOdd:
					if Self.pointInPolygon(point, contour.points) {
						evenOddInside.toggle()
					}
				case .nonZero:
					nonZeroWinding += Self.windingNumber(of: point, in: contour.points)
				}
			}
			return windingMode == .evenOdd ? evenOddInside : nonZeroWinding != 0

		case .stroke(let width):
			let threshold = max(width * 0.5 + tolerance, tolerance)
			for contour in contours where contour.points.count >= 2 {
				if Self.point(point, isWithin: threshold, of: contour) {
					return true
				}
			}
			return false
		}
	}

	public func applying(_ operation: BooleanOperation, with other: VectorPath, resolution: Int = 96, curveSteps: Int = 32) -> VectorPath {
		Self.boolean(self, other, operation: operation, resolution: resolution, curveSteps: curveSteps)
	}

	public func union(_ other: VectorPath, resolution: Int = 96, curveSteps: Int = 32) -> VectorPath {
		applying(.union, with: other, resolution: resolution, curveSteps: curveSteps)
	}

	public func intersect(_ other: VectorPath, resolution: Int = 96, curveSteps: Int = 32) -> VectorPath {
		applying(.intersection, with: other, resolution: resolution, curveSteps: curveSteps)
	}

	public func subtract(_ other: VectorPath, resolution: Int = 96, curveSteps: Int = 32) -> VectorPath {
		applying(.difference, with: other, resolution: resolution, curveSteps: curveSteps)
	}

	public func symmetricDifference(_ other: VectorPath, resolution: Int = 96, curveSteps: Int = 32) -> VectorPath {
		applying(.symmetricDifference, with: other, resolution: resolution, curveSteps: curveSteps)
	}
}

public extension VectorPath {
	typealias BezierPath = VectorPath

	init(start: Anchor, coordinateSpace: CoordinateSpace = .local, drawing: Drawing = .stroke(width: 0.018), windingMode: WindingMode = .nonZero) {
		self.init(elements: [.move(to: start)], coordinateSpace: coordinateSpace, drawing: drawing, windingMode: windingMode)
	}

	mutating func move(to point: Anchor) {
		elements.append(.move(to: point))
	}

	mutating func line(to point: Anchor) {
		elements.append(.line(to: point))
	}

	mutating func quadraticCurve(to point: Anchor, control: Anchor) {
		elements.append(.quadraticCurve(to: point, control: control))
	}

	mutating func cubicCurve(to point: Anchor, control1: Anchor, control2: Anchor) {
		elements.append(.cubicCurve(to: point, control1: control1, control2: control2))
	}

	mutating func close() {
		elements.append(.close)
	}

	static func bezier(start: Anchor, segments: [BezierSegment], closed: Bool = false, coordinateSpace: CoordinateSpace = .local, drawing: Drawing = .stroke(width: 0.018), windingMode: WindingMode = .nonZero) -> VectorPath {
		var elements: [Element] = [.move(to: start)]
		for segment in segments {
			switch segment {
			case .line(let point):
				elements.append(.line(to: point))
			case .quadraticCurve(let point, let control):
				elements.append(.quadraticCurve(to: point, control: control))
			case .cubicCurve(let point, let control1, let control2):
				elements.append(.cubicCurve(to: point, control1: control1, control2: control2))
			}
		}
		if closed {
			elements.append(.close)
		}
		return VectorPath(elements: elements, coordinateSpace: coordinateSpace, drawing: drawing, windingMode: windingMode)
	}

	static func contour(points: [SIMD3<Float>], isClosed: Bool, coordinateSpace: CoordinateSpace = .local, drawing: Drawing = .fill, windingMode: WindingMode = .nonZero) -> VectorPath {
		guard let first = points.first else {
			return VectorPath(elements: [], coordinateSpace: coordinateSpace, drawing: drawing, windingMode: windingMode)
		}
		var elements: [Element] = [.move(to: .point(first))]
		for point in points.dropFirst() {
			elements.append(.line(to: .point(point)))
		}
		if isClosed {
			elements.append(.close)
		}
		return VectorPath(elements: elements, coordinateSpace: coordinateSpace, drawing: drawing, windingMode: windingMode)
	}

	static func contours(_ contours: [RasterizedVectorContour], coordinateSpace: CoordinateSpace = .local, drawing: Drawing = .fill, windingMode: WindingMode = .nonZero) -> VectorPath {
		var elements: [Element] = []
		for contour in contours {
			guard let first = contour.points.first else { continue }
			elements.append(.move(to: .point(first)))
			for point in contour.points.dropFirst() {
				elements.append(.line(to: .point(point)))
			}
			if contour.isClosed {
				elements.append(.close)
			}
		}
		return VectorPath(elements: elements, coordinateSpace: coordinateSpace, drawing: drawing, windingMode: windingMode)
	}

	static func circle(radius: Float) -> VectorPath {
		VectorPath(elements: [
			.ellipse(center: .point(.zero), major: radius, minor: radius, rotation: 0, startAngle: 0, endAngle: 2 * Float.pi),
			.close
		])
	}

	static func ellipse(major: Float, minor: Float) -> VectorPath {
		VectorPath(elements: [
			.ellipse(center: .point(.zero), major: major, minor: minor, rotation: 0, startAngle: 0, endAngle: 2 * Float.pi),
			.close
		])
	}

	static func line(start: Anchor, end: Anchor, width: Float) -> VectorPath {
		VectorPath(elements: [
			.move(to: start),
			.line(to: end)
		], coordinateSpace: .world, drawing: .stroke(width: width))
	}

	static func arrow(start: Anchor, end: Anchor, shaftWidth: Float, headLength: Float, headWidth: Float, tipShape: ArrowShape? = .triangle, tailShape: ArrowShape? = nil) -> VectorPath {
		VectorPath(elements: [
			.arrow(start: start, end: end, shaftWidth: shaftWidth, headLength: headLength, headWidth: headWidth, tipShape: tipShape, tailShape: tailShape)
		], coordinateSpace: .world)
	}

	static func rect(width: Float, height: Float) -> VectorPath {
		let w2 = width / 2
		let h2 = height / 2
		return polygon(points: [
			SIMD3<Float>(-w2, -h2, 0),
			SIMD3<Float>(w2, -h2, 0),
			SIMD3<Float>(w2, h2, 0),
			SIMD3<Float>(-w2, h2, 0)
		])
	}

	static func polygon(points: [SIMD3<Float>]) -> VectorPath {
		contour(points: points, isClosed: true)
	}

	static func arc(radius: Float, startAngle: Float, endAngle: Float) -> VectorPath {
		VectorPath(elements: [
			.ellipse(center: .point(.zero), major: radius, minor: radius, rotation: 0, startAngle: startAngle, endAngle: endAngle)
		], drawing: .stroke(width: 0.018))
	}

	static func wall(start: Anchor, end: Anchor, spacing: Float, face: Unit) -> VectorPath {
		VectorPath(elements: [
			.wall(start: start, end: end, spacing: spacing, face: face)
		], coordinateSpace: .world, drawing: .stroke(width: 0.02))
	}
}

public extension VectorPath {
	static func + (lhs: VectorPath, rhs: VectorPath) -> VectorPath {
		lhs.union(rhs)
	}

	static func * (lhs: VectorPath, rhs: VectorPath) -> VectorPath {
		lhs.intersect(rhs)
	}

	static func - (lhs: VectorPath, rhs: VectorPath) -> VectorPath {
		lhs.subtract(rhs)
	}
}

infix operator ^^: AdditionPrecedence

public func ^^ (lhs: VectorPath, rhs: VectorPath) -> VectorPath {
	lhs.symmetricDifference(rhs)
}

public typealias BezierPath = VectorPath

private extension VectorPath {
	static func boolean(_ lhs: VectorPath, _ rhs: VectorPath, operation: BooleanOperation, resolution: Int, curveSteps: Int) -> VectorPath {
		guard let lhsBounds = lhs.bounds(curveSteps: curveSteps),
			  let rhsBounds = rhs.bounds(curveSteps: curveSteps) else {
			return VectorPath(elements: [])
		}

		var minPoint = SIMD3<Float>(
			min(lhsBounds.min.x, rhsBounds.min.x),
			min(lhsBounds.min.y, rhsBounds.min.y),
			min(lhsBounds.min.z, rhsBounds.min.z)
		)
		var maxPoint = SIMD3<Float>(
			max(lhsBounds.max.x, rhsBounds.max.x),
			max(lhsBounds.max.y, rhsBounds.max.y),
			max(lhsBounds.max.z, rhsBounds.max.z)
		)

		let padding = max(maxPoint.x - minPoint.x, maxPoint.y - minPoint.y) * 0.02 + 0.001
		minPoint.x -= padding
		minPoint.y -= padding
		maxPoint.x += padding
		maxPoint.y += padding

		let width = max(maxPoint.x - minPoint.x, 0.001)
		let height = max(maxPoint.y - minPoint.y, 0.001)
		let columns = max(resolution, 4)
		let rows = max(Int(ceil(Float(columns) * height / width)), 4)
		let cellWidth = width / Float(columns)
		let cellHeight = height / Float(rows)

		var mask = Array(repeating: false, count: columns * rows)
		for row in 0..<rows {
			for column in 0..<columns {
				let point = SIMD3<Float>(
					minPoint.x + (Float(column) + 0.5) * cellWidth,
					minPoint.y + (Float(row) + 0.5) * cellHeight,
					0
				)
				let insideLHS = lhs.contains(point, tolerance: min(cellWidth, cellHeight) * 0.5, curveSteps: curveSteps)
				let insideRHS = rhs.contains(point, tolerance: min(cellWidth, cellHeight) * 0.5, curveSteps: curveSteps)
				mask[row * columns + column] = switch operation {
				case .union:
					insideLHS || insideRHS
				case .intersection:
					insideLHS && insideRHS
				case .difference:
					insideLHS && !insideRHS
				case .symmetricDifference:
					insideLHS != insideRHS
				}
			}
		}

		let contours = rectangles(from: mask, columns: columns, rows: rows, minPoint: minPoint, cellWidth: cellWidth, cellHeight: cellHeight)
		let coordinateSpace: CoordinateSpace = lhs.coordinateSpace == .world || rhs.coordinateSpace == .world ? .world : .local
		return VectorPath.contours(contours, coordinateSpace: coordinateSpace, drawing: .fill, windingMode: .nonZero)
	}

	static func rectangles(from mask: [Bool], columns: Int, rows: Int, minPoint: SIMD3<Float>, cellWidth: Float, cellHeight: Float) -> [RasterizedVectorContour] {
		struct RunKey: Hashable {
			var start: Int
			var end: Int
		}
		struct ActiveRect {
			var startRow: Int
			var endRow: Int
		}

		var contours: [RasterizedVectorContour] = []
		var active: [RunKey: ActiveRect] = [:]

		func appendRect(key: RunKey, rect: ActiveRect) {
			let minX = minPoint.x + Float(key.start) * cellWidth
			let maxX = minPoint.x + Float(key.end + 1) * cellWidth
			let minY = minPoint.y + Float(rect.startRow) * cellHeight
			let maxY = minPoint.y + Float(rect.endRow + 1) * cellHeight
			contours.append(RasterizedVectorContour(points: [
				SIMD3<Float>(minX, minY, 0),
				SIMD3<Float>(maxX, minY, 0),
				SIMD3<Float>(maxX, maxY, 0),
				SIMD3<Float>(minX, maxY, 0)
			], isClosed: true))
		}

		for row in 0..<rows {
			var rowKeys: Set<RunKey> = []
			var column = 0
			while column < columns {
				if !mask[row * columns + column] {
					column += 1
					continue
				}

				let start = column
				while column + 1 < columns && mask[row * columns + column + 1] {
					column += 1
				}
				let key = RunKey(start: start, end: column)
				rowKeys.insert(key)
				if var rect = active[key] {
					rect.endRow = row
					active[key] = rect
				} else {
					active[key] = ActiveRect(startRow: row, endRow: row)
				}
				column += 1
			}

			let finishedRects = active.filter { !rowKeys.contains($0.key) }
			for (key, rect) in finishedRects {
				appendRect(key: key, rect: rect)
				active.removeValue(forKey: key)
			}
		}

		for (key, rect) in active {
			appendRect(key: key, rect: rect)
		}

		return contours
	}

	static func pointInPolygon(_ point: SIMD3<Float>, _ polygon: [SIMD3<Float>]) -> Bool {
		guard polygon.count >= 3 else { return false }
		var isInside = false
		var previous = polygon[polygon.count - 1]
		for current in polygon {
			let crossesY = (current.y > point.y) != (previous.y > point.y)
			if crossesY {
				let x = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y + 0.000001) + current.x
				if point.x < x {
					isInside.toggle()
				}
			}
			previous = current
		}
		return isInside
	}

	static func windingNumber(of point: SIMD3<Float>, in polygon: [SIMD3<Float>]) -> Int {
		guard polygon.count >= 3 else { return 0 }
		var winding = 0
		var previous = polygon[polygon.count - 1]
		for current in polygon {
			if previous.y <= point.y {
				if current.y > point.y && isLeft(previous, current, point) > 0 {
					winding += 1
				}
			} else if current.y <= point.y && isLeft(previous, current, point) < 0 {
				winding -= 1
			}
			previous = current
		}
		return winding
	}

	static func isLeft(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ point: SIMD3<Float>) -> Float {
		(end.x - start.x) * (point.y - start.y) - (point.x - start.x) * (end.y - start.y)
	}

	static func point(_ point: SIMD3<Float>, isWithin threshold: Float, of contour: RasterizedVectorContour) -> Bool {
		for index in 0..<(contour.points.count - 1) {
			if distanceFromPointToSegment(point, contour.points[index], contour.points[index + 1]) <= threshold {
				return true
			}
		}
		if contour.isClosed,
		   let first = contour.points.first,
		   let last = contour.points.last,
		   distanceFromPointToSegment(point, last, first) <= threshold {
			return true
		}
		return false
	}

	static func quadraticPoint(start: SIMD3<Float>, control: SIMD3<Float>, end: SIMD3<Float>, t: Float) -> SIMD3<Float> {
		let oneMinusT = 1 - t
		return start * (oneMinusT * oneMinusT) + control * (2 * oneMinusT * t) + end * (t * t)
	}

	static func cubicPoint(start: SIMD3<Float>, control1: SIMD3<Float>, control2: SIMD3<Float>, end: SIMD3<Float>, t: Float) -> SIMD3<Float> {
		let oneMinusT = 1 - t
		return start * (oneMinusT * oneMinusT * oneMinusT)
			+ control1 * (3 * oneMinusT * oneMinusT * t)
			+ control2 * (3 * oneMinusT * t * t)
			+ end * (t * t * t)
	}

	static func ellipsePoints(center: SIMD3<Float>, major: Float, minor: Float, rotation: Float, startAngle: Float, endAngle: Float, curveSteps: Int) -> [SIMD3<Float>] {
		let delta = endAngle - startAngle
		guard abs(delta) > 0.000001, major > 0, minor > 0 else { return [] }

		let fullCircle = abs(abs(delta) - 2 * Float.pi) < 0.0001
		let segmentCount = max(4, Int(ceil(abs(delta) / (2 * Float.pi) * Float(curveSteps))))
		let sampleCount = fullCircle ? segmentCount : segmentCount + 1
		let cosR = cos(rotation)
		let sinR = sin(rotation)

		return (0..<sampleCount).map { index in
			let denominator = Float(fullCircle ? segmentCount : max(segmentCount, 1))
			let angle = startAngle + delta * (Float(index) / denominator)
			let x = cos(angle) * major
			let y = sin(angle) * minor
			return SIMD3<Float>(
				center.x + x * cosR - y * sinR,
				center.y + x * sinR + y * cosR,
				center.z
			)
		}
	}

	static func arrowContours(start: SIMD3<Float>, end: SIMD3<Float>, shaftWidth: Float, headLength: Float, headWidth: Float, tipShape: ArrowShape?, tailShape: ArrowShape?, curveSteps: Int) -> [RasterizedVectorContour] {
		let delta = end - start
		let length = delta.length
		guard length > 0.0001 else { return [] }

		let direction = delta / length
		let normal = SIMD3<Float>(-direction.y, direction.x, 0)
		let actualHeadLength = min(headLength, length * 0.45)
		let tipBase = tipShape == nil ? end : end - direction * actualHeadLength
		let tailBase = tailShape == nil ? start : start + direction * actualHeadLength

		var contours: [RasterizedVectorContour] = []
		if (tipBase - tailBase).length > 0.0001, shaftWidth > 0 {
			let halfShaft = shaftWidth * 0.5
			contours.append(RasterizedVectorContour(points: [
				tailBase + normal * halfShaft,
				tipBase + normal * halfShaft,
				tipBase - normal * halfShaft,
				tailBase - normal * halfShaft
			], isClosed: true))
		}

		if let tipShape {
			contours.append(contentsOf: tipContours(tip: end, base: tipBase, direction: direction, normal: normal, headLength: actualHeadLength, headWidth: headWidth, shape: tipShape, curveSteps: curveSteps))
		}
		if let tailShape {
			contours.append(contentsOf: tipContours(tip: start, base: tailBase, direction: -direction, normal: -normal, headLength: actualHeadLength, headWidth: headWidth, shape: tailShape, curveSteps: curveSteps))
		}
		return contours
	}

	static func tipContours(tip: SIMD3<Float>, base: SIMD3<Float>, direction: SIMD3<Float>, normal: SIMD3<Float>, headLength: Float, headWidth: Float, shape: ArrowShape, curveSteps: Int) -> [RasterizedVectorContour] {
		let halfHead = headWidth * 0.5
		switch shape {
		case .triangle:
			return [RasterizedVectorContour(points: [
				tip,
				base + normal * halfHead,
				base - normal * halfHead
			], isClosed: true)]

		case .kite:
			let mid = base + direction * headWidth * 0.5
			return [RasterizedVectorContour(points: [
				tip,
				base + normal * halfHead,
				mid,
				base - normal * halfHead
			], isClosed: true)]

		case .circle:
			return [RasterizedVectorContour(points: ellipsePoints(
				center: base,
				major: halfHead,
				minor: halfHead,
				rotation: 0,
				startAngle: 0,
				endAngle: 2 * .pi,
				curveSteps: curveSteps
			), isClosed: true)]

		case .curvedTriangle:
			let steps = max(4, curveSteps / 4)
			var left: [SIMD3<Float>] = []
			var right: [SIMD3<Float>] = []
			for index in 0...steps {
				let t = Float(index) / Float(steps)
				let center = base + direction * (headLength * t)
				let width = halfHead * (1 - t) * (1 - t)
				left.append(center + normal * width)
				right.append(center - normal * width)
			}
			let points = left + [tip] + right.reversed()
			return [RasterizedVectorContour(points: points, isClosed: true)]
		}
	}

	static func wallContours(start: SIMD3<Float>, end: SIMD3<Float>, spacing: Float, face: SIMD3<Float>) -> [RasterizedVectorContour] {
		let delta = end - start
		let length = delta.length
		guard length > 0.0001 else { return [] }

		let direction = delta / length
		let safeSpacing = max(spacing, 0.02)
		let hatchLength: Float = 0.1
		let cos45: Float = 0.70710678
		let sin45: Float = 0.70710678
		let hatch = SIMD3<Float>(
			(face.x * cos45 - face.y * sin45) * hatchLength,
			(face.x * sin45 + face.y * cos45) * hatchLength,
			0
		)

		var contours = [RasterizedVectorContour(points: [start, end], isClosed: false)]
		let hatchCount = Int(floor(length / safeSpacing))
		for index in 0...hatchCount {
			let distance = Float(index) * safeSpacing
			let point = start + direction * distance
			contours.append(RasterizedVectorContour(points: [point, point + hatch], isClosed: false))
		}
		return contours
	}

	static func resample(_ points: [SIMD3<Float>], count: Int, closed: Bool) -> [SIMD3<Float>] {
		guard count > 0 else { return [] }
		guard points.count > 1 else {
			return Array(repeating: points.first ?? .zero, count: count)
		}

		let source = closed ? points + [points[0]] : points
		var distances = Array(repeating: Float(0), count: source.count)
		for index in 1..<source.count {
			distances[index] = distances[index - 1] + source[index].distance(to: source[index - 1])
		}
		let totalLength = distances.last ?? 0
		guard totalLength > 0.000001 else {
			return Array(repeating: source[0], count: count)
		}

		let denominator = closed ? Float(count) : Float(max(count - 1, 1))
		return (0..<count).map { sampleIndex in
			let targetDistance = totalLength * Float(sampleIndex) / denominator
			var segmentIndex = 1
			while segmentIndex < distances.count - 1 && distances[segmentIndex] < targetDistance {
				segmentIndex += 1
			}
			let segmentStart = distances[segmentIndex - 1]
			let segmentEnd = distances[segmentIndex]
			let localT = segmentEnd > segmentStart ? (targetDistance - segmentStart) / (segmentEnd - segmentStart) : 0
			return source[segmentIndex - 1] + (source[segmentIndex] - source[segmentIndex - 1]) * localT
		}
	}
}
