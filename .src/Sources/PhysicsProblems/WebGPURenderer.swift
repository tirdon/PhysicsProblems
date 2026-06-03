import Foundation
import JavaScriptEventLoop
import JavaScriptKit

final class WebGPURenderer {
    private let canvas: JSObject
    private let context: JSObject
    private let device: JSObject
    private let queue: JSObject
    private let pipeline: JSObject
    private let format: String

    private var vertexBuffer: JSObject?
    private var vertexCapacity = 0
    private var viewportPixels = (width: 400, height: 400)

    private let cameraCenter = Vec2(x: 0, y: -0.45)
    private let cameraHeight = 2.5

    static func create(canvasID: String) async throws(JSException) -> WebGPURenderer {
        let global = JSObject.global
        let document = try requireObject(global.document, "document is not available")
        let canvas = try requireObject(document.getElementById!(canvasID), "Canvas #\(canvasID) was not found")
        let navigator = try requireObject(global.navigator, "navigator is not available")
        let gpu = try requireObject(navigator.gpu, "WebGPU is not supported by this browser")

        let adapterPromise = try requireObject(gpu.requestAdapter!(), "navigator.gpu.requestAdapter() did not return a Promise")
        let adapter = try requireObject(try await JSPromise(unsafelyWrapping: adapterPromise).value, "WebGPU adapter was not available")
        let devicePromise = try requireObject(adapter.requestDevice!(), "GPUAdapter.requestDevice() did not return a Promise")
        let device = try requireObject(try await JSPromise(unsafelyWrapping: devicePromise).value, "WebGPU device was not available")
        let queue = try requireObject(device.queue, "GPUDevice.queue is not available")
        let context = try requireObject(canvas.getContext!("webgpu"), "Canvas does not provide a WebGPU context")
        let format = try requireString(gpu.getPreferredCanvasFormat!(), "WebGPU preferred canvas format is not a string")

        _ = context.configure!(makeJSObject([
            ("device", device.jsValue),
            ("format", format.jsValue),
            ("alphaMode", "opaque".jsValue)
        ]))

        let shaderModule = try requireFunctionResult(
            device.createShaderModule!(makeJSObject([("code", shaderSource.jsValue)])),
            "Failed to create WebGPU shader module"
        )
        let pipeline = try requireFunctionResult(
            device.createRenderPipeline!(pipelineDescriptor(shaderModule: shaderModule, format: format)),
            "Failed to create WebGPU render pipeline"
        )

        let renderer = WebGPURenderer(
            canvas: canvas,
            context: context,
            device: device,
            queue: queue,
            pipeline: pipeline,
            format: format
        )
        renderer.resizeCanvas()
        return renderer
    }

    func installPointerListeners(onMove: JSClosure, onDown: JSClosure, onUp: JSClosure) {
        _ = canvas.addEventListener!("pointermove", onMove)
        _ = canvas.addEventListener!("pointerdown", onDown)
        _ = canvas.addEventListener!("pointerup", onUp)
        _ = canvas.addEventListener!("pointerleave", onUp)
    }

    func worldPoint(from event: JSObject) -> Vec2 {
        let rect = canvas.getBoundingClientRect!().object!
        let left = rect.left.number ?? 0
        let top = rect.top.number ?? 0
        let width = max(rect.width.number ?? 1, 1)
        let height = max(rect.height.number ?? 1, 1)
        let normalizedX = ((event.clientX.number ?? 0) - left) / width
        let normalizedY = ((event.clientY.number ?? 0) - top) / height
        let cameraWidth = cameraHeight * aspectRatio

        return Vec2(
            x: cameraCenter.x + (normalizedX * 2 - 1) * cameraWidth * 0.5,
            y: cameraCenter.y + (1 - normalizedY * 2) * cameraHeight * 0.5
        )
    }

