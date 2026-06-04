//
//  HasHierarchy.swift
//  PhysicsProblems
//
//  Created by Antigravity on 3/6/2569 BE.
//

import Foundation

public enum Alignment {
	case center
	case leading
	case trailing
	case top
	case bottom
}

public protocol HasHierarchy: Entity {
	// MARK: Hierarchy
	var parent: HasHierarchy? { get set }
	var children: [Entity] { get set }
	
	func addChild(_ entity: Entity)
	func removeChild(_ entity: Entity)
	func removeParent()
	
	func align(_ alignment: Alignment, spacing: Float)
}

public extension HasHierarchy {
	func addChild(_ entity: Entity) {
		if let h = entity as? HasHierarchy {
			guard h.parent == nil else { return }
			h.parent = self
		}
		children.append(entity)
	}

	func removeChild(_ entity: Entity) {
		if let index = children.firstIndex(of: entity) {
			if let h = entity as? HasHierarchy {
				h.parent = nil
			}
			children.remove(at: index)
		}
	}
	
	func removeParent() {
		parent = nil
	}

	static func size(of entity: Entity) -> SIMD2<Float> {
		var childSize: SIMD2<Float> = .zero
		if let body = entity.components[PhysicsBodyComponent.self] {
			switch body.shape {
			case .circle(let r): childSize = SIMD2<Float>(r * 2, r * 2)
			case .ellipse(let major, let minor): childSize = SIMD2<Float>(major * 2, minor * 2)
			case .rect(let w, let h): childSize = SIMD2<Float>(w, h)
			}
		} else if let vector = entity.components[VectorComponent.self] {
			switch vector.vector {
			case .circle(let r): childSize = SIMD2<Float>(r * 2, r * 2)
			case .ellipse(let major, let minor): childSize = SIMD2<Float>(major * 2, minor * 2)
			case .rect(let w, let h): childSize = SIMD2<Float>(w, h)
			default: break
			}
		}
		let scale = entity.transform?.scale ?? .one
		return SIMD2<Float>(childSize.x * scale.x, childSize.y * scale.y)
	}

	func align(_ alignment: Alignment, spacing: Float = 0) {
		guard !children.isEmpty else { return }
		
		var currentOffset: Float = 0
		
		let direction: SIMD3<Float>
		switch alignment {
		case .leading: direction = SIMD3<Float>(-1, 0, 0)
		case .trailing: direction = SIMD3<Float>(1, 0, 0)
		case .top: direction = SIMD3<Float>(0, 1, 0)
		case .bottom: direction = SIMD3<Float>(0, -1, 0)
		case .center: direction = .zero
		}
		
		for child in children {
			let fullSize = Self.size(of: child)
			let childSize = abs(direction.x) > 0 ? fullSize.x : fullSize.y
			
			if alignment == .center {
				child.position = self.position
			} else {
				child.position = self.position + direction * (currentOffset + childSize / 2)
				currentOffset += childSize + spacing
			}
		}
	}
	
	func propagateTransform(oldTransform: TransformComponent?, newTransform: TransformComponent?) {
		let oldPosition = oldTransform?.position ?? .zero
		let oldScale = oldTransform?.scale ?? .one
		let newPosition = newTransform?.position ?? .zero
		let newScale = newTransform?.scale ?? .one
		
		let deltaPos = newPosition - oldPosition
		let scaleRatio = newScale / oldScale
		
		if deltaPos != .zero || scaleRatio != .one {
			for child in children {
				if var childTransform = child.transform {
					if scaleRatio != .one {
						let localPos = childTransform.position - oldPosition
						childTransform.position = oldPosition + localPos * scaleRatio
						childTransform.scale *= scaleRatio
					}
					if deltaPos != .zero {
						childTransform.position += deltaPos
					}
					child.transform = childTransform
				}
			}
		}
	}

