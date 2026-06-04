/**
 * WebGPU Renderer for PhysicsProblems
 * Renders scene primitives (circles, lines, arrows) using WebGPU.
 * Called from Swift WASM via JavaScriptKit interop.
 */

// MARK: - WGSL Shaders

const SHADER_SOURCE = `
struct VertexInput {
  @location(0) position: vec2f,
  @location(1) world_pos: vec2f,
  @location(2) pA: vec2f,
  @location(3) pB: vec2f,
  @location(4) width: f32,
  @location(5) color: vec4f,
  @location(6) params: vec2f, // x = type, y = rotation
}

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
  @location(1) world_pos: vec2f,
  @location(2) pA: vec2f,
  @location(3) pB: vec2f,
  @location(4) width: f32,
  @location(5) params: vec2f,
}

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
  var output: VertexOutput;
  output.position = vec4f(input.position, 0.0, 1.0);
  output.color = input.color;
  output.world_pos = input.world_pos;
  output.pA = input.pA;
  output.pB = input.pB;
  output.width = input.width;
  output.params = input.params;
  return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4f {
  if (input.params.x == 0.0) {
    return input.color;
  }
  
  if (input.params.x == 2.0) {
    let p = input.world_pos - input.pA;
    let cosR = cos(-input.params.y);
    let sinR = sin(-input.params.y);
    let lp = vec2f(p.x * cosR - p.y * sinR, p.x * sinR + p.y * cosR);
    let ab = input.pB;
    let pAbs = abs(lp);
    
    let l = length(pAbs / max(ab, vec2f(0.0001)));
    let dist = (l - 1.0) * length(pAbs) / max(l, 0.0001);
    
    let stroke_dist = abs(dist);
    let radius = input.width * 0.5;
    let fw = fwidth(stroke_dist);
    let alpha = smoothstep(radius + fw, radius - fw, stroke_dist);
    
    if (alpha < 0.01) { discard; }
    return vec4f(input.color.rgb, input.color.a * alpha);
  }
  
  let pa = input.world_pos - input.pA;
  let ba = input.pB - input.pA;
  let ba2 = dot(ba, ba);
  let h = clamp(dot(pa, ba) / max(ba2, 0.0000001), 0.0, 1.0);
  let dist = length(pa - ba * h);
  
  let radius = input.width * 0.5;
  let fw = fwidth(dist);
  let alpha = smoothstep(radius + fw, radius - fw, dist);
  
  if (alpha < 0.01) {
    discard;
  }
  
  return vec4f(input.color.rgb, input.color.a * alpha);
}
`;

const MESH_SHADER_SOURCE = `
struct VertexInput {
  @location(0) position: vec3f,
  @location(1) normal: vec3f,
  @location(2) color: vec4f,
}

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) normal: vec3f,
  @location(1) color: vec4f,
}

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
  var output: VertexOutput;
  // Position is assumed to be pre-projected or handled via uniforms in the future
  // For now, we just pass z and w=1
  output.position = vec4f(input.position.x, input.position.y, input.position.z, 1.0);
  output.normal = input.normal;
  output.color = input.color;
  return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4f {
  // Simple directional lighting
  let lightDir = normalize(vec3f(0.5, 0.8, 0.3));
  let n = normalize(input.normal);
  let diffuse = max(dot(n, lightDir), 0.0);
  let ambient = 0.3;
  let finalColor = input.color.rgb * (ambient + diffuse * 0.7);
  return vec4f(finalColor, input.color.a);
}
`;

// MARK: - Constants

const FLOATS_PER_VERTEX = 15; // x, y, wpX, wpY, pAx, pAy, pBx, pBy, w, r, g, b, a, type, rot
const BYTES_PER_VERTEX = FLOATS_PER_VERTEX * 4; // 60 bytes
const CIRCLE_SEGMENTS = 128;
const CLEAR_COLOR = { r: 0.08, g: 0.09, b: 0.11, a: 1.0 };

class VertexArray {
  constructor(initialCapacity = 16384) {
    this.capacity = initialCapacity;
    this.buffer = new Float32Array(this.capacity * FLOATS_PER_VERTEX);
    this.count = 0;
  }

