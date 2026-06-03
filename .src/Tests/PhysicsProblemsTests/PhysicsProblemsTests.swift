import Testing
import Foundation
@testable import PhysicsEngine

@MainActor
@Test func sceneCanAddEntitiesAndSnapshot() async throws {
    let scene = SceneWorld()

    let pivot = Circle()
    pivot.transform = TransformComponent(position: .zero)
    pivot.vector = VectorComponent(vector: .circle(radius: 0.035))
    pivot.style = RenderStyleComponent(color: .pivot)
    scene.add(pivot)

    let bob = Circle()
    let bobPosition = SIMD3<Float>(-0.72, -0.86, 0)
    bob.transform = TransformComponent(position: bobPosition)
    bob.vector = VectorComponent(vector: .circle(radius: 0.12))
    bob.style = RenderStyleComponent(color: .bob, hoverColor: .bobHighlight)
    bob.interaction = InteractionComponent(
        hoverable: true,
        draggable: true,
        pauseAnimationOnHover: true,
        hitPadding: 0.05
    )
    scene.add(bob)

    let string = Line()
    string.vector = VectorComponent(vector: .line(
        start: .point(.zero),
        end: .entity(bob),
        width: 0.018
    ))
    string.style = RenderStyleComponent(color: .string)
    scene.add(string)

    let gravity = Arrow()
    gravity.vector = VectorComponent(vector: .arrow(
        start: .entity(bob),
        end: .entity(bob, offset: SIMD3<Float>(0, -0.55, 0)),
        shaftWidth: 0.025,
        headLength: 0.12,
        headWidth: 0.11
    ))
    gravity.style = RenderStyleComponent(color: .gravity, opacity: 0)
    gravity.revealOnHover = RevealOnHoverComponent(trigger: bob)
    scene.add(gravity)

    // Test snapshot contains entities
    let snapshot = scene.snapshot()
    // pivot + bob visible, string visible = 3 primitives (gravity hidden due to opacity 0)
    #expect(snapshot.primitives.count == 3)

    // Test transform is set
    #expect(bob.transform?.position == bobPosition)
    #expect(pivot.transform?.position == .zero)
}



@MainActor
@Test func draggingBobUpdatesPosition() async throws {
    let scene = SceneWorld()

    let bob = Circle()
    let start = SIMD3<Float>(-0.72, -0.86, 0)
    bob.transform = TransformComponent(position: start)
    bob.vector = VectorComponent(vector: .circle(radius: 0.12))
    bob.interaction = InteractionComponent(
        hoverable: true,
        draggable: true,
        pauseAnimationOnHover: true,
        hitPadding: 0.05
    )
    scene.add(bob)

    let target = SIMD3<Float>(0.4, -0.95, 0)

    scene.pointerDown(at: start)
    scene.pointerMoved(to: target)
    scene.pointerUp(at: target)

    #expect(bob.transform?.position == target)
}

@MainActor
@Test func forceArrowsAreHiddenUntilBobHover() async throws {
    let scene = SceneWorld()

    let bob = Circle()
    let bobPos = SIMD3<Float>(-0.72, -0.86, 0)
    bob.transform = TransformComponent(position: bobPos)
    bob.vector = VectorComponent(vector: .circle(radius: 0.12))
    bob.style = RenderStyleComponent(color: .bob, hoverColor: .bobHighlight)
    bob.interaction = InteractionComponent(hoverable: true, draggable: true, pauseAnimationOnHover: true, hitPadding: 0.05)
    scene.add(bob)

    let gravity = Arrow()
    gravity.vector = VectorComponent(vector: .arrow(start: .entity(bob), end: .entity(bob, offset: SIMD3(0, -0.55, 0)), shaftWidth: 0.025, headLength: 0.12, headWidth: 0.11))
    gravity.style = RenderStyleComponent(color: .gravity, opacity: 0)
    gravity.revealOnHover = RevealOnHoverComponent(trigger: bob)
    scene.add(gravity)

    let tension = Arrow()
    tension.vector = VectorComponent(vector: .arrow(start: .entity(bob), end: .point(.zero), shaftWidth: 0.025, headLength: 0.12, headWidth: 0.11))
    tension.style = RenderStyleComponent(color: .tension, opacity: 0)
    tension.revealOnHover = RevealOnHoverComponent(trigger: bob)
    scene.add(tension)

    let hiddenSnapshot = scene.snapshot()
    #expect(hiddenSnapshot.primitives.count == 1) // only bob

    scene.pointerMoved(to: bobPos)

    let visibleSnapshot = scene.snapshot()
    let arrowCount = visibleSnapshot.primitives.filter {
        if case .arrow = $0 { return true }
        return false
    }.count
    #expect(arrowCount == 2)
}

@MainActor
@Test func entityColorConvenience() async throws {
    let circle = Circle()
    circle.color(.red)
    #expect(circle.style?.color == .red)
}

@MainActor
@Test func entityShiftAndMoveAnimations() async throws {
    let circle = Circle()
    circle.transform = TransformComponent(position: .zero)

    let shift = circle.shift(1.i + 2.j)
    let shiftTrack = shift.tracks[0] as! MoveTrack
    #expect(shiftTrack.isRelative == true)
    #expect(shiftTrack.target == SIMD3<Float>(1, 2, 0))

    let move = circle.move(to: .origin)
    let moveTrack = move.tracks[0] as! MoveTrack
    #expect(moveTrack.isRelative == false)
    #expect(moveTrack.target == .zero)
}
