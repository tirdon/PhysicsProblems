//
//  Entity+Mesh.swift
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 5/6/2569 BE.
//

// MARK: - Entity inheritances
public class MeshEntity: Entity {
	public var mesh: MeshComponent? {
		get { components[MeshComponent.self] }
		set { components[MeshComponent.self] = newValue }
	}

	public var style: RenderStyleComponent? {
		get { components[RenderStyleComponent.self] }
		set { components[RenderStyleComponent.self] = newValue }
	}
	
	@discardableResult
	public func color(_ color: Color) -> Self {
		var s = style ?? RenderStyleComponent(color: .clear)
		s.color = color
		style = s
		return self
	}
}