  ensure(additionalVertices) {
    if (this.count + additionalVertices > this.capacity) {
      let newCapacity = this.capacity;
      while (this.count + additionalVertices > newCapacity) newCapacity *= 2;
      const newBuffer = new Float32Array(newCapacity * FLOATS_PER_VERTEX);
      newBuffer.set(this.buffer.subarray(0, this.count * FLOATS_PER_VERTEX));
      this.buffer = newBuffer;
      this.capacity = newCapacity;
    }
  }

  push(x, y, wpX, wpY, ax, ay, bx, by, w, r, g, b, a, type, rot) {
    this.ensure(1);
    let i = this.count * FLOATS_PER_VERTEX;
    const b_ = this.buffer;
    b_[i++] = x; b_[i++] = y;
    b_[i++] = wpX; b_[i++] = wpY;
    b_[i++] = ax; b_[i++] = ay;
    b_[i++] = bx; b_[i++] = by;
    b_[i++] = w;
    b_[i++] = r; b_[i++] = g; b_[i++] = b; b_[i++] = a;
    b_[i++] = type; b_[i++] = rot;
    this.count++;
  }
  
  clear() {
    this.count = 0;
  }
}

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
            { shaderLocation: 1, offset: 8, format: 'float32x2' },   // world_pos
            { shaderLocation: 2, offset: 16, format: 'float32x2' },  // pA
            { shaderLocation: 3, offset: 24, format: 'float32x2' },  // pB
            { shaderLocation: 4, offset: 32, format: 'float32' },    // width
            { shaderLocation: 5, offset: 36, format: 'float32x4' },  // color
            { shaderLocation: 6, offset: 52, format: 'float32x2' },  // params
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
    this.pathVertexBuffer = null;
    this.pathVertexCapacity = 0;

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

    if (!this.meshVertices) this.meshVertices = new VertexArray();
    if (!this.pathVertices) this.pathVertices = new VertexArray();

    this.meshVertices.clear();
    this.pathVertices.clear();

    this._buildMeshVertices(primitives, this.meshVertices);
    this._buildPathVertices(primitives, this.pathVertices);
    if (this.meshVertices.count === 0 && this.pathVertices.count === 0) return;

    const meshBuffer = this._uploadVertices(this.meshVertices, 'mesh');
    const pathBuffer = this._uploadVertices(this.pathVertices, 'path');

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
    this._drawUploadedVertices(pass, meshBuffer, this.meshVertices);
    this._drawUploadedVertices(pass, pathBuffer, this.pathVertices);
    pass.end();

    this.queue.submit([encoder.finish()]);
  }

  setCamera(camera) {
    this.camera = camera;
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

    if (this.camera) {
      let ndcX = (normalizedX * 2 - 1);
      let ndcY = (1 - normalizedY * 2);
      
      let fovRad = (this.camera.fov * Math.PI) / 180.0;
      let f = 1.0 / Math.tan(fovRad / 2.0);
      
      let viewX = ndcX * this._aspectRatio / f;
      let viewY = ndcY / f;
      let viewZ = -1.0;

      let cx = this.camera.orientation.x;
      let cy = this.camera.orientation.y;
      let cz = this.camera.orientation.z;
      let cw = this.camera.orientation.w;

      let tx = 2 * (cy * viewZ - cz * viewY);
      let ty = 2 * (cz * viewX - cx * viewZ);
      let tz = 2 * (cx * viewY - cy * viewX);

      let rayX = viewX + cw * tx + cy * tz - cz * ty;
      let rayY = viewY + cw * ty + cz * tx - cx * tz;
      let rayZ = viewZ + cw * tz + cx * ty - cy * tx;

      if (Math.abs(rayZ) < 0.0001) {
        return { x: this.camera.position.x, y: this.camera.position.y, z: 0 };
      }
      let t = -this.camera.position.z / rayZ;
      return {
        x: this.camera.position.x + rayX * t,
        y: this.camera.position.y + rayY * t,
        z: 0
      };
    }

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
   * @param {VertexArray} vertexArray
   * @private
   */
  _uploadVertices(vertexArray, kind = 'mesh') {
    if (vertexArray.count === 0) return null;
    const floatCount = vertexArray.count * FLOATS_PER_VERTEX;
    const buffer = this._ensureVertexBuffer(floatCount, kind);
    if (!buffer) return null;

    this.queue.writeBuffer(buffer, 0, vertexArray.buffer.subarray(0, floatCount));
    return buffer;
  }

  _drawUploadedVertices(pass, buffer, vertexArray) {
    if (!buffer || vertexArray.count === 0) return;
    pass.setVertexBuffer(0, buffer);
    pass.draw(vertexArray.count);
  }

  _ensureVertexBuffer(floatCount, kind = 'mesh') {
    const bufferKey = kind === 'path' ? 'pathVertexBuffer' : 'vertexBuffer';
    const capacityKey = kind === 'path' ? 'pathVertexCapacity' : 'vertexCapacity';

    if (floatCount <= this[capacityKey]) return this[bufferKey];

    let capacity = Math.max(1024, this[capacityKey]);
    while (capacity < floatCount) {
      capacity *= 2;
    }
    this[capacityKey] = capacity;

    this[bufferKey] = this.device.createBuffer({
      size: capacity * 4, // 4 bytes per float
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });
    return this[bufferKey];
  }

  /**
   * Builds the flat vertex array from primitives.
   * @param {Array} primitives
   * @param {VertexArray} vertices
   * @private
   */
  _buildMeshVertices(primitives, vertices) {
    const screenMax = Math.max(this._cameraWidth, this._cameraHeight);

    for (const prim of primitives) {
      if (prim.type === 'path') continue;
      const strokeWidth = prim.strokeWidth !== undefined ? (Math.min(10, Math.max(0, prim.strokeWidth)) / 100.0) * screenMax : 0;

      switch (prim.type) {
        case 'circle':
          if (prim.strokeColor && prim.strokeColor.a > 0 && strokeWidth > 0) {
            this._appendStrokeEllipse(vertices, prim.center, prim.radius, prim.radius, 0, strokeWidth, prim.strokeColor, prim.strokeStyle);
          }
          if (prim.color && prim.color.a > 0) {
            this._appendCircle(vertices, prim.center, Math.max(0, prim.radius), prim.color);
          }
          break;
        case 'ellipse':
          if (prim.strokeColor && prim.strokeColor.a > 0 && strokeWidth > 0) {
            this._appendStrokeEllipse(vertices, prim.center, prim.major, prim.minor, prim.rotation, strokeWidth, prim.strokeColor, prim.strokeStyle);
          }
          if (prim.color && prim.color.a > 0) {
            this._appendEllipse(vertices, prim.center, Math.max(0, prim.major), Math.max(0, prim.minor), prim.rotation, prim.color);
          }
          break;
        case 'line':
          if (prim.strokeColor && prim.strokeColor.a > 0 && strokeWidth > 0) {
            this._appendStrokeLine(vertices, prim.start, prim.end, Math.max(prim.width, strokeWidth), prim.strokeColor, prim.strokeStyle);
          } else {
            this._appendLine(vertices, prim.start, prim.end, prim.width, prim.color);
          }
          break;
        case 'arrow':
          // Arrow stroke not perfectly defined, fallback to normal rendering but use strokeColor if present
          this._appendArrow(vertices, prim.start, prim.end, prim.shaftWidth, prim.headLength, prim.headWidth, prim.strokeColor || prim.color, prim.tipShape, prim.tailShape);
          break;
        case 'wall':
          this._appendWall(vertices, prim.start, prim.end, prim.spacing, prim.face, prim.strokeColor || prim.color);
          break;
        case 'rect':
          if (prim.strokeColor && prim.strokeColor.a > 0 && strokeWidth > 0) {
            // we'd need _appendStrokeRect or polyline, let's use polyline for rect stroke
            const w2 = prim.width / 2;
            const h2 = prim.height / 2;
            const cosR = Math.cos(prim.rotation || 0);
            const sinR = Math.sin(prim.rotation || 0);
            const pts = [
              { x: -w2, y: -h2, z: 0 }, { x: w2, y: -h2, z: 0 },
              { x: w2, y: h2, z: 0 }, { x: -w2, y: h2, z: 0 }
            ].map(p => ({
              x: prim.center.x + p.x * cosR - p.y * sinR,
              y: prim.center.y + p.x * sinR + p.y * cosR,
              z: prim.center.z
            }));
            this._appendPolyline(vertices, pts, strokeWidth, prim.strokeColor, true, prim.strokeStyle);
          }
          if (prim.color && prim.color.a > 0) {
            const w2 = prim.width / 2;
            const h2 = prim.height / 2;
            const cosR = Math.cos(prim.rotation || 0);
            const sinR = Math.sin(prim.rotation || 0);
            const pts = [
              { x: -w2, y: -h2, z: 0 }, { x: w2, y: -h2, z: 0 },
              { x: w2, y: h2, z: 0 }, { x: -w2, y: h2, z: 0 }
            ].map(p => ({
              x: prim.center.x + p.x * cosR - p.y * sinR,
              y: prim.center.y + p.x * sinR + p.y * cosR,
              z: prim.center.z
            }));
            this._appendPolygon(vertices, pts, prim.color);
          }
          break;
        case 'polygon':
          if (prim.strokeColor && prim.strokeColor.a > 0 && strokeWidth > 0) {
            this._appendPolyline(vertices, prim.points, strokeWidth, prim.strokeColor, true, prim.strokeStyle);
          }
          if (prim.color && prim.color.a > 0) {
            this._appendPolygon(vertices, prim.points, prim.color);
          }
          break;
        case 'arc':
          if (prim.strokeColor && prim.strokeColor.a > 0 && strokeWidth > 0) {
             // Basic arc stroke approximation using ellipse points
             const delta = prim.endAngle - prim.startAngle;
             const steps = 32;
             const pts = [];
             for (let i = 0; i <= steps; i++) {
                const angle = prim.startAngle + delta * (i / steps);
                pts.push({
                   x: prim.center.x + Math.cos(angle) * prim.radius,
                   y: prim.center.y + Math.sin(angle) * prim.radius,
                   z: prim.center.z || 0
                });
             }
             this._appendPolyline(vertices, pts, strokeWidth, prim.strokeColor, false, prim.strokeStyle);
          }
          // Arcs are usually just strokes, but if filled, it's a pie slice
          if (prim.color && prim.color.a > 0) {
             const delta = prim.endAngle - prim.startAngle;
             const steps = 32;
             const pts = [prim.center];
             for (let i = 0; i <= steps; i++) {
                const angle = prim.startAngle + delta * (i / steps);
                pts.push({
                   x: prim.center.x + Math.cos(angle) * prim.radius,
                   y: prim.center.y + Math.sin(angle) * prim.radius,
                   z: prim.center.z || 0
                });
             }
             this._appendPolygon(vertices, pts, prim.color);
          }
          break;
      }
    }
  }

  _buildPathVertices(primitives, vertices) {
    const screenMax = Math.max(this._cameraWidth, this._cameraHeight);

    for (const prim of primitives) {
      if (prim.type !== 'path') continue;
      const strokeWidth = prim.strokeWidth !== undefined ? (Math.min(10, Math.max(0, prim.strokeWidth)) / 100.0) * screenMax : 0;
      this._appendVectorPath(vertices, prim, strokeWidth);
    }

    return vertices;
  }

  /**
   * Appends a circle as a triangle fan.
   * @private
   */

  _appendVectorPath(vertices, prim, styleStrokeWidth) {
    const contours = Array.isArray(prim.contours) ? prim.contours : [];
    const drawing = prim.drawing || 'fill';
    const fillColor = prim.color;
    const strokeColor = prim.strokeColor || prim.color;
    const pathStrokeWidth = Math.max(0, prim.pathStrokeWidth || 0.02);
    const windingMode = prim.windingMode || 'non_zero';
    const closedContours = [];

    for (const contour of contours) {
      const points = Array.isArray(contour.points) ? contour.points : [];
      if (points.length < 2) continue;

      const closed = !!contour.closed;
      if (drawing === 'stroke' || !closed) {
        if (strokeColor && strokeColor.a > 0) {
          this._appendPolyline(vertices, points, pathStrokeWidth, strokeColor, closed, prim.strokeStyle);
        }
        continue;
      }

      closedContours.push(this._cleanPolygon(points));
    }

    if (drawing === 'fill' && fillColor && fillColor.a > 0) {
      this._appendWindingPathFill(vertices, closedContours, fillColor, windingMode);
    }

    if (drawing === 'fill') {
      for (const points of closedContours) {
        if (points.length < 2) continue;
        const closed = points.length > 2;
        if (prim.strokeColor && prim.strokeColor.a > 0 && styleStrokeWidth > 0) {
          this._appendPolyline(vertices, points, styleStrokeWidth, prim.strokeColor, true, prim.strokeStyle);
        }
      }
    }
  }

  _appendWindingPathFill(vertices, closedContours, fillColor, windingMode) {
    const edges = [];
    for (const contour of closedContours) {
      for (let i = 0; i < contour.length; i++) {
        const p0 = contour[i];
        const p1 = contour[(i + 1) % contour.length];
        if (Math.abs(p0.y - p1.y) < 1e-7) continue;

        let dir = p1.y > p0.y ? 1 : -1;
        edges.push({
          y0: p0.y,
          y1: p1.y,
          dir: dir,
          m: (p1.x - p0.x) / (p1.y - p0.y),
          c: p0.x - p0.y * (p1.x - p0.x) / (p1.y - p0.y)
        });
      }
    }

    const criticalYs = new Set();
    for (const edge of edges) {
      criticalYs.add(edge.y0);
      criticalYs.add(edge.y1);
    }

    for (let i = 0; i < edges.length; i++) {
      for (let j = i + 1; j < edges.length; j++) {
        const e1 = edges[i];
        const e2 = edges[j];

        const minY1 = Math.min(e1.y0, e1.y1);
        const maxY1 = Math.max(e1.y0, e1.y1);
        const minY2 = Math.min(e2.y0, e2.y1);
        const maxY2 = Math.max(e2.y0, e2.y1);

        if (maxY1 <= minY2 || maxY2 <= minY1) continue;
        if (Math.abs(e1.m - e2.m) < 1e-7) continue;

        const yInt = (e2.c - e1.c) / (e1.m - e2.m);

        if (yInt > minY1 + 1e-7 && yInt < maxY1 - 1e-7 &&
            yInt > minY2 + 1e-7 && yInt < maxY2 - 1e-7) {
          criticalYs.add(yInt);
        }
      }
    }

    const sortedYs = Array.from(criticalYs).sort((a, b) => a - b);
    const uniqueYs = [];
    for (const y of sortedYs) {
      if (uniqueYs.length === 0 || y - uniqueYs[uniqueYs.length - 1] > 1e-6) {
        uniqueYs.push(y);
      }
    }

    for (let i = 0; i < uniqueYs.length - 1; i++) {
      const yTop = uniqueYs[i];
      const yBottom = uniqueYs[i + 1];
      const yMid = (yTop + yBottom) / 2;

      const activeEdges = [];
      for (const edge of edges) {
        const minY = Math.min(edge.y0, edge.y1);
        const maxY = Math.max(edge.y0, edge.y1);
        if (minY <= yMid && maxY >= yMid) {
          activeEdges.push(edge);
        }
      }

      if (activeEdges.length === 0) continue;

      for (const edge of activeEdges) {
        edge.xMid = edge.m * yMid + edge.c;
      }

      activeEdges.sort((a, b) => a.xMid - b.xMid);

      let winding = 0;
      let inside = false;
      let leftEdge = null;

      for (let j = 0; j < activeEdges.length; j++) {
        const edge = activeEdges[j];
        winding += edge.dir;

        let isInside = false;
        if (windingMode === 'even_odd') {
          isInside = (winding % 2) !== 0;
        } else {
          isInside = winding !== 0;
        }

        const nextEdge = activeEdges[j + 1];
        if (nextEdge && Math.abs(nextEdge.xMid - edge.xMid) < 1e-7) {
          continue;
        }

        if (isInside && !inside) {
          inside = true;
          leftEdge = edge;
        } else if (!isInside && inside) {
          inside = false;
          const rightEdge = edge;

          const tlX = leftEdge.m * yTop + leftEdge.c;
          const blX = leftEdge.m * yBottom + leftEdge.c;
          const trX = rightEdge.m * yTop + rightEdge.c;
          const brX = rightEdge.m * yBottom + rightEdge.c;

          this._appendTriangle(vertices,
            { x: tlX, y: yTop, z: 0 },
            { x: trX, y: yTop, z: 0 },
            { x: brX, y: yBottom, z: 0 },
            fillColor
          );
          this._appendTriangle(vertices,
            { x: tlX, y: yTop, z: 0 },
            { x: brX, y: yBottom, z: 0 },
            { x: blX, y: yBottom, z: 0 },
            fillColor
          );
        }
      }
    }
  }

  _appendPolyline(vertices, points, width, color, closed = false, style = 'solid') {
    if (points.length < 2) return;
    for (let i = 0; i < points.length - 1; i++) {
      this._appendStrokeLine(vertices, points[i], points[i + 1], width, color, style);
    }
    if (closed && points.length > 2) {
      this._appendStrokeLine(vertices, points[points.length - 1], points[0], width, color, style);
    }
  }

  _appendPolygon(vertices, points, color) {
    const polygon = this._cleanPolygon(points);
    if (polygon.length < 3) return;

    const triangles = this._triangulatePolygon(polygon);
    if (triangles.length === 0) {
      for (let i = 1; i < polygon.length - 1; i++) {
        this._appendTriangle(vertices, polygon[0], polygon[i], polygon[i + 1], color);
      }
      return;
    }

    for (const triangle of triangles) {
      this._appendTriangle(vertices, triangle[0], triangle[1], triangle[2], color);
    }
  }

  _cleanPolygon(points) {
    const cleaned = [];
    for (const point of points) {
      const previous = cleaned[cleaned.length - 1];
      if (!previous || Math.hypot(point.x - previous.x, point.y - previous.y) > 0.000001) {
        cleaned.push(point);
      }
    }
    if (cleaned.length > 1) {
      const first = cleaned[0];
      const last = cleaned[cleaned.length - 1];
      if (Math.hypot(first.x - last.x, first.y - last.y) <= 0.000001) {
        cleaned.pop();
      }
    }
    return cleaned;
  }

  _triangulatePolygon(points) {
    const triangles = [];
    const indices = points.map((_, i) => i);
    const clockwise = this._polygonArea(points) < 0;
    let guard = 0;

    while (indices.length > 3 && guard < points.length * points.length) {
      let earFound = false;
      for (let i = 0; i < indices.length; i++) {
        const prevIndex = indices[(i - 1 + indices.length) % indices.length];
        const currentIndex = indices[i];
        const nextIndex = indices[(i + 1) % indices.length];
        const a = points[prevIndex];
        const b = points[currentIndex];
        const c = points[nextIndex];

        if (!this._isConvex(a, b, c, clockwise)) continue;
        if (this._triangleContainsAnyPoint(points, indices, prevIndex, currentIndex, nextIndex)) continue;

        triangles.push(clockwise ? [a, c, b] : [a, b, c]);
        indices.splice(i, 1);
        earFound = true;
        break;
      }

      if (!earFound) break;
      guard++;
    }

    if (indices.length === 3) {
      const a = points[indices[0]];
      const b = points[indices[1]];
      const c = points[indices[2]];
      triangles.push(clockwise ? [a, c, b] : [a, b, c]);
    }
    return triangles;
  }

  _polygonArea(points) {
    let area = 0;
    for (let i = 0; i < points.length; i++) {
      const a = points[i];
      const b = points[(i + 1) % points.length];
      area += a.x * b.y - b.x * a.y;
    }
    return area * 0.5;
  }

  _isConvex(a, b, c, clockwise) {
    const cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    return clockwise ? cross < -0.000001 : cross > 0.000001;
  }

  _triangleContainsAnyPoint(points, indices, ai, bi, ci) {
    const a = points[ai];
    const b = points[bi];
    const c = points[ci];
    for (const index of indices) {
      if (index === ai || index === bi || index === ci) continue;
      if (this._pointInTriangle(points[index], a, b, c)) return true;
    }
    return false;
  }

  _pointInTriangle(p, a, b, c) {
    const area = (u, v, w) => (v.x - u.x) * (w.y - u.y) - (v.y - u.y) * (w.x - u.x);
    const ab = area(a, b, p);
    const bc = area(b, c, p);
    const ca = area(c, a, p);
    const hasNegative = ab < -0.000001 || bc < -0.000001 || ca < -0.000001;
    const hasPositive = ab > 0.000001 || bc > 0.000001 || ca > 0.000001;
    return !(hasNegative && hasPositive);
  }

  _appendStrokeEllipse(vertices, center, major, minor, rotation, width, color, style = 'solid') {
    if (style === 'solid') {
      const expand = Math.max(major, minor) + width * 0.5 + Math.max(0.02, width * 0.2);
      const s0 = { x: center.x - expand, y: center.y - expand, z: 0 };
      const s1 = { x: center.x + expand, y: center.y - expand, z: 0 };
      const s2 = { x: center.x + expand, y: center.y + expand, z: 0 };
      const s3 = { x: center.x - expand, y: center.y + expand, z: 0 };

      const pB = { x: major, y: minor, z: 0 };
      this._appendTriangleEllipse(vertices, s0, s1, s2, color, center, pB, width, rotation);
      this._appendTriangleEllipse(vertices, s0, s2, s3, color, center, pB, width, rotation);
      return;
    }

    const cosR = Math.cos(rotation);
    const sinR = Math.sin(rotation);

    let dashLength = 0.1;
    if (style === 'dashed') dashLength = 0.15;
    else if (style === 'dotted') dashLength = 0.05;

    // Approximate circumference
    const h = Math.pow(major - minor, 2) / Math.pow(major + minor, 2);
    const circumference = Math.PI * (major + minor) * (1 + (3 * h) / (10 + Math.sqrt(4 - 3 * h)));
    const segments = style === 'solid' ? 128 : Math.max(128, Math.floor(circumference / (dashLength * 0.5)));

    let currentDist = 0;

    for (let i = 0; i < segments; i++) {
      const a0 = (i / segments) * Math.PI * 2;
      const a1 = ((i + 1) / segments) * Math.PI * 2;
      
      const x0 = major * Math.cos(a0);
      const y0 = minor * Math.sin(a0);
      const x1 = major * Math.cos(a1);
      const y1 = minor * Math.sin(a1);

      const dx = x1 - x0;
      const dy = y1 - y0;
      const arcLen = Math.sqrt(dx*dx + dy*dy);

      if (style !== 'solid') {
        if (Math.floor(currentDist / dashLength) % 2 === 1) {
           currentDist += arcLen;
           continue;
        }
      }
      currentDist += arcLen;

      // rotate
      const rx0 = x0 * cosR - y0 * sinR;
      const ry0 = x0 * sinR + y0 * cosR;
      const rx1 = x1 * cosR - y1 * sinR;
      const ry1 = x1 * sinR + y1 * cosR;

      const p0 = { x: center.x + rx0, y: center.y + ry0, z: 0 };
      const p1 = { x: center.x + rx1, y: center.y + ry1, z: 0 };

      this._appendLine(vertices, p0, p1, width, color);
    }
  }

  _appendStrokeLine(vertices, start, end, width, color, style = 'solid') {
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len < 0.0001) return;

    if (style === 'solid') {
      this._appendLine(vertices, start, end, width, color);
      return;
    }

    let dashLength = 0.1;
    if (style === 'dashed') dashLength = 0.15;
    else if (style === 'dotted') dashLength = 0.05;

    const dirX = dx / len;
    const dirY = dy / len;

    let currentDist = 0;
    while (currentDist < len) {
      const nextDist = Math.min(len, currentDist + dashLength);
      const p1 = { x: start.x + dirX * currentDist, y: start.y + dirY * currentDist, z: 0 };
      const p2 = { x: start.x + dirX * nextDist, y: start.y + dirY * nextDist, z: 0 };
      this._appendLine(vertices, p1, p2, width, color);
      currentDist += dashLength * 2;
    }
  }

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
   * Appends a thick line as two triangles (quad) using SDF padding.
   * @private
   */
  _appendLine(vertices, start, end, width, color) {
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len < 0.0001) return;

    const expand = (width * 0.5) + Math.max(0.02, width * 0.2);

    const nx = (-dy / len) * expand;
    const ny = (dx / len) * expand;

    const px = (dx / len) * expand;
    const py = (dy / len) * expand;

    const s0 = { x: start.x + nx - px, y: start.y + ny - py, z: 0 };
    const s1 = { x: start.x - nx - px, y: start.y - ny - py, z: 0 };
    const e0 = { x: end.x + nx + px, y: end.y + ny + py, z: 0 };
    const e1 = { x: end.x - nx + px, y: end.y - ny + py, z: 0 };

    this._appendTriangleSDF(vertices, s0, s1, e0, color, start, end, width);
    this._appendTriangleSDF(vertices, e0, s1, e1, color, start, end, width);
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

  _appendTriangleEllipse(vertices, a, b, c, color, center, ab, width, rotation) {
    this._appendVertex(vertices, a, color, a, center, ab, width, 2.0, rotation);
    this._appendVertex(vertices, b, color, b, center, ab, width, 2.0, rotation);
    this._appendVertex(vertices, c, color, c, center, ab, width, 2.0, rotation);
  }

  _appendTriangleSDF(vertices, a, b, c, color, pA, pB, width) {
    this._appendVertex(vertices, a, color, a, pA, pB, width, 1.0, 0.0);
    this._appendVertex(vertices, b, color, b, pA, pB, width, 1.0, 0.0);
    this._appendVertex(vertices, c, color, c, pA, pB, width, 1.0, 0.0);
  }

  /**
   * Appends a single vertex (projected to clip space).
   * @private
   */
  _appendVertex(vertices, point, color, worldPos = null, pA = null, pB = null, width = 0, type = 0.0, rotation = 0.0) {
    const clip = this._project(point);
    const wp = worldPos || point;
    const a = pA || point;
    const b = pB || point;
    vertices.push(clip.x, clip.y, wp.x, wp.y, a.x, a.y, b.x, b.y, width, color.r, color.g, color.b, color.a, type, rotation);
  }

  /**
   * Projects a world-space point to clip space using the camera.
   * @private
   */
  _project(point) {
    let px = point.x;
    let py = point.y;
    let pz = point.z || 0;

    if (this.camera) {
      let dx = px - this.camera.position.x;
      let dy = py - this.camera.position.y;
      let dz = pz - this.camera.position.z;

      let cx = -this.camera.orientation.x;
      let cy = -this.camera.orientation.y;
      let cz = -this.camera.orientation.z;
      let cw = this.camera.orientation.w;

      let tx = 2 * (cy * dz - cz * dy);
      let ty = 2 * (cz * dx - cx * dz);
      let tz = 2 * (cx * dy - cy * dx);

      px = dx + cw * tx + cy * tz - cz * ty;
      py = dy + cw * ty + cz * tx - cx * tz;
      pz = dz + cw * tz + cx * ty - cy * tx;

      let fovRad = (this.camera.fov * Math.PI) / 180.0;
      let f = 1.0 / Math.tan(fovRad / 2.0);
      let zDist = -pz;
      if (zDist < 0.001) zDist = 0.001;

      return {
        x: (px * f / this._aspectRatio) / zDist,
        y: (py * f) / zDist
      };
    }

    return {
      x: (px - this.cameraCenter.x) / (this._cameraWidth * 0.5),
      y: (py - this.cameraCenter.y) / (this._cameraHeight * 0.5),
    };
  }
}
