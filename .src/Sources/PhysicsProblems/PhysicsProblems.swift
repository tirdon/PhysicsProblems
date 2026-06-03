import JavaScriptEventLoop
import JavaScriptKit
import PhysicsEngine
import Foundation

// swift package --package-path .src --scratch-path .build --swift-sdk 6.3-RELEASE-wasm32-unknown-wasip1-threads --allow-writing-to-directory script js --use-cdn --output script

@main
struct PhysicsProblems {
    @MainActor static var animationClosure: JSClosure?
    @MainActor static var onMoveClosure: JSClosure?
    @MainActor static var onDownClosure: JSClosure?
    @MainActor static var onUpClosure: JSClosure?

    static func main() {
        JavaScriptEventLoop.installGlobalExecutor()
        Task {
            let engine = Engine { scene in
                scene.registerSystem(PendulumAnimationSystem.self)

				let circle = Pendulum()
                scene.add(circle)

                scene.play(circle.shift(1.i + 2.j))
				
                scene.play(circle.move(to: .origin))
                await scene.wait()
                
                circle.pendulumAnimation = PendulumPhysicsComponent(
                    length: 2.0,
                    baseAngle: 0,
                    amplitude: 0.28,
                    period: 2.4
                )
				
				circle.interaction = InteractionComponent(
					hoverable: true, draggable: true, pauseAnimationOnHover: true
				)
				
				await scene.wait(second: 4)
				await scene.pause(system: PendulumAnimationSystem.self)
				scene.play(circle.edge(to: .bottom))
            }

            // Set up JS renderer and animation loop
            guard let primaryScene = engine.primaryScene else { return }

            do {
                let renderer = try await createJSRenderer(canvasID: "main-canvas")

                // Render initial frame
                renderScene(primaryScene, with: renderer)

                // Install pointer handlers
                installPointerHandlers(scene: primaryScene, renderer: renderer)

                // Start animation loop
                startAnimationLoop(scene: primaryScene, renderer: renderer)
            } catch {
                let console = JSObject.global.console
				_ = console.error("Failed to initialize renderer: \(error)")
            }
        }
    }
}

// MARK: - JS Renderer Bridge

private func createJSRenderer(canvasID: String) async throws -> JSObject {
    let global = JSObject.global
    let rendererModule = global.WebGPURendererModule
    if rendererModule.isUndefined {
        // Fall back to creating directly via the class on global
        let rendererClass = global.WebGPURenderer
        guard !rendererClass.isUndefined else {
            throw JSError(message: "WebGPURenderer not found on global scope")
        }
		let promise = rendererClass.create(canvasID)
        guard let promiseObj = promise.object else {
            throw JSError(message: "WebGPURenderer.create did not return an object")
        }
        guard let result = try await JSPromise(unsafelyWrapping: promiseObj).value.object else {
            throw JSError(message: "WebGPURenderer.create resolved to nil")
        }
        return result
    }
	let promise = rendererModule.create(canvasID)
    guard let promiseObj = promise.object else {
        throw JSError(message: "Renderer create did not return a promise")
    }
    guard let result = try await JSPromise(unsafelyWrapping: promiseObj).value.object else {
        throw JSError(message: "Renderer create resolved to nil")
    }
    return result
}

@MainActor private func renderScene(_ scene: SceneWorld, with renderer: JSObject) {
    if let viewportId = scene.viewportId {
        _ = renderer.setViewport!(viewportId.jsValue)
    } else {
        _ = renderer.setViewport!(JSValue.null)
    }
    
    let snapshot = scene.snapshot()
    let jsArray = primitivesToJSArray(snapshot.primitives)
    _ = renderer.render!(jsArray)
}