    func render(_ snapshot: SceneSnapshot) {
        resizeCanvas()
        var builder = VertexBuilder(cameraCenter: cameraCenter, cameraHeight: cameraHeight, aspectRatio: aspectRatio)
        builder.append(snapshot: snapshot)
        let vertices = builder.vertices
        guard !vertices.isEmpty else { return }

        ensureVertexBuffer(floatCount: vertices.count)
        guard let vertexBuffer else { return }

        let typedArray = JSFloat32Array(vertices)
        _ = queue.writeBuffer!(vertexBuffer, 0, typedArray.jsObject)

        let encoder = device.createCommandEncoder!().object!
        let currentTexture = context.getCurrentTexture!().object!
        let textureView = currentTexture.createView!().object!
        let pass = encoder.beginRenderPass!(renderPassDescriptor(textureView: textureView)).object!
        _ = pass.setPipeline!(pipeline)
        _ = pass.setVertexBuffer!(0, vertexBuffer)
        _ = pass.draw!(Double(vertices.count / VertexBuilder.floatsPerVertex))
        _ = pass.end!()
        let command = encoder.finish!().object!
        _ = queue.submit!([command])
    }

    private init(canvas: JSObject, context: JSObject, device: JSObject, queue: JSObject, pipeline: JSObject, format: String) {
        self.canvas = canvas
        self.context = context
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.format = format
    }

    private var aspectRatio: Double {
        max(Double(viewportPixels.width) / Double(max(viewportPixels.height, 1)), 0.1)
    }

    private func resizeCanvas() {
        let global = JSObject.global
        let ratio = max(global.devicePixelRatio.number ?? 1, 1)
        let cssWidth = canvas.clientWidth.number ?? canvas.width.number ?? 400
        let cssHeight = canvas.clientHeight.number ?? canvas.height.number ?? 400
        let width = max(Int(cssWidth * ratio), 1)
        let height = max(Int(cssHeight * ratio), 1)
        viewportPixels = (width, height)
        if Int(canvas.width.number ?? 0) != width {
            canvas.width = Double(width).jsValue
        }
        if Int(canvas.height.number ?? 0) != height {
            canvas.height = Double(height).jsValue
        }
    }

    private func ensureVertexBuffer(floatCount: Int) {
        guard floatCount > vertexCapacity else { return }
        var capacity = max(1024, vertexCapacity)
        while capacity < floatCount {
            capacity *= 2
        }
        vertexCapacity = capacity

        let usage = bufferUsageFlag("VERTEX") + bufferUsageFlag("COPY_DST")
        vertexBuffer = device.createBuffer!(makeJSObject([
            ("size", Double(capacity * MemoryLayout<Float32>.size).jsValue),
            ("usage", usage.jsValue)
        ])).object!
    }

    private func bufferUsageFlag(_ name: String) -> Double {
        JSObject.global.GPUBufferUsage.object?[name].number ?? 0
    }

    private func renderPassDescriptor(textureView: JSObject) -> JSObject {
        makeJSObject([
            ("colorAttachments", [
                makeJSValueObject([
                    ("view", textureView.jsValue),
                    ("clearValue", makeJSValueObject([
                        ("r", Color.background.r.jsValue),
                        ("g", Color.background.g.jsValue),
                        ("b", Color.background.b.jsValue),
                        ("a", Color.background.a.jsValue)
                    ])),
                    ("loadOp", "clear".jsValue),
                    ("storeOp", "store".jsValue)
                ])
            ].jsValue)
        ])
    }
}

private func pipelineDescriptor(shaderModule: JSObject, format: String) -> JSObject {
    let vertexAttributes: [JSValue] = [
        makeJSValueObject([
            ("shaderLocation", Int32(0).jsValue),
            ("offset", Int32(0).jsValue),
            ("format", "float32x2".jsValue)
        ]),
        makeJSValueObject([
            ("shaderLocation", Int32(1).jsValue),
            ("offset", Int32(8).jsValue),
            ("format", "float32x4".jsValue)
        ])
    ]

    let blend = makeJSValueObject([
        ("color", makeJSValueObject([
            ("srcFactor", "src-alpha".jsValue),
            ("dstFactor", "one-minus-src-alpha".jsValue),
            ("operation", "add".jsValue)
        ])),
        ("alpha", makeJSValueObject([
            ("srcFactor", "one".jsValue),
            ("dstFactor", "one-minus-src-alpha".jsValue),
            ("operation", "add".jsValue)
        ]))
    ])

    return makeJSObject([
        ("layout", "auto".jsValue),
        ("vertex", makeJSValueObject([
            ("module", shaderModule.jsValue),
            ("entryPoint", "vs_main".jsValue),
            ("buffers", [
                makeJSValueObject([
                    ("arrayStride", Int32(24).jsValue),
                    ("attributes", vertexAttributes.jsValue)
                ])
            ].jsValue)
        ])),
        ("fragment", makeJSValueObject([
            ("module", shaderModule.jsValue),
            ("entryPoint", "fs_main".jsValue),
            ("targets", [
                makeJSValueObject([
                    ("format", format.jsValue),
                    ("blend", blend)
                ])
            ].jsValue)
        ])),
        ("primitive", makeJSValueObject([
            ("topology", "triangle-list".jsValue)
        ]))
    ])
}

