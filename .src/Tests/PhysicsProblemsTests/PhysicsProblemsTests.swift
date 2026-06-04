import Testing
import Foundation
@testable import PhysicsEngine

@MainActor
@Test func sceneCanAddEntitiesAndSnapshot() async throws {
    let scene = SceneWorld()

    let pivot = Circle()
    pivot.transform = TransformComponent(position: .zero)
    pivot.vector = VectorComponent(vector: .circle(radius: 0.035))
    pivot.style = RenderStyleComponent(color: .gray)
    scene.add(pivot)

    let bob = Circle()
    let bobPosition = SIMD3<Float>(-0.72, -0.86, 0)
    bob.transform = TransformComponent(position: bobPosition)
    bob.vector = VectorComponent(vector: .circle(radius: 0.12))
    bob.style = RenderStyleComponent(color: .blue, hoverColor: .cyan)
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
    string.style = RenderStyleComponent(color: .red)
    scene.add(string)

    let gravity = Arrow()
    gravity.vector = VectorComponent(vector: .arrow(
        start: .entity(bob),
        end: .entity(bob, direction: .bottom, offset: 0.43),
        shaftWidth: 0.025,
        headLength: 0.12,
        headWidth: 0.11
    ))
    gravity.style = RenderStyleComponent(color: .green, opacity: 0)
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
    bob.style = RenderStyleComponent(color: .blue, hoverColor: .cyan)
    bob.interaction = InteractionComponent(hoverable: true, draggable: true, pauseAnimationOnHover: true, hitPadding: 0.05)
    scene.add(bob)

    let gravity = Arrow()
    gravity.vector = VectorComponent(vector: .arrow(start: .entity(bob), end: .entity(bob, direction: .bottom, offset: 0.43), shaftWidth: 0.025, headLength: 0.12, headWidth: 0.11))
    gravity.style = RenderStyleComponent(color: .green, opacity: 0)
    gravity.revealOnHover = RevealOnHoverComponent(trigger: bob)
    scene.add(gravity)

    let tension = Arrow()
    tension.vector = VectorComponent(vector: .arrow(start: .entity(bob), end: .point(.zero), shaftWidth: 0.025, headLength: 0.12, headWidth: 0.11))
    tension.style = RenderStyleComponent(color: .orange, opacity: 0)
    tension.revealOnHover = RevealOnHoverComponent(trigger: bob)
    scene.add(tension)

    let hiddenSnapshot = scene.snapshot()
    #expect(hiddenSnapshot.primitives.count == 1) // only bob

    scene.pointerMoved(to: bobPos)

    let visibleSnapshot = scene.snapshot()
    let pathCount = visibleSnapshot.primitives.filter {
        if case .path = $0 { return true }
        return false
    }.count
    #expect(pathCount == 3)
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

@Test func vectorComponentStoresRasterizablePath() async throws {
    let vector = VectorComponent(vector: .circle(radius: 0.5))
    let points = vector.path.rasterize(curveSteps: 24)

    #expect(points.count == 24)
    #expect(vector.path.contains(.zero))
    #expect(!vector.path.contains(SIMD3<Float>(1, 1, 0)))
}

@Test func bezierPathRasterizesCurves() async throws {
    let path = VectorPath.bezier(
        start: .point(.zero),
        segments: [
            .cubicCurve(
                to: .point(SIMD3<Float>(1, 0, 0)),
                control1: .point(SIMD3<Float>(0, 1, 0)),
                control2: .point(SIMD3<Float>(1, 1, 0))
            )
        ]
    )

    let points = path.rasterize(curveSteps: 8)
    #expect(points.count == 9)
    #expect(points.first == .zero)
    #expect(points.last == SIMD3<Float>(1, 0, 0))
}

@Test func pathsCanMorphThroughRasterizedSamples() async throws {
    let square = VectorPath.rect(width: 1, height: 1)
    let circle = VectorPath.circle(radius: 0.5)
    let morphed = square.interpolated(to: circle, progress: 0.5, samples: 32)

    #expect(morphed.rasterize().count == 32)
    #expect(morphed.contains(.zero))
}

@Test func pathBooleanOperatorsRasterizeResults() async throws {
    let left = VectorPath.contour(points: [
        SIMD3<Float>(-1, -1, 0),
        SIMD3<Float>(1, -1, 0),
        SIMD3<Float>(1, 1, 0),
        SIMD3<Float>(-1, 1, 0)
    ], isClosed: true)
    let right = VectorPath.contour(points: [
        SIMD3<Float>(0, -1, 0),
        SIMD3<Float>(2, -1, 0),
        SIMD3<Float>(2, 1, 0),
        SIMD3<Float>(0, 1, 0)
    ], isClosed: true)

    let union = left + right
    let intersection = left * right
    let difference = left - right
    let symmetricDifference = left ^^ right

    #expect(union.contains(SIMD3<Float>(-0.5, 0, 0)))
    #expect(union.contains(SIMD3<Float>(1.5, 0, 0)))
    #expect(intersection.contains(SIMD3<Float>(0.5, 0, 0)))
    #expect(!intersection.contains(SIMD3<Float>(-0.5, 0, 0)))
    #expect(difference.contains(SIMD3<Float>(-0.5, 0, 0)))
    #expect(!difference.contains(SIMD3<Float>(0.5, 0, 0)))
    #expect(symmetricDifference.contains(SIMD3<Float>(-0.5, 0, 0)))
    #expect(!symmetricDifference.contains(SIMD3<Float>(0.5, 0, 0)))
}
