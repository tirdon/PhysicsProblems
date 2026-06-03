import Foundation

// MARK: - Component Protocol

protocol Component {}

// MARK: - ComponentSet

struct ComponentSet {
    private var storage: [ObjectIdentifier: Component] = [:]

    subscript<T: Component>(componentType: T.Type) -> T? {
        get { storage[ObjectIdentifier(componentType)] as? T }
        set {
            if let newValue {
                storage[ObjectIdentifier(componentType)] = newValue
            } else {
                storage.removeValue(forKey: ObjectIdentifier(componentType))
            }
        }
    }

    func has(_ componentType: (some Component).Type) -> Bool {
        storage[ObjectIdentifier(componentType)] != nil
    }

    mutating func set(_ component: some Component) {
        storage[ObjectIdentifier(type(of: component))] = component
    }

    mutating func remove<T: Component>(_ componentType: T.Type) {
        storage.removeValue(forKey: ObjectIdentifier(componentType))
    }
}

// MARK: - Entity (Base Class)

class Entity: Hashable {
    let id: Int
    var components = ComponentSet()

    init(id: Int) {
        self.id = id
    }

    // MARK: Component Accessors

    var transform: TransformComponent? {
        get { components[TransformComponent.self] }
        set { components[TransformComponent.self] = newValue }
    }

    var path: PathComponent? {
        get { components[PathComponent.self] }
        set { components[PathComponent.self] = newValue }
    }

    var style: RenderStyleComponent? {
        get { components[RenderStyleComponent.self] }
        set { components[RenderStyleComponent.self] = newValue }
    }

    var interaction: InteractionComponent? {
        get { components[InteractionComponent.self] }
        set { components[InteractionComponent.self] = newValue }
    }

    var pendulumAnimation: PendulumAnimationComponent? {
        get { components[PendulumAnimationComponent.self] }
        set { components[PendulumAnimationComponent.self] = newValue }
    }

    var revealOnHover: RevealOnHoverComponent? {
        get { components[RevealOnHoverComponent.self] }
        set { components[RevealOnHoverComponent.self] = newValue }
    }