private let shaderSource = """
struct VertexInput {
  @location(0) position: vec2f,
  @location(1) color: vec4f,
}

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
}

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
  var output: VertexOutput;
  output.position = vec4f(input.position, 0.0, 1.0);
  output.color = input.color;
  return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4f {
  return input.color;
}
"""

private struct VertexBuilder {
    static let floatsPerVertex = 6

    var vertices: [Float32] = []
    let cameraCenter: Vec2
    let cameraHeight: Double
    let aspectRatio: Double

    mutating func append(snapshot: SceneSnapshot) {
        for primitive in snapshot.primitives {
            switch primitive {
            case .circle(let center, let radius, let color):
                appendCircle(center: center, radius: radius, color: color)
            case .line(let start, let end, let width, let color):
                appendLine(start: start, end: end, width: width, color: color)
            case .arrow(let start, let end, let shaftWidth, let headLength, let headWidth, let color):
                appendArrow(start: start, end: end, shaftWidth: shaftWidth, headLength: headLength, headWidth: headWidth, color: color)
            }
        }
    }

    mutating private func appendCircle(center: Vec2, radius: Double, color: Color) {
        let segments = 48
        for index in 0..<segments {
            let a0 = (Double(index) / Double(segments)) * Double.pi * 2
            let a1 = (Double(index + 1) / Double(segments)) * Double.pi * 2
            appendTriangle(
                center,
                center + Vec2(x: cos(a0), y: sin(a0)) * radius,
                center + Vec2(x: cos(a1), y: sin(a1)) * radius,
                color: color
            )
        }
    }

    mutating private func appendLine(start: Vec2, end: Vec2, width: Double, color: Color) {
        let direction = end - start
        guard direction.length > 0.0001 else { return }
        let normal = Vec2(x: -direction.normalized.y, y: direction.normalized.x) * (width * 0.5)
        appendTriangle(start + normal, start - normal, end + normal, color: color)
        appendTriangle(end + normal, start - normal, end - normal, color: color)
    }

    mutating private func appendArrow(start: Vec2, end: Vec2, shaftWidth: Double, headLength: Double, headWidth: Double, color: Color) {
        let vector = end - start
        let length = vector.length
        guard length > 0.0001 else { return }
        let direction = vector / length
        let actualHeadLength = min(headLength, length * 0.45)
        let headBase = end - direction * actualHeadLength
        appendLine(start: start, end: headBase, width: shaftWidth, color: color)

        let normal = Vec2(x: -direction.y, y: direction.x) * (headWidth * 0.5)
        appendTriangle(end, headBase + normal, headBase - normal, color: color)
    }

    mutating private func appendTriangle(_ a: Vec2, _ b: Vec2, _ c: Vec2, color: Color) {
        appendVertex(a, color: color)
        appendVertex(b, color: color)
        appendVertex(c, color: color)
    }

    mutating private func appendVertex(_ point: Vec2, color: Color) {
        let clip = project(point)
        vertices.append(Float32(clip.x))
        vertices.append(Float32(clip.y))
        vertices.append(Float32(color.r))
        vertices.append(Float32(color.g))
        vertices.append(Float32(color.b))
        vertices.append(Float32(color.a))
    }

    private func project(_ point: Vec2) -> Vec2 {
        let cameraWidth = cameraHeight * aspectRatio
        return Vec2(
            x: (point.x - cameraCenter.x) / (cameraWidth * 0.5),
            y: (point.y - cameraCenter.y) / (cameraHeight * 0.5)
        )
    }
}