	@MainActor
	func animateAlign(_ alignment: Alignment, spacing: Float = 0, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		guard !children.isEmpty else { return clip }
		
		var currentOffset: Float = 0
		let direction: SIMD3<Float>
		switch alignment {
		case .leading: direction = SIMD3<Float>(-1, 0, 0)
		case .trailing: direction = SIMD3<Float>(1, 0, 0)
		case .top: direction = SIMD3<Float>(0, 1, 0)
		case .bottom: direction = SIMD3<Float>(0, -1, 0)
		case .center: direction = .zero
		}
		
		for child in children {
			let fullSize = Self.size(of: child)
			let childSize = abs(direction.x) > 0 ? fullSize.x : fullSize.y
			let targetPos = alignment == .center ? self.position : self.position + direction * (currentOffset + childSize / 2)
			
			clip.addTrack(MoveTrack(entity: child, target: targetPos, isRelative: false, duration: duration, easing: easing))
			
			if alignment != .center {
				currentOffset += childSize + spacing
			}
		}
		return clip
	}
	
	@MainActor
	func append(_ entity: Entity, alignment: Alignment, spacing: Float = 0, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		addChild(entity)
		return animateAlign(alignment, spacing: spacing, duration: duration, easing: easing)
	}
}

public class Row: Entity, HasHierarchy {
	public weak var parent: HasHierarchy?
	public var children: [Entity] = []

	public var spacing: Float

	public init(spacing: Float = 0, children: [Entity] = []) {
		self.spacing = spacing
		super.init()
		for child in children {
			addChild(child)
		}
		layout()
	}
	
	public override var transform: TransformComponent? {
		get { super.transform }
		set {
			let oldTransform = super.transform
			super.transform = newValue
			propagateTransform(oldTransform: oldTransform, newTransform: newValue)
		}
	}
	
	public func layout() {
		guard !children.isEmpty else { return }
		
		let sizes = children.map { Self.size(of: $0) }
		let totalWidth = sizes.map { $0.x }.reduce(0, +) + Float(children.count - 1) * spacing
		
		var currentX = self.position.x - totalWidth / 2
		for (i, child) in children.enumerated() {
			let s = sizes[i]
			child.position = SIMD3<Float>(currentX + s.x / 2, self.position.y, self.position.z)
			currentX += s.x + spacing
		}
	}

	@MainActor
	public func animateLayout(duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		guard !children.isEmpty else { return clip }
		
		let sizes = children.map { Self.size(of: $0) }
		let totalWidth = sizes.map { $0.x }.reduce(0, +) + Float(children.count - 1) * spacing
		
		var currentX = self.position.x - totalWidth / 2
		for (i, child) in children.enumerated() {
			let s = sizes[i]
			let targetPos = SIMD3<Float>(currentX + s.x / 2, self.position.y, self.position.z)
			clip.addTrack(MoveTrack(entity: child, target: targetPos, isRelative: false, duration: duration, easing: easing))
			currentX += s.x + spacing
		}
		return clip
	}
	
	@MainActor
	public func append(_ entity: Entity, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		addChild(entity)
		return animateLayout(duration: duration, easing: easing)
	}
}

public class Column: Entity, HasHierarchy {
	public weak var parent: HasHierarchy?
	public var children: [Entity] = []

	public var spacing: Float

	public init(spacing: Float = 0, children: [Entity] = []) {
		self.spacing = spacing
		super.init()
		for child in children {
			addChild(child)
		}
		layout()
	}
	
	public override var transform: TransformComponent? {
		get { super.transform }
		set {
			let oldTransform = super.transform
			super.transform = newValue
			propagateTransform(oldTransform: oldTransform, newTransform: newValue)
		}
	}
	
	public func layout() {
		guard !children.isEmpty else { return }
		
		let sizes = children.map { Self.size(of: $0) }
		let totalHeight = sizes.map { $0.y }.reduce(0, +) + Float(children.count - 1) * spacing
		
		var currentY = self.position.y + totalHeight / 2
		for (i, child) in children.enumerated() {
			let s = sizes[i]
			child.position = SIMD3<Float>(self.position.x, currentY - s.y / 2, self.position.z)
			currentY -= (s.y + spacing)
		}
	}

