import Testing
@testable import PhysicsProblems

@Test func pendulumSceneCreatesExpectedComponents() async throws {
    let (world, entities) = PendulumScene.makeWorld()

    #expect(world.transforms[entities.pivot]?.position == .zero)
    #expect(world.lines[entities.string] != nil)
    #expect(world.circles[entities.bob]?.radius == 0.12)
    #expect(world.arrows[entities.gravity] != nil)
    #expect(world.arrows[entities.tension] != nil)
    #expect(world.interactions[entities.bob]?.draggable == true)
    #expect(world.pendulumAnimations[entities.bob] != nil)
}

@Test func animationMovesBobUnlessPausedOnHover() async throws {
    var (world, entities) = PendulumScene.makeWorld()
    let initial = try #require(world.transforms[entities.bob]?.position)

    world.update(deltaTime: 0.6)
    let animated = try #require(world.transforms[entities.bob]?.position)
    #expect(animated != initial)

    world.pointerMoved(to: animated)
    world.update(deltaTime: 0.6)
    let paused = try #require(world.transforms[entities.bob]?.position)
    #expect(paused == animated)
}

@Test func draggingBobUpdatesAttachedRenderSnapshot() async throws {
    var (world, entities) = PendulumScene.makeWorld()
    let start = try #require(world.transforms[entities.bob]?.position)
    let target = Vec2(x: 0.4, y: -0.95)

    world.pointerDown(at: start)
    world.pointerMoved(to: target)
    world.pointerUp(at: target)

    #expect(world.transforms[entities.bob]?.position == target)

    let snapshot = world.snapshot()
    let hasStringAttachedToBob = snapshot.primitives.contains {
        guard case .line(let lineStart, let lineEnd, _, _) = $0 else { return false }
        return lineStart == .zero && lineEnd == target
    }
    #expect(hasStringAttachedToBob)
}

@Test func forceArrowsAreHiddenUntilBobHover() async throws {
    var (world, entities) = PendulumScene.makeWorld()
    let hiddenSnapshot = world.snapshot()
    #expect(hiddenSnapshot.primitives.count == 3)

    let bobPosition = try #require(world.transforms[entities.bob]?.position)
    world.pointerMoved(to: bobPosition)

    let visibleSnapshot = world.snapshot()
    let arrowCount = visibleSnapshot.primitives.filter {
        if case .arrow = $0 { return true }
        return false
    }.count
    #expect(arrowCount == 2)
}