private func primitivesToJSArray(_ primitives: [RenderPrimitive]) -> JSValue {
    var array: [JSValue] = []
    for prim in primitives {
        switch prim {
        case .circle(let center, let radius, let color):
            array.append(makeJSObj([
                ("type", "circle".jsValue),
                ("center", makeJSObj([("x", center.x.jsValue), ("y", center.y.jsValue), ("z", center.z.jsValue)])),
                ("radius", Double(radius).jsValue),
                ("color", colorToJS(color))
            ]))
        case .ellipse(let center, let major, let minor, let rotation, let color):
            array.append(makeJSObj([
                ("type", "ellipse".jsValue),
                ("center", makeJSObj([("x", center.x.jsValue), ("y", center.y.jsValue), ("z", center.z.jsValue)])),
                ("major", Double(major).jsValue),
                ("minor", Double(minor).jsValue),
                ("rotation", Double(rotation).jsValue),
                ("color", colorToJS(color))
            ]))
        case .line(let start, let end, let width, let color):
            array.append(makeJSObj([
                ("type", "line".jsValue),
                ("start", makeJSObj([("x", start.x.jsValue), ("y", start.y.jsValue), ("z", start.z.jsValue)])),
                ("end", makeJSObj([("x", end.x.jsValue), ("y", end.y.jsValue), ("z", end.z.jsValue)])),
                ("width", Double(width).jsValue),
                ("color", colorToJS(color))
            ]))
        case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth, let tipShape, let tailShape, let color):
            var props: [(String, JSValue)] = [
                ("type", "arrow".jsValue),
                ("start", makeJSObj([("x", start.x.jsValue), ("y", start.y.jsValue), ("z", start.z.jsValue)])),
                ("end", makeJSObj([("x", end.x.jsValue), ("y", end.y.jsValue), ("z", end.z.jsValue)])),
                ("shaftWidth", Double(shaftWidth).jsValue),
                ("headLength", Double(headLength).jsValue),
                ("headWidth", Double(headWidth).jsValue),
                ("color", colorToJS(color))
            ]
            if let tip = tipShape { props.append(("tipShape", tip.rawValue.jsValue)) }
            if let tail = tailShape { props.append(("tailShape", tail.rawValue.jsValue)) }
            array.append(makeJSObj(props))
        case .rect(let center, let width, let height, let rotation, let color):
            array.append(makeJSObj([
                ("type", "rect".jsValue),
                ("center", makeJSObj([("x", center.x.jsValue), ("y", center.y.jsValue), ("z", center.z.jsValue)])),
                ("width", Double(width).jsValue),
                ("height", Double(height).jsValue),
                ("rotation", Double(rotation).jsValue),
                ("color", colorToJS(color))
            ]))
        case .polygon(let points, let color):
            let pointsArr = points.map { makeJSObj([("x", $0.x.jsValue), ("y", $0.y.jsValue), ("z", $0.z.jsValue)]) }
            array.append(makeJSObj([
                ("type", "polygon".jsValue),
                ("points", pointsArr.jsValue),
                ("color", colorToJS(color))
            ]))
        case .arc(let center, let radius, let startAngle, let endAngle, let color):
            array.append(makeJSObj([
                ("type", "arc".jsValue),
                ("center", makeJSObj([("x", center.x.jsValue), ("y", center.y.jsValue), ("z", center.z.jsValue)])),
                ("radius", Double(radius).jsValue),
                ("startAngle", Double(startAngle).jsValue),
                ("endAngle", Double(endAngle).jsValue),
                ("color", colorToJS(color))
            ]))
        }
    }
    return array.jsValue
}

private func colorToJS(_ color: Color) -> JSValue {
    makeJSObj([
        ("r", Double(color.r).jsValue),
        ("g", Double(color.g).jsValue),
        ("b", Double(color.b).jsValue),
        ("a", Double(color.a).jsValue)
    ])
}

private func makeJSObj(_ entries: [(String, JSValue)]) -> JSValue {
    let obj = JSObject.global.Object.function!.new()
    for (key, value) in entries {
        obj[key] = value
    }
    return obj.jsValue
}

// MARK: - Pointer Handling

@MainActor private func updateCursor(scene: SceneWorld, renderer: JSObject) {
    let target = renderer.pointerTarget.object ?? renderer.canvas.object!
    let style = target.style.object!
    
    if scene.draggedEntity != nil {
        style.cursor = "grabbing".jsValue
    } else if let hovered = scene.hoveredEntity,
        hovered.components[PhysicsBodyComponent.self] != nil {
        style.cursor = "grab".jsValue
    } else {
        style.cursor = "default".jsValue
    }
}

@MainActor private func installPointerHandlers(scene: SceneWorld, renderer: JSObject) {
    let onMove = JSClosure { arguments -> JSValue in
        guard let pointObj = arguments.first?.object else { return .undefined }
        let x = Float(pointObj.x.number ?? 0)
        let y = Float(pointObj.y.number ?? 0)
        scene.pointerMoved(to: SIMD3<Float>(x, y, 0))
        updateCursor(scene: scene, renderer: renderer)
        renderScene(scene, with: renderer)
        return .undefined
    }

    let onDown = JSClosure { arguments -> JSValue in
        guard let pointObj = arguments.first?.object else { return .undefined }
        let x = Float(pointObj.x.number ?? 0)
        let y = Float(pointObj.y.number ?? 0)
        scene.pointerDown(at: SIMD3<Float>(x, y, 0))
        updateCursor(scene: scene, renderer: renderer)
        renderScene(scene, with: renderer)
        return .undefined
    }

    let onUp = JSClosure { arguments -> JSValue in
        guard let pointObj = arguments.first?.object else { return .undefined }
        let x = Float(pointObj.x.number ?? 0)
        let y = Float(pointObj.y.number ?? 0)
        scene.pointerUp(at: SIMD3<Float>(x, y, 0))
        updateCursor(scene: scene, renderer: renderer)
        renderScene(scene, with: renderer)
        return .undefined
    }

    PhysicsProblems.onMoveClosure = onMove
    PhysicsProblems.onDownClosure = onDown
    PhysicsProblems.onUpClosure = onUp

    _ = renderer.installPointerListeners!(onMove, onDown, onUp)
}

// MARK: - Animation Loop

@MainActor private func startAnimationLoop(scene: SceneWorld, renderer: JSObject) {
    let callback = JSClosure { arguments -> JSValue in
        let deltaTime = Float(arguments.first?.number ?? 0)
        scene.update(deltaTime: deltaTime)
        renderScene(scene, with: renderer)
        return .undefined
    }

    PhysicsProblems.animationClosure = callback
    _ = renderer.startAnimationLoop!(callback)
}

// MARK: - JSError Helper

struct JSError: Error {
    let message: String
}
