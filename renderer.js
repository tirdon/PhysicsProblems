/**
 * WebGPU Renderer for PhysicsProblems
 * Renders scene primitives (circles, lines, arrows) using WebGPU.
 * Called from Swift WASM via JavaScriptKit interop.
 */

// MARK: - WGSL Shaders

const SHADER_SOURCE = `
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
`;

// MARK: - Constants

const FLOATS_PER_VERTEX = 6; // x, y, r, g, b, a
const BYTES_PER_VERTEX = FLOATS_PER_VERTEX * 4; // 24 bytes
const CIRCLE_SEGMENTS = 48;
const CLEAR_COLOR = { r: 0.08, g: 0.09, b: 0.11, a: 1.0 };

// MARK: - WebGPURenderer

export class WebGPURenderer {
  /**
   * Creates and initializes a WebGPU renderer attached to the given canvas.
   * @param {string} canvasId - The DOM id of the canvas element.
   * @returns {Promise<WebGPURenderer>}
   */
  static async create(canvasId) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) throw new Error(`Canvas #${canvasId} was not found`);

    const gpu = navigator.gpu;
    if (!gpu) throw new Error('WebGPU is not supported by this browser');

    const adapter = await gpu.requestAdapter();
    if (!adapter) throw new Error('WebGPU adapter was not available');

    const device = await adapter.requestDevice();
    if (!device) throw new Error('WebGPU device was not available');

    const context = canvas.getContext('webgpu');
    if (!context) throw new Error('Canvas does not provide a WebGPU context');

    const format = gpu.getPreferredCanvasFormat();

    context.configure({
      device,
      format,
      alphaMode: 'opaque',
    });

    // Create shader module
    const shaderModule = device.createShaderModule({ code: SHADER_SOURCE });

    // Create render pipeline with alpha blending
    const pipeline = device.createRenderPipeline({
      layout: 'auto',
      vertex: {
        module: shaderModule,
        entryPoint: 'vs_main',
        buffers: [{
          arrayStride: BYTES_PER_VERTEX,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x2' },   // position
            { shaderLocation: 1, offset: 8, format: 'float32x4' },   // color
          ],
        }],
      },
      fragment: {
        module: shaderModule,
        entryPoint: 'fs_main',
        targets: [{
          format,
          blend: {
            color: {
              srcFactor: 'src-alpha',
              dstFactor: 'one-minus-src-alpha',
              operation: 'add',
            },
            alpha: {
              srcFactor: 'one',
              dstFactor: 'one-minus-src-alpha',
              operation: 'add',
            },
          },
        }],
      },
      primitive: {
        topology: 'triangle-list',
      },
    });

    return new WebGPURenderer(canvas, context, device, pipeline, format);
  }

  /**
   * @private
   */
  constructor(canvas, context, device, pipeline, format) {
    this.canvas = canvas;
    this.context = context;
    this.device = device;
    this.queue = device.queue;
    this.pipeline = pipeline;
    this.format = format;

    // Vertex buffer management
    this.vertexBuffer = null;
    this.vertexCapacity = 0;

    // Camera settings
    this.cameraCenter = { x: 0, y: -0.45 };
    this.cameraHeight = 2.5;

    // Viewport tracking
    this.viewportWidth = 400;
    this.viewportHeight = 400;
    this.viewportId = null;
    this._pointerTarget = canvas;

    // Initial resize
    this._resizeCanvas();
  }

  // MARK: - Public API

  /**
   * Renders an array of primitives using WebGPU.
   * @param {Array} primitives - Array of primitive objects.
   */
  render(primitives) {
    this._resizeCanvas();

    const vertices = this._buildVertices(primitives);
    if (vertices.length === 0) return;

    this._ensureVertexBuffer(vertices.length);
    if (!this.vertexBuffer) return;

    // Upload vertex data
    const data = new Float32Array(vertices);
    this.queue.writeBuffer(this.vertexBuffer, 0, data);

    // Create command encoder and render pass
    const encoder = this.device.createCommandEncoder();
    const textureView = this.context.getCurrentTexture().createView();

    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view: textureView,
        clearValue: CLEAR_COLOR,
        loadOp: 'clear',
        storeOp: 'store',
      }],
    });

    pass.setPipeline(this.pipeline);
    pass.setVertexBuffer(0, this.vertexBuffer);
    pass.draw(vertices.length / FLOATS_PER_VERTEX);
    pass.end();

    this.queue.submit([encoder.finish()]);
  }

  /**
   * Converts a pointer event to world coordinates.
   * @param {PointerEvent} event
   * @returns {{ x: number, y: number, z: number }}
   */
  worldPointFromEvent(event) {
    const target = this._pointerTarget || this.canvas;
    const rect = target.getBoundingClientRect();
    const normalizedX = (event.clientX - rect.left) / Math.max(rect.width, 1);
    const normalizedY = (event.clientY - rect.top) / Math.max(rect.height, 1);

    return {
      x: this.cameraCenter.x + (normalizedX * 2 - 1) * this._cameraWidth * 0.5,
      y: this.cameraCenter.y + (1 - normalizedY * 2) * this._cameraHeight * 0.5,
      z: 0,
    };
  }

  /**
   * Sets the viewport overlay element for pointer events.
   * @param {string|null} id
   */
  setViewport(id) {
    if (this.viewportId === id) return;
    this.viewportId = id;
    const target = id ? document.getElementById(id) : this.canvas;
    if (this._pointerTarget === target) return;
    
    if (this._onMoveCallback) {
      this._removePointerListeners();
    }
    this._pointerTarget = target;
    if (this._onMoveCallback) {
      this._addPointerListeners();
    }
  }

  get pointerTarget() {
    return this._pointerTarget || this.canvas;
  }

  /**
   * Installs pointer event listeners on the canvas or viewport.
   * @param {Function} onMove - Called with world point on pointer move.
   * @param {Function} onDown - Called with world point on pointer down.
   * @param {Function} onUp - Called with world point on pointer up.
   */
  installPointerListeners(onMove, onDown, onUp) {
    this._onMoveCallback = onMove;
    this._onDownCallback = onDown;
    this._onUpCallback = onUp;
    
    this._onMoveHandler = (e) => {
      e.preventDefault();
      onMove(this.worldPointFromEvent(e));
    };
    
    this._onDownHandler = (e) => {
      e.preventDefault();
      if (e.pointerId !== undefined) {
        e.target.setPointerCapture(e.pointerId);
      }
      onDown(this.worldPointFromEvent(e));
    };
    
    this._onUpHandler = (e) => {
      e.preventDefault();
      onUp(this.worldPointFromEvent(e));
    };

    this._addPointerListeners();
  }

  _addPointerListeners() {
    const target = this._pointerTarget || this.canvas;
    target.addEventListener('pointermove', this._onMoveHandler);
    target.addEventListener('pointerdown', this._onDownHandler);
    target.addEventListener('pointerup', this._onUpHandler);
    target.addEventListener('pointerleave', this._onUpHandler);
  }

  _removePointerListeners() {
    const target = this._pointerTarget || this.canvas;
    target.removeEventListener('pointermove', this._onMoveHandler);
    target.removeEventListener('pointerdown', this._onDownHandler);
    target.removeEventListener('pointerup', this._onUpHandler);
    target.removeEventListener('pointerleave', this._onUpHandler);
  }

  /**
   * Starts an animation loop that calls the callback with deltaTime each frame.
   * @param {Function} callback - Called with deltaTime in seconds.
   */
  startAnimationLoop(callback) {
    let lastTimestamp = null;

    const tick = (timestamp) => {
      let deltaTime = 0;
      if (lastTimestamp !== null) {
        deltaTime = (timestamp - lastTimestamp) / 1000;
      }
      lastTimestamp = timestamp;
      callback(deltaTime);
      requestAnimationFrame(tick);
    };

    requestAnimationFrame(tick);
  }

  // MARK: - Private Methods

  get _aspectRatio() {
    return Math.max(this.viewportWidth / Math.max(this.viewportHeight, 1), 0.1);
  }

  get _cameraWidth() {
    return this._aspectRatio >= 1 ? 10 : 10 * this._aspectRatio;
  }

  get _cameraHeight() {
    return this._aspectRatio >= 1 ? 10 / this._aspectRatio : 10;
  }

  /**
   * Resizes the canvas to match the device pixel ratio.
   * @private
   */
  _resizeCanvas() {
    const ratio = Math.max(window.devicePixelRatio || 1, 1);
    const cssWidth = this.canvas.clientWidth || 400;
    const cssHeight = this.canvas.clientHeight || 400;
    const width = Math.max(Math.floor(cssWidth * ratio), 1);
    const height = Math.max(Math.floor(cssHeight * ratio), 1);

    this.viewportWidth = width;
    this.viewportHeight = height;

    if (this.canvas.width !== width) {
      this.canvas.width = width;
    }
    if (this.canvas.height !== height) {
      this.canvas.height = height;
    }
  }

  /**
   * Ensures the vertex buffer is large enough.
   * @param {number} floatCount - Required number of floats.
   * @private
   */
  _ensureVertexBuffer(floatCount) {
    if (floatCount <= this.vertexCapacity) return;

    let capacity = Math.max(1024, this.vertexCapacity);
    while (capacity < floatCount) {
      capacity *= 2;
    }
    this.vertexCapacity = capacity;

    this.vertexBuffer = this.device.createBuffer({
      size: capacity * 4, // 4 bytes per float
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });
  }

  /**
   * Builds the flat vertex array from primitives.
   * @param {Array} primitives
   * @returns {number[]}
   * @private
   */
  _buildVertices(primitives) {
    const vertices = [];

    for (const prim of primitives) {
      switch (prim.type) {
        case 'circle':
          this._appendCircle(vertices, prim.center, prim.radius, prim.color);
          break;
        case 'ellipse':
          this._appendEllipse(vertices, prim.center, prim.major, prim.minor, prim.rotation, prim.color);
          break;
        case 'line':
          this._appendLine(vertices, prim.start, prim.end, prim.width, prim.color);
          break;
        case 'arrow':
          this._appendArrow(vertices, prim.start, prim.end, prim.shaftWidth, prim.headLength, prim.headWidth, prim.color, prim.tipShape, prim.tailShape);
          break;
        case 'wall':
          this._appendWall(vertices, prim.start, prim.end, prim.spacing, prim.face, prim.color);
          break;
      }
    }

    return vertices;
  }

  /**
   * Appends a circle as a triangle fan.
   * @private
   */
  _appendCircle(vertices, center, radius, color) {
    this._appendEllipse(vertices, center, radius, radius, 0, color);
  }

  /**
   * Appends an ellipse as a triangle fan.
   * @private
   */
  _appendEllipse(vertices, center, major, minor, rotation, color) {
    const cosR = Math.cos(rotation);
    const sinR = Math.sin(rotation);

    for (let i = 0; i < CIRCLE_SEGMENTS; i++) {
      const a0 = (i / CIRCLE_SEGMENTS) * Math.PI * 2;
      const a1 = ((i + 1) / CIRCLE_SEGMENTS) * Math.PI * 2;

      const x0 = Math.cos(a0) * major;
      const y0 = Math.sin(a0) * minor;
      const rx0 = x0 * cosR - y0 * sinR;
      const ry0 = x0 * sinR + y0 * cosR;

      const x1 = Math.cos(a1) * major;
      const y1 = Math.sin(a1) * minor;
      const rx1 = x1 * cosR - y1 * sinR;
      const ry1 = x1 * sinR + y1 * cosR;

      this._appendTriangle(vertices,
        center,
        { x: center.x + rx0, y: center.y + ry0, z: 0 },
        { x: center.x + rx1, y: center.y + ry1, z: 0 },
        color
      );
    }
  }

  /**
   * Appends a thick line as two triangles (quad).
   * @private
   */
  _appendLine(vertices, start, end, width, color) {
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len < 0.0001) return;

    const nx = (-dy / len) * (width * 0.5);
    const ny = (dx / len) * (width * 0.5);

    const s0 = { x: start.x + nx, y: start.y + ny, z: 0 };
    const s1 = { x: start.x - nx, y: start.y - ny, z: 0 };
    const e0 = { x: end.x + nx, y: end.y + ny, z: 0 };
    const e1 = { x: end.x - nx, y: end.y - ny, z: 0 };

    this._appendTriangle(vertices, s0, s1, e0, color);
    this._appendTriangle(vertices, e0, s1, e1, color);
  }

  /**
   * Appends a wall (base line + hatch marks).
   * @private
   */
  _appendWall(vertices, start, end, spacing, face, color) {
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len < 0.0001) return;

    const dirX = dx / len;
    const dirY = dy / len;

    const lineWidth = 0.02;
    this._appendLine(vertices, start, end, lineWidth, color);

    const safeSpacing = Math.max(spacing, 0.02);
    const hatchLength = 0.1;
    // hatch is 45 degrees to the face
    const cos45 = 0.70710678;
    const sin45 = 0.70710678;
    const hx = (face.x * cos45 - face.y * sin45) * hatchLength;
    const hy = (face.x * sin45 + face.y * cos45) * hatchLength;

    const numHatches = Math.floor(len / safeSpacing);
    for (let i = 0; i <= numHatches; i++) {
      const t = i * safeSpacing;
      const pX = start.x + dirX * t;
      const pY = start.y + dirY * t;
      this._appendLine(
        vertices,
        { x: pX, y: pY, z: 0 },
        { x: pX + hx, y: pY + hy, z: 0 },
        lineWidth,
        color
      );
    }
  }

  /**
   * Appends an arrow (shaft + head triangle).
   * @private
   */
  _appendArrow(vertices, start, end, shaftWidth, headLength, headWidth, color, tipShape, tailShape) {
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const length = Math.sqrt(dx * dx + dy * dy);
    if (length < 0.0001) return;

    const dirX = dx / length;
    const dirY = dy / length;
    const actualHeadLength = Math.min(headLength, length * 0.45);

    // Calculate bases
    let tipBase = end;
    if (tipShape) {
      tipBase = {
        x: end.x - dirX * actualHeadLength,
        y: end.y - dirY * actualHeadLength,
        z: 0
      };
    }

    let tailBase = start;
    if (tailShape) {
      tailBase = {
        x: start.x + dirX * actualHeadLength,
        y: start.y + dirY * actualHeadLength,
        z: 0
      };
    }

    // Draw shaft
    this._appendLine(vertices, tailBase, tipBase, shaftWidth, color);

    // Draw tip
    if (tipShape) {
      this._appendTip(vertices, end, tipBase, dirX, dirY, headWidth, color, tipShape);
    }
    
    // Draw tail
    if (tailShape) {
      this._appendTip(vertices, start, tailBase, -dirX, -dirY, headWidth, color, tailShape);
    }
  }

  /**
   * Appends a tip shape at a given location.
   * @private
   */
  _appendTip(vertices, tip, base, dirX, dirY, headWidth, color, shape) {
    const nx = -dirY * (headWidth * 0.5);
    const ny = dirX * (headWidth * 0.5);

    if (shape === 'triangle') {
      this._appendTriangle(vertices, tip, 
        { x: base.x + nx, y: base.y + ny, z: 0 },
        { x: base.x - nx, y: base.y - ny, z: 0 },
        color
      );
    } else if (shape === 'kite') {
      const mid = { x: base.x + dirX * headWidth * 0.5, y: base.y + dirY * headWidth * 0.5, z: 0 };
      this._appendTriangle(vertices, tip, { x: base.x + nx, y: base.y + ny, z: 0 }, mid, color);
      this._appendTriangle(vertices, tip, mid, { x: base.x - nx, y: base.y - ny, z: 0 }, color);
    } else if (shape === 'circle') {
      const radius = headWidth * 0.5;
      this._appendCircle(vertices, base, radius, color);
    } else if (shape === 'curved_triangle') {
      // Approximate curved triangle with multiple smaller triangles
      const steps = 8;
      for (let i = 0; i < steps; i++) {
        const t1 = i / steps;
        const t2 = (i + 1) / steps;
        // quadratic bezier from base to tip, pulling inward
        const w1 = headWidth * 0.5 * (1 - t1) * (1 - t1);
        const w2 = headWidth * 0.5 * (1 - t2) * (1 - t2);
        
        const p1X = base.x + dirX * t1 * (tip.x - base.x);
        const p1Y = base.y + dirY * t1 * (tip.y - base.y);
        const p2X = base.x + dirX * t2 * (tip.x - base.x);
        const p2Y = base.y + dirY * t2 * (tip.y - base.y);

        this._appendTriangle(vertices, 
          { x: p1X + nx * w1 * 2 / headWidth, y: p1Y + ny * w1 * 2 / headWidth, z: 0 },
          { x: p2X + nx * w2 * 2 / headWidth, y: p2Y + ny * w2 * 2 / headWidth, z: 0 },
          { x: p1X - nx * w1 * 2 / headWidth, y: p1Y - ny * w1 * 2 / headWidth, z: 0 },
          color
        );
        this._appendTriangle(vertices, 
          { x: p1X - nx * w1 * 2 / headWidth, y: p1Y - ny * w1 * 2 / headWidth, z: 0 },
          { x: p2X + nx * w2 * 2 / headWidth, y: p2Y + ny * w2 * 2 / headWidth, z: 0 },
          { x: p2X - nx * w2 * 2 / headWidth, y: p2Y - ny * w2 * 2 / headWidth, z: 0 },
          color
        );
      }
    }
  }

  /**
   * Appends three vertices forming a triangle.
   * @private
   */
  _appendTriangle(vertices, a, b, c, color) {
    this._appendVertex(vertices, a, color);
    this._appendVertex(vertices, b, color);
    this._appendVertex(vertices, c, color);
  }

  /**
   * Appends a single vertex (projected to clip space).
   * @private
   */
  _appendVertex(vertices, point, color) {
    const clip = this._project(point);
    vertices.push(clip.x, clip.y, color.r, color.g, color.b, color.a);
  }

  /**
   * Projects a world-space point to clip space using the camera.
   * @private
   */
  _project(point) {
    return {
      x: (point.x - this.cameraCenter.x) / (this._cameraWidth * 0.5),
      y: (point.y - this.cameraCenter.y) / (this._cameraHeight * 0.5),
    };
  }
}
