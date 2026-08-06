import { multiply, perspective, translation } from "./math";
import type { RenderData, Vec4Color } from "./types";

type StatusCallback = (message: string | null) => void;

interface Programs {
  scene: WebGLProgram;
  edge: WebGLProgram;
  quad: WebGLProgram;
  ribbon: WebGLProgram;
}

interface Buffers {
  square: WebGLBuffer;
  edge: WebGLBuffer;
  quad: WebGLBuffer;
  ribbon: WebGLBuffer;
}

interface RenderTarget {
  texture: WebGLTexture;
  framebuffer: WebGLFramebuffer;
  depth: WebGLRenderbuffer;
}

const SCENE_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
uniform mat4 uModel;
uniform mat4 uViewProjection;
out vec3 vNormal;
out vec3 vPosition;
void main() {
  vec4 world = uModel * vec4(aPosition, 1.0);
  vPosition = world.xyz;
  vNormal = normalize(mat3(uModel) * vec3(0.0, 0.0, 1.0));
  gl_Position = uViewProjection * world;
}`;

const SCENE_FRAGMENT = `#version 300 es
precision highp float;
in vec3 vNormal;
in vec3 vPosition;
uniform vec4 uColor;
uniform bool uLighting;
uniform float uAmbient;
uniform float uShiny;
out vec4 outColor;
void main() {
  if (!uLighting) {
    outColor = uColor;
    return;
  }
  vec3 normal = normalize(vNormal);
  vec3 lightA = normalize(vec3(0.0, 1.0, 0.5));
  vec3 lightB = normalize(vec3(0.0, -1.0, -0.5));
  float diffuse = max(dot(normal, lightA), 0.0) + max(dot(normal, lightB), 0.0);
  vec3 eye = normalize(vec3(0.0, 0.0, 10.0) - vPosition);
  float exponent = floor(uShiny * 128.0);
  float specular = pow(max(dot(reflect(-lightA, normal), eye), 0.0), max(exponent, 1.0));
  vec3 lit = uColor.rgb * (uAmbient + 0.8 * diffuse) + vec3(specular);
  outColor = vec4(lit, uColor.a);
}`;

const EDGE_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec2 aCorner;
uniform vec3 uStart;
uniform vec3 uEnd;
uniform mat4 uModel;
uniform mat4 uViewProjection;
uniform vec2 uViewport;
uniform float uWidth;
void main() {
  vec4 startClip = uViewProjection * uModel * vec4(uStart, 1.0);
  vec4 endClip = uViewProjection * uModel * vec4(uEnd, 1.0);
  vec2 startNdc = startClip.xy / startClip.w;
  vec2 endNdc = endClip.xy / endClip.w;
  vec2 direction = normalize((endNdc - startNdc) * uViewport);
  vec2 normal = vec2(-direction.y, direction.x);
  vec4 position = mix(startClip, endClip, aCorner.x);
  position.xy += normal * aCorner.y * uWidth * position.w / uViewport;
  gl_Position = position;
}`;

const EDGE_FRAGMENT = `#version 300 es
precision highp float;
uniform vec4 uColor;
out vec4 outColor;
void main() { outColor = uColor; }`;

const QUAD_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec2 aPosition;
out vec2 vUv;
void main() {
  vUv = aPosition * 0.5 + 0.5;
  gl_Position = vec4(aPosition, 0.0, 1.0);
}`;

const QUAD_FRAGMENT = `#version 300 es
precision highp float;
in vec2 vUv;
uniform sampler2D uTexture;
uniform vec4 uBackground;
uniform int uOperation;
uniform bool uSmooth;
uniform ivec2 uFadeCell;
out vec4 outColor;
void main() {
  if (uOperation == 1) {
    outColor = uBackground;
    return;
  }
  if (uOperation == 2) {
    ivec2 cell = ivec2(mod(gl_FragCoord.xy, 4.0));
    if (any(notEqual(cell, uFadeCell))) discard;
    outColor = uBackground;
    return;
  }
  if (uSmooth) {
    vec2 texel = 1.0 / vec2(textureSize(uTexture, 0));
    outColor = (
      texture(uTexture, vUv) * 4.0
      + texture(uTexture, vUv + vec2(texel.x, 0.0))
      + texture(uTexture, vUv - vec2(texel.x, 0.0))
      + texture(uTexture, vUv + vec2(0.0, texel.y))
      + texture(uTexture, vUv - vec2(0.0, texel.y))
    ) / 8.0;
    return;
  }
  outColor = texture(uTexture, vUv);
}`;

const RIBBON_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec4 aColor;
uniform mat4 uViewProjection;
out vec4 vColor;
void main() {
  vColor = aColor;
  gl_Position = uViewProjection * vec4(aPosition, 1.0);
}`;