    static func == (lhs: Entity, rhs: Entity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Entity Subclasses

class Circle: Entity {}
class Line: Entity {}
class Arrow: Entity {}

// MARK: - EntityQuery

struct EntityQuery {
    let predicate: (Entity) -> Bool

    static func has<T: Component>(_ type: T.Type) -> EntityQuery {
        EntityQuery { $0.components.has(type) }
    }

    static func has<A: Component, B: Component>(_ a: A.Type, _ b: B.Type) -> EntityQuery {
        EntityQuery { $0.components.has(a) && $0.components.has(b) }
    }
}

// MARK: - System Protocol

protocol System {
    func update(context: SceneUpdateContext)
}

struct SceneUpdateContext {
    let scene: SceneWorld
    let deltaTime: Double
}

// MARK: - Components

struct TransformComponent: Component {
    var position: Vec2
    var rotation: Double = 0
}

enum Anchor {
    case point(Vec2)
    case entity(Entity, offset: Vec2 = .zero)

    func resolve() -> Vec2 {
        switch self {
        case .point(let point):
            return point
        case .entity(let entity, let offset):
            return (entity.transform?.position ?? .zero) + offset
        }
    }
}

struct PathComponent: Component {
    enum Path {
        case circle(radius: Double)
        case line(start: Anchor, end: Anchor, width: Double)
        case arrow(start: Anchor, end: Anchor, shaftWidth: Double, headLength: Double, headWidth: Double)
    }
    var path: Path
}

struct RenderStyleComponent: Component {
    var color: Color
    var opacity: Double = 1
    var hoverColor: Color?
}

struct InteractionComponent: Component {
    var hoverable: Bool
    var draggable: Bool
    var pauseAnimationOnHover: Bool
    var hitPadding: Double
}

struct PendulumAnimationComponent: Component {
    var pivot: Vec2
    var length: Double
    var baseAngle: Double
    var amplitude: Double
    var period: Double
    var elapsed: Double = 0
}

struct RevealOnHoverComponent: Component {
    var trigger: Entity
}

// MARK: - Render Primitives

enum RenderPrimitive {
    case circle(center: Vec2, radius: Double, color: Color)
    case line(start: Vec2, end: Vec2, width: Double, color: Color)
    case arrow(start: Vec2, end: Vec2, shaftWidth: Double, headLength: Double, headWidth: Double, color: Color)
}

struct SceneSnapshot {
    var primitives: [RenderPrimitive]
}

// MARK: - SceneWorld

struct SceneWorld {
    private var nextID = 0
    private(set) var entities: [Entity] = []
    private var systems: [System] = []

    private(set) var hoveredEntity: Entity?
    private(set) var draggedEntity: Entity?
    private var dragOffset = Vec2.zero

    // MARK: Entity Creation

    @discardableResult
    mutating func addEntity() -> Entity {
        let entity = Entity(id: nextID)
        nextID += 1
        entities.append(entity)
        return entity
    }

    @discardableResult
    mutating func addCircle() -> Circle {
        let entity = Circle(id: nextID)
        nextID += 1
        entities.append(entity)
        return entity
    }

    @discardableResult
    mutating func addLine() -> Line {
        let entity = Line(id: nextID)
        nextID += 1
        entities.append(entity)
        return entity
    }

    @discardableResult
    mutating func addArrow() -> Arrow {
        let entity = Arrow(id: nextID)
        nextID += 1
        entities.append(entity)
        return entity
    }

    // MARK: System Registration

    mutating func registerSystem(_ system: System) {
        systems.append(system)
    }

    // MARK: Query

    func performQuery(_ query: EntityQuery) -> [Entity] {
        entities.filter(query.predicate)
    }

    // MARK: Update

    mutating func update(deltaTime: Double) {
        let context = SceneUpdateContext(scene: self, deltaTime: deltaTime)
        for system in systems {
            system.update(context: context)
        }
    }

    // MARK: Input Handling

    mutating func pointerMoved(to point: Vec2) {
        if let draggedEntity {
            if var transform = draggedEntity.transform {
                transform.position = point + dragOffset
                draggedEntity.transform = transform
            }
            hoveredEntity = draggedEntity
            return
        }
        hoveredEntity = hitTest(point)
    }

    mutating func pointerDown(at point: Vec2) {
        guard let entity = hitTest(point),
              entity.interaction?.draggable == true,
              let position = entity.transform?.position
        else {
            hoveredEntity = nil
            draggedEntity = nil
            return
        }
        hoveredEntity = entity
        draggedEntity = entity
        dragOffset = position - point
    }

    mutating func pointerUp(at point: Vec2) {
        if let draggedEntity {
            updatePendulumAnimationAfterDrag(entity: draggedEntity)
        }
        draggedEntity = nil
        dragOffset = .zero
        hoveredEntity = hitTest(point)
    }

    // MARK: Snapshot

    func snapshot() -> SceneSnapshot {
        var primitives: [RenderPrimitive] = []
        primitives.reserveCapacity(entities.count)

        for entity in entities {
            let style = effectiveStyle(for: entity)
            guard style.opacity > 0.001 else { continue }
            let color = style.color.withOpacity(style.opacity)

            if let pathComponent = entity.path {
                switch pathComponent.path {
                case .circle(let radius):
                    if let transform = entity.transform {
                        primitives.append(.circle(center: transform.position, radius: radius, color: color))
                    }
                case .line(let start, let end, let width):
                    primitives.append(.line(
                        start: start.resolve(),
                        end: end.resolve(),
                        width: width,
                        color: color
                    ))
                case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth):
                    primitives.append(.arrow(
                        start: start.resolve(),
                        end: end.resolve(),
                        shaftWidth: shaftWidth,
                        headLength: headLength,
                        headWidth: headWidth,
                        color: color
                    ))
                }
            }
        }

        return SceneSnapshot(primitives: primitives)
    }

    // MARK: Hit Testing

    func hitTest(_ point: Vec2) -> Entity? {
        for entity in entities.reversed() {
            guard let interaction = entity.interaction,
                  interaction.hoverable || interaction.draggable else {
                continue
            }
            if let pathComponent = entity.path {
                switch pathComponent.path {
                case .circle(let radius):
                    if let transform = entity.transform {
                        let hitRadius = radius + interaction.hitPadding
                        if point.distance(to: transform.position) <= hitRadius {
                            return entity
                        }
                    }
                case .line(let start, let end, let width):
                    let distance = distanceFromPointToSegment(point, start.resolve(), end.resolve())
                    if distance <= width * 0.5 + interaction.hitPadding {
                        return entity
                    }
                case .arrow(let start, let end, _, _, let headWidth):
                    let distance = distanceFromPointToSegment(point, start.resolve(), end.resolve())
                    if distance <= headWidth * 0.5 + interaction.hitPadding {
                        return entity
                    }
                }
            }
        }
        return nil
    }

    // MARK: Private

    private func effectiveStyle(for entity: Entity) -> RenderStyleComponent {
        var style = entity.style ?? RenderStyleComponent(color: .pivot)
        if let trigger = entity.revealOnHover?.trigger {
            let visible = hoveredEntity == trigger || draggedEntity == trigger
            style.opacity = visible ? 1 : 0
        }
        if (hoveredEntity == entity || draggedEntity == entity), let hoverColor = style.hoverColor {
            style.color = hoverColor
        }
        return style
    }

    private func updatePendulumAnimationAfterDrag(entity: Entity) {
        guard var animation = entity.pendulumAnimation,
              let position = entity.transform?.position
        else { return }

        let relative = position - animation.pivot
        let length = max(relative.length, 0.2)
        animation.length = length
        animation.baseAngle = atan2(relative.x, -relative.y)
        animation.elapsed = 0
        entity.pendulumAnimation = animation
    }
}
