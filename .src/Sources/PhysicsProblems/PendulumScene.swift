import Foundation

// MARK: - PendulumAnimationSystem

struct PendulumAnimationSystem: System {
    func update(context: SceneUpdateContext) {
        let boundedDelta = clamp(context.deltaTime, min: 0, max: 0.05)
        let scene = context.scene

        for entity in scene.performQuery(.has(PendulumAnimationComponent.self)) {
            guard var animation = entity.pendulumAnimation else { continue }

            if scene.draggedEntity == entity {
                continue
            }
            if scene.hoveredEntity == entity,
               entity.interaction?.pauseAnimationOnHover == true {
                continue
            }

            animation.elapsed += boundedDelta
            let phase = sin((animation.elapsed / animation.period) * Double.pi * 2)
            let angle = animation.baseAngle + animation.amplitude * phase

            if var transform = entity.transform {
                transform.position = animation.pivot + Vec2(x: sin(angle), y: -cos(angle)) * animation.length
                entity.transform = transform
            }

            entity.pendulumAnimation = animation
        }
    }
}

// MARK: - PendulumScene

struct PendulumSceneEntities {
    var pivot: Circle
    var string: Line
    var bob: Circle
    var gravity: Arrow
    var tension: Arrow
}

enum PendulumScene {
    static func makeWorld() -> (SceneWorld, PendulumSceneEntities) {
        var world = SceneWorld()

        // Register systems
        world.registerSystem(PendulumAnimationSystem())

        // Create entities
        let pivot = world.addCircle()
        pivot.transform = TransformComponent(position: .zero)
        pivot.path = PathComponent(path: .circle(radius: 0.035))
        pivot.style = RenderStyleComponent(color: .pivot)

        let string = world.addLine()
        // LineComponent set after bob is created (needs bob reference)

        let bob = world.addCircle()
        let bobPosition = Vec2(x: -0.72, y: -0.86)
        bob.transform = TransformComponent(position: bobPosition)
        bob.path = PathComponent(path: .circle(radius: 0.12))
        bob.style = RenderStyleComponent(color: .bob, hoverColor: .bobHighlight)
        bob.interaction = InteractionComponent(
            hoverable: true,
            draggable: true,
            pauseAnimationOnHover: true,
            hitPadding: 0.05
        )
        bob.pendulumAnimation = PendulumAnimationComponent(
            pivot: .zero,
            length: bobPosition.length,
            baseAngle: atan2(bobPosition.x, -bobPosition.y),
            amplitude: 0.28,
            period: 2.4
        )

        string.path = PathComponent(path: .line(
            start: .point(.zero),
            end: .entity(bob),
            width: 0.018
        ))
        string.style = RenderStyleComponent(color: .string)

        let gravity = world.addArrow()
        gravity.path = PathComponent(path: .arrow(
            start: .entity(bob),
            end: .entity(bob, offset: Vec2(x: 0, y: -0.55)),
            shaftWidth: 0.025,
            headLength: 0.12,
            headWidth: 0.11
        ))
        gravity.style = RenderStyleComponent(color: .gravity, opacity: 0)
        gravity.revealOnHover = RevealOnHoverComponent(trigger: bob)

        let tension = world.addArrow()
        tension.path = PathComponent(path: .arrow(
            start: .entity(bob),
            end: .point(.zero),
            shaftWidth: 0.025,
            headLength: 0.12,
            headWidth: 0.11
        ))
        tension.style = RenderStyleComponent(color: .tension, opacity: 0)
        tension.revealOnHover = RevealOnHoverComponent(trigger: bob)

        return (world, PendulumSceneEntities(
            pivot: pivot,
            string: string,
            bob: bob,
            gravity: gravity,
            tension: tension
        ))
    }
}