	@MainActor
	public func animateLayout(duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		guard !children.isEmpty else { return clip }
		
		let sizes = children.map { Self.size(of: $0) }
		let totalHeight = sizes.map { $0.y }.reduce(0, +) + Float(children.count - 1) * spacing
		
		var currentY = self.position.y + totalHeight / 2
		for (i, child) in children.enumerated() {
			let s = sizes[i]
			let targetPos = SIMD3<Float>(self.position.x, currentY - s.y / 2, self.position.z)
			clip.addTrack(MoveTrack(entity: child, target: targetPos, isRelative: false, duration: duration, easing: easing))
			currentY -= (s.y + spacing)
		}
		return clip
	}
	
	@MainActor
	public func append(_ entity: Entity, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		addChild(entity)
		return animateLayout(duration: duration, easing: easing)
	}
}

open class Grid: Entity, HasHierarchy {
	public weak var parent: HasHierarchy?
	public var children: [Entity] = []

	public var columns: Int
	public var spacing: SIMD2<Float>

	public init(columns: Int, spacing: SIMD2<Float> = .zero, children: [Entity] = []) {
		self.columns = columns
		self.spacing = spacing
		super.init()
		for child in children {
			addChild(child)
		}
		layout()
	}
	
	open override var transform: TransformComponent? {
		get { super.transform }
		set {
			let oldTransform = super.transform
			super.transform = newValue
			propagateTransform(oldTransform: oldTransform, newTransform: newValue)
		}
	}
	
	public func layout() {
		guard !children.isEmpty, columns > 0 else { return }
		
		let sizes = children.map { Self.size(of: $0) }
		let rows = Int(ceil(Double(children.count) / Double(columns)))
		
		var colWidths = [Float](repeating: 0, count: columns)
		var rowHeights = [Float](repeating: 0, count: rows)
		
		for (i, s) in sizes.enumerated() {
			let r = i / columns
			let c = i % columns
			colWidths[c] = max(colWidths[c], s.x)
			rowHeights[r] = max(rowHeights[r], s.y)
		}
		
		let totalWidth = colWidths.reduce(0, +) + Float(columns - 1) * spacing.x
		let totalHeight = rowHeights.reduce(0, +) + Float(rows - 1) * spacing.y
		
		var startY = self.position.y + totalHeight / 2
		for r in 0..<rows {
			var startX = self.position.x - totalWidth / 2
			for c in 0..<columns {
				let idx = r * columns + c
				if idx < children.count {
					let child = children[idx]
					child.position = SIMD3<Float>(startX + colWidths[c] / 2, startY - rowHeights[r] / 2, self.position.z)
				}
				startX += colWidths[c] + spacing.x
			}
			startY -= (rowHeights[r] + spacing.y)
		}
	}

	@MainActor
	public func animateLayout(duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		let clip = AnimationClip()
		guard !children.isEmpty, columns > 0 else { return clip }
		
		let sizes = children.map { Self.size(of: $0) }
		let rows = Int(ceil(Double(children.count) / Double(columns)))
		
		var colWidths = [Float](repeating: 0, count: columns)
		var rowHeights = [Float](repeating: 0, count: rows)
		
		for (i, s) in sizes.enumerated() {
			let r = i / columns
			let c = i % columns
			colWidths[c] = max(colWidths[c], s.x)
			rowHeights[r] = max(rowHeights[r], s.y)
		}
		
		let totalWidth = colWidths.reduce(0, +) + Float(columns - 1) * spacing.x
		let totalHeight = rowHeights.reduce(0, +) + Float(rows - 1) * spacing.y
		
		var startY = self.position.y + totalHeight / 2
		for r in 0..<rows {
			var startX = self.position.x - totalWidth / 2
			for c in 0..<columns {
				let idx = r * columns + c
				if idx < children.count {
					let child = children[idx]
					let targetPos = SIMD3<Float>(startX + colWidths[c] / 2, startY - rowHeights[r] / 2, self.position.z)
					clip.addTrack(MoveTrack(entity: child, target: targetPos, isRelative: false, duration: duration, easing: easing))
				}
				startX += colWidths[c] + spacing.x
			}
			startY -= (rowHeights[r] + spacing.y)
		}
		return clip
	}
	
	@MainActor
	public func append(_ entity: Entity, duration: Float = 1.0, easing: Easing = .smooth) -> AnimationClip {
		addChild(entity)
		return animateLayout(duration: duration, easing: easing)
	}
}
