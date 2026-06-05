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
    @MainActor static var togglePauseClosure: JSClosure?
    @MainActor static var seekClosure: JSClosure?
    @MainActor static var setPausedClosure: JSClosure?
    static func main() {
        JavaScriptEventLoop.installGlobalExecutor()
        Task {
            let engine = Engine { scene in
                scene.registerSystem(PendulumAnimationSystem.self)

				let pendulum = Pendulum()
                scene.add(pendulum)

                scene.play(pendulum.shift(1.i + 2.j, easing: .easeOut))
                scene.play(pendulum.move(to: .origin, easing: .easeInOut))
				await scene.wait()
//                scene.run {
                    pendulum.first(where: { $0 is Circle })?.components[PendulumPhysicsComponent.self] = PendulumPhysicsComponent(
                        length: pendulum.string.length,
                        baseAngle: 0,
                        amplitude: 0.28,
                        period: 2.4
                    )
                    pendulum.first(where: { $0 is Circle })?.interaction = InteractionComponent(
                        hoverable: true, draggable: true, pauseAnimationOnHover: true
                    )
//                }
				
				scene.delay(4)
//				scene.run {
					pendulum.bob.color(.cyan)
				await scene.pause(system: PendulumAnimationSystem.self)
//				}
				scene.play(pendulum.edge(to: .bottom, easing: .easeIn))
            }

            // Set up JS renderer and animation loop
            guard let primaryScene = engine.primary else { return }

            do {
                let renderer = try await createJSRenderer(canvasID: "main-canvas")

                // Render initial frame
                renderScene(primaryScene, with: renderer)

                // Install pointer handlers
                installPointerHandlers(scene: primaryScene, renderer: renderer)

                // Install timeline controller (keyframe clips, excludes system)
                installTimelineController(scene: primaryScene, renderer: renderer)

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
    
    if !renderer.setCamera.isUndefined {
        let cam = scene.camera
        let jsCam = makeJSObj([
            ("position", vec3ToJS(cam.transform.position)),
            ("orientation", makeJSObj([("x", cam.transform.orientation.x.jsValue), ("y", cam.transform.orientation.y.jsValue), ("z", cam.transform.orientation.z.jsValue), ("w", cam.transform.orientation.w.jsValue)])),
            ("fov", Float64(cam.fov).jsValue)
        ])
        _ = renderer.setCamera!(jsCam)
    }
    
    let snapshot = scene.snapshot()
    let jsArray = primitivesToJSArray(snapshot.primitives)
    _ = renderer.render!(jsArray)

    // Send timeline state to JS (keyframe clips only, excludes system)
    let tlState = scene.timeline.state
    let jsTl = timelineStateToJS(tlState)
    let global = JSObject.global
    if let ctrl = global.TimelineController.object,
       !ctrl.updateState.isUndefined {
        _ = ctrl.updateState!(jsTl)
    }
}

private func primitivesToJSArray(_ primitives: [RenderPrimitive]) -> JSValue {
    var array: [JSValue] = []
    
    func addStyle(_ props: inout [(String, JSValue)], style: RenderStyleComponent) {
        props.append(("color", colorToJS(style.color.with(opacity: style.opacity))))
        if let stroke = style.strokeColor {
            props.append(("strokeColor", colorToJS(stroke.with(opacity: style.opacity))))
            props.append(("strokeWidth", Double(style.strokeWidth).jsValue))
            props.append(("strokeStyle", style.strokeStyle.rawValue.jsValue))
            props.append(("strokeCap", style.strokeCap.rawValue.jsValue))
        }
    }

    for prim in primitives {
        switch prim {
        case .circle(let center, let radius, let style):
            var props: [(String, JSValue)] = [
                ("type", "circle".jsValue),
                ("center", vec3ToJS(center)),
                ("radius", Double(radius).jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .ellipse(let center, let major, let minor, let rotation, let style):
            var props: [(String, JSValue)] = [
                ("type", "ellipse".jsValue),
                ("center", vec3ToJS(center)),
                ("major", Double(major).jsValue),
                ("minor", Double(minor).jsValue),
                ("rotation", Double(rotation).jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .line(let start, let end, let width, let style):
            var props: [(String, JSValue)] = [
                ("type", "line".jsValue),
                ("start", vec3ToJS(start)),
                ("end", vec3ToJS(end)),
                ("width", Double(width).jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth, let tipShape, let tailShape, let style):
            var props: [(String, JSValue)] = [
                ("type", "arrow".jsValue),
                ("start", vec3ToJS(start)),
                ("end", vec3ToJS(end)),
                ("shaftWidth", Double(shaftWidth).jsValue),
                ("headLength", Double(headLength).jsValue),
                ("headWidth", Double(headWidth).jsValue)
            ]
            addStyle(&props, style: style)
            if let tip = tipShape { props.append(("tipShape", tip.rawValue.jsValue)) }
            if let tail = tailShape { props.append(("tailShape", tail.rawValue.jsValue)) }
            array.append(makeJSObj(props))
            
        case .rect(let center, let width, let height, let rotation, let style):
            var props: [(String, JSValue)] = [
                ("type", "rect".jsValue),
                ("center", vec3ToJS(center)),
                ("width", Double(width).jsValue),
                ("height", Double(height).jsValue),
                ("rotation", Double(rotation).jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .polygon(let points, let style):
            let pointsArr = points.map { vec3ToJS($0) }
            var props: [(String, JSValue)] = [
                ("type", "polygon".jsValue),
                ("points", pointsArr.jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .arc(let center, let radius, let startAngle, let endAngle, let style):
            var props: [(String, JSValue)] = [
                ("type", "arc".jsValue),
                ("center", vec3ToJS(center)),
                ("radius", Double(radius).jsValue),
                ("startAngle", Double(startAngle).jsValue),
                ("endAngle", Double(endAngle).jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .wall(let start, let end, let spacing, let face, let style):
            var props: [(String, JSValue)] = [
                ("type", "wall".jsValue),
                ("start", vec3ToJS(start)),
                ("end", vec3ToJS(end)),
                ("spacing", Double(spacing).jsValue),
                ("face", vec3ToJS(face))
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))

        case .path(let contours, let drawing, let windingMode, let style):
            let contoursArray = contours.map { contour in
                let pointsArray = contour.points.map { vec3ToJS($0) }
                return makeJSObj([
                    ("points", pointsArray.jsValue),
                    ("closed", contour.isClosed.jsValue)
                ])
            }
            var props: [(String, JSValue)] = [
                ("type", "path".jsValue),
                ("contours", contoursArray.jsValue),
                ("windingMode", windingMode.rawValue.jsValue)
            ]
            switch drawing {
            case .fill:
                props.append(("drawing", "fill".jsValue))
            case .stroke(let width):
                props.append(("drawing", "stroke".jsValue))
                props.append(("pathStrokeWidth", Double(width).jsValue))
            }
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
            
        case .mesh(let vertices, let normals, let indices, let shading, let style):
            let vArr = vertices.map { vec3ToJS($0) }
            let nArr = normals.map { vec3ToJS($0) }
            let iArr = indices.map { Double($0).jsValue }
            var props: [(String, JSValue)] = [
                ("type", "mesh".jsValue),
                ("vertices", vArr.jsValue),
                ("normals", nArr.jsValue),
                ("indices", iArr.jsValue),
                ("shading", shading.rawValue.jsValue)
            ]
            addStyle(&props, style: style)
            array.append(makeJSObj(props))
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

private func vec3ToJS(_ v: SIMD3<Float>) -> JSValue {
    makeJSObj([("x", v.x.jsValue), ("y", v.y.jsValue), ("z", v.z.jsValue)])
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
        hovered.interaction?.draggable == true {
        style.cursor = "grab".jsValue
    } else {
        style.cursor = "default".jsValue
    }
}

@MainActor private func installPointerHandlers(scene: SceneWorld, renderer: JSObject) {
    func makePointerClosure(_ handler: @escaping (SceneWorld, SIMD3<Float>) -> Void) -> JSClosure {
        JSClosure { arguments -> JSValue in
            guard let pointObj = arguments.first?.object else { return .undefined }
            let x = Float(pointObj.x.number ?? 0)
            let y = Float(pointObj.y.number ?? 0)
            handler(scene, SIMD3<Float>(x, y, 0))
            updateCursor(scene: scene, renderer: renderer)
            renderScene(scene, with: renderer)
            return .undefined
        }
    }

    let onMove = makePointerClosure { $0.pointerMoved(to: $1) }
    let onDown = makePointerClosure { $0.pointerDown(at: $1) }
    let onUp = makePointerClosure { $0.pointerUp(at: $1) }

    PhysicsProblems.onMoveClosure = onMove
    PhysicsProblems.onDownClosure = onDown
    PhysicsProblems.onUpClosure = onUp

    _ = renderer.installPointerListeners!(onMove, onDown, onUp)
}

// MARK: - Animation Loop

@MainActor private func startAnimationLoop(scene: SceneWorld, renderer: JSObject) {
    let callback = JSClosure { arguments -> JSValue in
        let dt = Float(arguments.first?.number ?? 0)
        let deltaTime = scene.timeline.isPaused ? 0 : dt
        scene.update(deltaTime: deltaTime)
        renderScene(scene, with: renderer)
        return .undefined
    }

    PhysicsProblems.animationClosure = callback
    _ = renderer.startAnimationLoop!(callback)
}

// MARK: - Timeline Bridge

@MainActor private func installTimelineController(scene: SceneWorld, renderer: JSObject) {
    let togglePause = JSClosure { _ -> JSValue in
        scene.timeline.togglePause()
        return scene.timeline.isPaused.jsValue
    }

    let seek = JSClosure { arguments -> JSValue in
        let time = Float(arguments.first?.number ?? 0)
        scene.timeline.seek(to: time, in: scene)
        return .undefined
    }

    let setPaused = JSClosure { arguments -> JSValue in
        let paused = arguments.first?.boolean ?? false
        scene.timeline.setPaused(paused)
        return .undefined
    }

    PhysicsProblems.togglePauseClosure = togglePause
    PhysicsProblems.seekClosure = seek
    PhysicsProblems.setPausedClosure = setPaused

    let global = JSObject.global
    // Merge onto existing object (timeline.js may have already set updateState)
    let ctrl: JSObject
    if let existing = global.TimelineController.object {
        ctrl = existing
    } else {
        ctrl = global.Object.function!.new()
    }
    ctrl.togglePause = togglePause.jsValue
    ctrl.seek = seek.jsValue
    ctrl.setPaused = setPaused.jsValue
    global.TimelineController = ctrl.jsValue
}

private func timelineStateToJS(_ state: TimelineState) -> JSValue {
    let clipsJS = state.clips.map { clip -> JSValue in
        let tracksJS = clip.tracks.map { track -> JSValue in
            let kfTimes = track.keyframeTimes.map { Double($0).jsValue }
            return makeJSObj([
                ("keyPath", track.keyPath.jsValue),
                ("duration", Double(track.duration).jsValue),
                ("keyframeTimes", kfTimes.jsValue)
            ])
        }
        return makeJSObj([
            ("index", Double(clip.index).jsValue),
            ("startTime", Double(clip.startTime).jsValue),
            ("duration", Double(clip.duration).jsValue),
            ("tracks", tracksJS.jsValue),
            ("isCurrent", clip.isCurrent.jsValue)
        ])
    }
    return makeJSObj([
        ("clips", clipsJS.jsValue),
        ("totalDuration", Double(state.totalDuration).jsValue),
        ("currentTime", Double(state.currentTime).jsValue),
        ("isPaused", state.isPaused.jsValue)
    ])
}

// MARK: - JSError Helper

struct JSError: Error {
    let message: String
}