const RIBBON_FRAGMENT = `#version 300 es
precision highp float;
in vec4 vColor;
out vec4 outColor;
void main() { outColor = vColor; }`;

const SQUARE = new Float32Array([
  0, 0, 0,
  0.2, 0, 0,
  0, 0.2, 0,
  0, 0.2, 0,
  0.2, 0, 0,
  0.2, 0.2, 0,
]);

const EDGE_CORNERS = new Float32Array([
  0, -1, 1, -1, 1, 1,
  0, -1, 1, 1, 0, 1,
]);

const QUAD = new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]);
const EDGES: readonly [readonly [number, number, number], readonly [number, number, number]][] = [
  [[0, 0, 0], [0.2, 0, 0]],
  [[0.2, 0, 0], [0.2, 0.2, 0]],
  [[0.2, 0.2, 0], [0, 0.2, 0]],
  [[0, 0.2, 0], [0, 0, 0]],
];
const FADE_SHIFTS = [0, 2, 2, 0, 1, 3, 3, 1, 0, 2, 2, 0, 1, 3, 3, 1];
const FADE_ROWS = [0, 2, 0, 2, 1, 3, 1, 3, 1, 3, 1, 3, 0, 2, 0, 2];

export class ElectropaintRenderer {
  private gl: WebGL2RenderingContext | null = null;
  private programs: Programs | null = null;
  private buffers: Buffers | null = null;
  private targets: RenderTarget[] = [];
  private readTarget = 0;
  private targetWidth = 0;
  private targetHeight = 0;
  private fadeStep = 0;
  private contextLost = false;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly onStatus: StatusCallback,
  ) {
    canvas.addEventListener("webglcontextlost", (event) => {
      event.preventDefault();
      this.contextLost = true;
      this.onStatus("The WebGL context was lost. Electropaint will restore itself when the browser recovers it.");
    });
    canvas.addEventListener("webglcontextrestored", () => {
      this.contextLost = false;
      this.initialize();
      this.onStatus(null);
    });
    this.initialize();
  }

  get available(): boolean {
    return this.gl !== null && !this.contextLost;
  }

  render(data: RenderData): void {
    const gl = this.gl;
    const programs = this.programs;
    const buffers = this.buffers;
    if (!gl || !programs || !buffers || this.contextLost) return;
    this.resize();
    this.ensureTargets();
    const writeTarget = 1 - this.readTarget;
    const write = this.targets[writeTarget];
    const previous = this.targets[this.readTarget];
    if (!write || !previous) return;

    gl.bindFramebuffer(gl.FRAMEBUFFER, write.framebuffer);
    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.BLEND);

    if (data.smear) {
      this.drawTexture(previous.texture, data.smooth);
      if (data.fade) {
        this.drawBackground(data.background, true);
        this.fadeStep = (this.fadeStep + 1) % 16;
      }
    } else {
      gl.clearColor(data.background.r, data.background.g, data.background.b, data.background.a);
      gl.clear(gl.COLOR_BUFFER_BIT);
    }

    if (data.depth) {
      gl.enable(gl.DEPTH_TEST);
      gl.depthFunc(gl.LEQUAL);
      gl.clearDepth(1);
      gl.clear(gl.DEPTH_BUFFER_BIT);
    } else {
      gl.disable(gl.DEPTH_TEST);
    }
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const viewProjection = this.viewProjection();
    if (data.ribbonMode) this.drawRibbons(data, viewProjection);
    else this.drawSquares(data, viewProjection);

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.BLEND);
    this.drawTexture(write.texture, false);
    this.readTarget = writeTarget;
  }

  private initialize(): void {
    const gl = this.canvas.getContext("webgl2", {
      alpha: true,
      antialias: true,
      depth: true,
      preserveDrawingBuffer: true,
    });
    if (!gl) {
      this.gl = null;
      this.onStatus("WebGL2 is unavailable. Electropaint requires a current Chrome, Firefox, Safari, or Edge browser with hardware acceleration enabled.");
      return;
    }
    this.gl = gl;
    try {
      this.programs = {
        scene: this.createProgram(SCENE_VERTEX, SCENE_FRAGMENT),
        edge: this.createProgram(EDGE_VERTEX, EDGE_FRAGMENT),
        quad: this.createProgram(QUAD_VERTEX, QUAD_FRAGMENT),
        ribbon: this.createProgram(RIBBON_VERTEX, RIBBON_FRAGMENT),
      };
      this.buffers = {
        square: this.createBuffer(SQUARE),
        edge: this.createBuffer(EDGE_CORNERS),
        quad: this.createBuffer(QUAD),
        ribbon: this.createBuffer(new Float32Array(0), gl.DYNAMIC_DRAW),
      };
      this.targets = [];
      this.targetWidth = 0;
      this.targetHeight = 0;
      this.readTarget = 0;
      this.fadeStep = 0;
    } catch (error) {
      this.gl = null;
      this.onStatus(`WebGL2 initialization failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private resize(): void {
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.max(1, Math.round(this.canvas.clientWidth * ratio));
    const height = Math.max(1, Math.round(this.canvas.clientHeight * ratio));
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
  }

  private ensureTargets(): void {
    const gl = this.gl;
    if (!gl || (this.targetWidth === this.canvas.width && this.targetHeight === this.canvas.height)) return;
    for (const target of this.targets) {
      gl.deleteFramebuffer(target.framebuffer);
      gl.deleteTexture(target.texture);
      gl.deleteRenderbuffer(target.depth);
    }
    this.targets = [this.createTarget(), this.createTarget()];
    this.targetWidth = this.canvas.width;
    this.targetHeight = this.canvas.height;
    this.readTarget = 0;
    for (const target of this.targets) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      gl.clearColor(0, 0, 0, 1);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }

  private createTarget(): RenderTarget {
    const gl = this.requireGl();
    const texture = gl.createTexture();
    const framebuffer = gl.createFramebuffer();
    const depth = gl.createRenderbuffer();
    if (!texture || !framebuffer || !depth) throw new Error("Could not allocate a frame buffer");
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(
      gl.TEXTURE_2D, 0, gl.RGBA8, this.canvas.width, this.canvas.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null,
    );
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    gl.bindRenderbuffer(gl.RENDERBUFFER, depth);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, this.canvas.width, this.canvas.height);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
      throw new Error("The browser rejected the Electropaint frame buffer");
    }
    return { texture, framebuffer, depth };
  }

  private drawSquares(data: RenderData, viewProjection: number[]): void {
    const gl = this.requireGl();
    const programs = this.requirePrograms();
    const buffers = this.requireBuffers();
    gl.useProgram(programs.scene);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.square);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
    this.uniformMatrix(programs.scene, "uViewProjection", viewProjection);
    gl.uniform1i(gl.getUniformLocation(programs.scene, "uLighting"), data.lighting ? 1 : 0);
    for (const square of data.squares) {
      this.uniformMatrix(programs.scene, "uModel", square.model);
      gl.uniform1f(gl.getUniformLocation(programs.scene, "uAmbient"), square.ambient);
      gl.uniform1f(gl.getUniformLocation(programs.scene, "uShiny"), square.shiny);
      if (square.fill) {
        this.uniformColor(programs.scene, "uColor", square.fillColor);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
      }
      if (square.outline) {
        this.drawEdges(
          square.model,
          viewProjection,
          square.outlineColor,
          square.fatLine ? 3 : 1,
        );
        gl.useProgram(programs.scene);
        gl.bindBuffer(gl.ARRAY_BUFFER, buffers.square);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      }
    }
  }

  private drawEdges(
    model: number[],
    viewProjection: number[],
    color: Vec4Color,
    width: number,
  ): void {
    const gl = this.requireGl();
    const program = this.requirePrograms().edge;
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.requireBuffers().edge);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    this.uniformMatrix(program, "uModel", model);
    this.uniformMatrix(program, "uViewProjection", viewProjection);
    this.uniformColor(program, "uColor", color);
    gl.uniform2f(gl.getUniformLocation(program, "uViewport"), this.canvas.width, this.canvas.height);
    gl.uniform1f(gl.getUniformLocation(program, "uWidth"), width);
    for (const [start, end] of EDGES) {
      gl.uniform3fv(gl.getUniformLocation(program, "uStart"), start);
      gl.uniform3fv(gl.getUniformLocation(program, "uEnd"), end);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }
  }

  private drawRibbons(data: RenderData, viewProjection: number[]): void {
    const gl = this.requireGl();
    const program = this.requirePrograms().ribbon;
    const buffer = this.requireBuffers().ribbon;
    gl.useProgram(program);
    this.uniformMatrix(program, "uViewProjection", viewProjection);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.enableVertexAttribArray(0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 7 * 4, 0);
    gl.vertexAttribPointer(1, 4, gl.FLOAT, false, 7 * 4, 3 * 4);
    for (const ribbon of data.ribbons) {
      const packed = new Float32Array(ribbon.length * 7);
      ribbon.forEach((vertex, index) => {
        packed.set([
          ...vertex.position,
          vertex.color.r,
          vertex.color.g,
          vertex.color.b,
          vertex.color.a,
        ], index * 7);
      });
      gl.bufferData(gl.ARRAY_BUFFER, packed, gl.DYNAMIC_DRAW);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, ribbon.length);
    }
  }

  private drawTexture(texture: WebGLTexture, smooth: boolean): void {
    const gl = this.requireGl();
    const program = this.requirePrograms().quad;
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.requireBuffers().quad);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.uniform1i(gl.getUniformLocation(program, "uTexture"), 0);
    gl.uniform1i(gl.getUniformLocation(program, "uOperation"), 0);
    gl.uniform1i(gl.getUniformLocation(program, "uSmooth"), smooth ? 1 : 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }

  private drawBackground(color: Vec4Color, stippled: boolean): void {
    const gl = this.requireGl();
    const program = this.requirePrograms().quad;
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.requireBuffers().quad);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    this.uniformColor(program, "uBackground", color);
    gl.uniform1i(gl.getUniformLocation(program, "uOperation"), stippled ? 2 : 1);
    gl.uniform2i(
      gl.getUniformLocation(program, "uFadeCell"),
      FADE_SHIFTS[this.fadeStep] ?? 0,
      FADE_ROWS[this.fadeStep] ?? 0,
    );
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }

  private viewProjection(): number[] {
    const aspect = this.canvas.width / Math.max(1, this.canvas.height);
    return multiply(perspective(30, aspect, 0.01, 10000), translation(0, 0, -10));
  }

  private createProgram(vertexSource: string, fragmentSource: string): WebGLProgram {
    const gl = this.requireGl();
    const vertex = this.compileShader(gl.VERTEX_SHADER, vertexSource);
    const fragment = this.compileShader(gl.FRAGMENT_SHADER, fragmentSource);
    const program = gl.createProgram();
    if (!program) throw new Error("Could not allocate a shader program");
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    gl.deleteShader(vertex);
    gl.deleteShader(fragment);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(program) ?? "Shader link failed");
    }
    return program;
  }

  private compileShader(type: number, source: string): WebGLShader {
    const gl = this.requireGl();
    const shader = gl.createShader(type);
    if (!shader) throw new Error("Could not allocate a shader");
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader) ?? "Shader compilation failed");
    }
    return shader;
  }

  private createBuffer(data: Float32Array, usage?: number): WebGLBuffer {
    const gl = this.requireGl();
    const buffer = gl.createBuffer();
    if (!buffer) throw new Error("Could not allocate a vertex buffer");
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, data, usage ?? gl.STATIC_DRAW);
    return buffer;
  }

  private uniformMatrix(program: WebGLProgram, name: string, value: number[]): void {
    this.requireGl().uniformMatrix4fv(
      this.requireGl().getUniformLocation(program, name),
      false,
      new Float32Array(value),
    );
  }

  private uniformColor(program: WebGLProgram, name: string, color: Vec4Color): void {
    this.requireGl().uniform4f(
      this.requireGl().getUniformLocation(program, name),
      color.r,
      color.g,
      color.b,
      color.a,
    );
  }

  private requireGl(): WebGL2RenderingContext {
    if (!this.gl) throw new Error("WebGL2 is unavailable");
    return this.gl;
  }

  private requirePrograms(): Programs {
    if (!this.programs) throw new Error("Shader programs are unavailable");
    return this.programs;
  }

  private requireBuffers(): Buffers {
    if (!this.buffers) throw new Error("Vertex buffers are unavailable");
    return this.buffers;
  }
}
