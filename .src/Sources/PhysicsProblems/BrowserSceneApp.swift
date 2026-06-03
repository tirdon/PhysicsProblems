import JavaScriptEventLoop
import JavaScriptKit

final class BrowserSceneApp: @unchecked Sendable {
    private var world: SceneWorld
    private var renderer: WebGPURenderer?
    private var lastFrameTimestamp: Double?

    private var animationFrameClosure: JSClosure?
    private var pointerMoveClosure: JSClosure?
    private var pointerDownClosure: JSClosure?
    private var pointerUpClosure: JSClosure?

    init() {
        (world, _) = PendulumScene.makeWorld()
    }

    func start() async throws(JSException) {
        renderer = try await WebGPURenderer.create(canvasID: "main-canvas")
        installPointerHandlers()
        renderer?.render(world.snapshot())
        startAnimationLoop()
    }

    private func installPointerHandlers() {
        pointerMoveClosure = JSClosure { arguments in
            guard let event = arguments.first?.object else { return .undefined }
            _ = event.preventDefault?()
            self.handlePointerMove(event)
            return .undefined
        }

        pointerDownClosure = JSClosure { arguments in
            guard let event = arguments.first?.object else { return .undefined }
            _ = event.preventDefault?()
            if let pointerID = event.pointerId.number {
                self.rendererCanvasSetPointerCapture(event: event, pointerID: pointerID)
            }
            self.handlePointerDown(event)
            return .undefined
        }

        pointerUpClosure = JSClosure { arguments in
            guard let event = arguments.first?.object else { return .undefined }
            _ = event.preventDefault?()
            self.handlePointerUp(event)
            return .undefined
        }

        if let pointerMoveClosure, let pointerDownClosure, let pointerUpClosure {
            renderer?.installPointerListeners(
                onMove: pointerMoveClosure,
                onDown: pointerDownClosure,
                onUp: pointerUpClosure
            )
        }
    }

    private func startAnimationLoop() {
        animationFrameClosure = JSClosure { arguments in
            let timestamp = arguments.first?.number ?? 0
            self.tick(timestamp: timestamp)
            return .undefined
        }
        requestNextFrame()
    }

    private func requestNextFrame() {
        guard let animationFrameClosure else { return }
        _ = JSObject.global.requestAnimationFrame!(animationFrameClosure)
    }

    private func tick(timestamp: Double) {
        let deltaTime: Double
        if let lastFrameTimestamp {
            deltaTime = (timestamp - lastFrameTimestamp) / 1000
        } else {
            deltaTime = 0
        }
        lastFrameTimestamp = timestamp

        world.update(deltaTime: deltaTime)
        renderer?.render(world.snapshot())
        requestNextFrame()
    }

    private func handlePointerMove(_ event: JSObject) {
        guard let renderer else { return }
        world.pointerMoved(to: renderer.worldPoint(from: event))
        renderer.render(world.snapshot())
    }

    private func handlePointerDown(_ event: JSObject) {
        guard let renderer else { return }
        world.pointerDown(at: renderer.worldPoint(from: event))
        renderer.render(world.snapshot())
    }

    private func handlePointerUp(_ event: JSObject) {
        guard let renderer else { return }
        world.pointerUp(at: renderer.worldPoint(from: event))
        renderer.render(world.snapshot())
    }

    private func rendererCanvasSetPointerCapture(event: JSObject, pointerID: Double) {
        _ = event.target.object?.setPointerCapture?(pointerID)
    }
}
