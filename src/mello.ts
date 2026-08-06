import {
  hlsToRgb,
  multiply,
  rotationX,
  rotationY,
  rotationZ,
  scaling,
  translation,
  wrap,
  type Mat4,
} from "./math";
import type {
  CompatibilityPolicy,
  ElectropaintMode,
  ReconstructionProfile,
  RenderData,
  RenderSquare,
} from "./types";

// Reconstructs the decompiled 1994 OpenGL screensaver and its "mello" script:
// https://github.com/sgi-demos/sgi-demos/tree/main/demos/ep-1994-ogl-decomp
export const MELLO_PROFILE = "ep-1994-ogl-decomp" as const satisfies ReconstructionProfile;
export const MELLO_HISTORY_LENGTH = 128;
export const MELLO_VISIBLE_COUNT = 40;

type ActuatorId = "arm" | "flip" | "hue" | "light" | "outline" | "spin" | "twist" | "wheel" | "wrist";

interface Actuator {
  value: number;
  low: number;
  high: number;
  duration: number;
  target: number;
  step: number;
  direction: 1 | -1;
  moving: boolean;
}

interface MelloSample {
  zoom: number;
  arm: number;
  wrist: number;
  twist: number;
  flip: number;
  spin: number;
  outline: boolean;
  hue: number;
  lightness: number;
}

interface PhaseSequence {
  phase: "slow" | "fast";
  transitionFrame: number;
}

export interface MelloStateSnapshot {
  kind: typeof MELLO_PROFILE;
  randomState: string;
  frame: number;
  point: number;
  wheel: number;
  globalSpin: number;
  globalFlip: number;
  shippedLook: boolean;
  actuators: Record<ActuatorId, Actuator>;
  history: MelloSample[];
}

const blankSample = (): MelloSample => ({
  zoom: 0,
  arm: 0,
  wrist: 0,
  twist: 0,
  flip: 0,
  spin: 0,
  outline: false,
  hue: 0,
  lightness: 0,
});

const blankActuator = (): Actuator => ({
  value: 0,
  low: 0,
  high: 0,
  duration: 1,
  target: 0,
  step: 0,
  direction: 1,
  moving: false,
});

class Drand48 {
  private static readonly MASK = (1n << 48n) - 1n;
  private state = 0x330en;

  next(): number {
    this.state = (0x5deece66dn * this.state + 0xbn) & Drand48.MASK;
    return Number(this.state) / 281474976710656;
  }

  capture(): string {
    return this.state.toString(16).padStart(12, "0");
  }
}

export class MelloReconstruction {
  private readonly random = new Drand48();
  private readonly actuators = Object.fromEntries(
    // Actuator-table order matters because each target consumes drand48 values.
    (["outline", "twist", "wheel", "spin", "flip", "arm", "wrist", "hue", "light"] as const)
      .map((id) => [id, blankActuator()]),
  ) as Record<ActuatorId, Actuator>;
  private history = Array.from({ length: MELLO_HISTORY_LENGTH }, blankSample);
  private frame = 0;
  private point = 0;
  private wheel = 0;
  private globalSpin = 0;
  private globalFlip = 0;
  private initialized = false;
  private spinSequence: PhaseSequence = { phase: "slow", transitionFrame: Number.POSITIVE_INFINITY };
  private flipSequence: PhaseSequence = { phase: "slow", transitionFrame: Number.POSITIVE_INFINITY };
  shippedLook = true;

  step(): void {
    this.frame += 1;
    this.point = (this.point + 1) & (MELLO_HISTORY_LENGTH - 1);

    // Sequence zero starts the eight script sequences on its first taste. The
    // newly started sequences become eligible on the following display frame.
    if (this.frame === 2) this.initializeScript();
    if (this.initialized) {
      this.advancePhaseSequences();
      this.setTargets();
      this.animateActuators();
    }

    const sample = this.history[this.point] ?? blankSample();
    sample.zoom = 0.06;
    sample.arm = this.actuators.arm.value;
    sample.wrist = this.actuators.wrist.value;
    sample.twist = this.actuators.twist.value;
    sample.outline = this.actuators.outline.value > 0;
    sample.hue = wrap(this.actuators.hue.value, 0, 1);
    sample.lightness = this.actuators.light.value;
    this.globalFlip = wrap(this.globalFlip + this.actuators.flip.value, 0, 360);
    this.globalSpin = wrap(this.globalSpin + this.actuators.spin.value, 0, 360);
    sample.flip = this.globalFlip;
    sample.spin = this.globalSpin;
    this.history[this.point] = sample;
    this.wheel = wrap(this.wheel - this.actuators.wheel.value, 0, 360);
  }

  toggleShippedLook(): boolean {
    this.shippedLook = !this.shippedLook;
    return this.shippedLook;
  }

  captureState(): MelloStateSnapshot {
    return {
      kind: MELLO_PROFILE,
      randomState: this.random.capture(),
      frame: this.frame,
      point: this.point,
      wheel: this.wheel,
      globalSpin: this.globalSpin,
      globalFlip: this.globalFlip,
      shippedLook: this.shippedLook,
      actuators: Object.fromEntries(
        Object.entries(this.actuators).map(([id, actuator]) => [id, { ...actuator }]),
      ) as Record<ActuatorId, Actuator>,
      history: this.history.map((sample) => ({ ...sample })),
    };
  }

  renderData(
    mode: ElectropaintMode,
    compatibilityPolicy: CompatibilityPolicy,
    tick: number,
  ): RenderData {
    const squares: RenderSquare[] = [];
    let chain: Mat4 = rotationX(this.wheel);

    // draw_wings first backs the whole chain through half of the visible zoom
    // history, then walks forward while applying each square's transforms.
    for (let offset = 0; offset < MELLO_VISIBLE_COUNT; offset += 1) {
      const sample = this.history[this.historyIndex(this.point - offset - 1)] ?? blankSample();
      chain = multiply(chain, translation(0, 0, sample.zoom * -0.5));
    }

    for (let offset = 0; offset < MELLO_VISIBLE_COUNT; offset += 1) {
      const sample = this.history[this.historyIndex(this.point - offset - 1)] ?? blankSample();
      let model = multiply(chain, rotationZ(sample.spin));
      model = multiply(model, translation(0, sample.arm, 0));
      model = multiply(model, rotationY(sample.flip));
      model = multiply(model, translation(sample.wrist, 0, 0));
      model = multiply(model, translation(-0.1, -0.1, 0));
      this.addSquare(squares, model, sample, 0);

      chain = multiply(chain, scaling(1, -1, 1));
      if (!this.shippedLook) this.addSquare(squares, modelFromChain(chain, sample), sample, 1);
      chain = multiply(chain, rotationZ(180));
      if (!this.shippedLook) this.addSquare(squares, modelFromChain(chain, sample), sample, 2);
      chain = multiply(chain, scaling(1, -1, 1));
      if (!this.shippedLook) this.addSquare(squares, modelFromChain(chain, sample), sample, 3);
      chain = multiply(chain, rotationZ(sample.twist));
      chain = multiply(chain, translation(0, 0, sample.zoom));
    }

    return {
      mode,
      compatibilityPolicy,
      tick,
      squares,
      ribbons: [],
      background: { r: 0, g: 0, b: 0, a: 1 },
      smear: false,
      smooth: false,
      fade: false,
      depth: false,
      lighting: false,
      ribbonMode: false,
      camera: this.shippedLook
        ? { fovDegrees: 60, distance: 4, flipY: true }
        : { fovDegrees: 30, distance: 10, flipY: false },
    };
  }

  private initializeScript(): void {
    this.initialized = true;
    this.configure("wrist", -1.5, 1.5, 160);
    this.configure("hue", 0, 1.295, 60);
    this.configure("light", 0, 1, 80);
    this.configure("wheel", -0.137, 0, 120);
    this.configure("spin", -0.23, 0, 100);
    this.configure("flip", -2, 0, 50);
    this.configure("arm", -2, 2, 90);
    this.configure("twist", -200, 0, 2250);
    this.configure("outline", 0, 1, 5000);
    this.flipSequence = { phase: "slow", transitionFrame: this.frame + this.randomDelay(1200) };
    this.spinSequence = { phase: "slow", transitionFrame: this.frame + this.randomDelay(1000) };
  }

  private configure(id: ActuatorId, low: number, high: number, duration: number): void {
    Object.assign(this.actuators[id], { low, high, duration });
  }

  private advancePhaseSequences(): void {
    if (this.frame + 0.5 > this.spinSequence.transitionFrame) {
      if (this.spinSequence.phase === "slow") {
        this.configure("spin", -5.23, 0, 40);
        this.spinSequence = { phase: "fast", transitionFrame: this.frame + this.randomDelay(200) };
      } else {
        this.configure("spin", -0.23, 0, 100);
        this.spinSequence = { phase: "slow", transitionFrame: this.frame + this.randomDelay(1000) };
      }
    }
    if (this.frame + 0.5 > this.flipSequence.transitionFrame) {
      if (this.flipSequence.phase === "slow") {
        this.configure("flip", -10, 0, 50);
        this.flipSequence = { phase: "fast", transitionFrame: this.frame + this.randomDelay(220) };
      } else {
        this.configure("flip", -2, 0, 50);
        this.flipSequence = { phase: "slow", transitionFrame: this.frame + this.randomDelay(1200) };
      }
    }
  }

  private randomDelay(duration: number): number {
    return duration * 2 * this.exponentialRandom();
  }

  private exponentialRandom(): number {
    return Math.expm1(this.random.next()) / Math.expm1(1);
  }

  private setTargets(): void {
    for (const actuator of Object.values(this.actuators)) {
      if (actuator.moving) continue;
      const targetMix = this.random.next();
      actuator.target = actuator.low * (1 - targetMix) + actuator.high * targetMix;
      let duration = actuator.duration * 2 * this.exponentialRandom();
      if (duration >= 1) duration = actuator.duration * 2 * this.exponentialRandom();
      duration = Math.max(1, duration);
      actuator.step = (actuator.target - actuator.value) / duration;
      actuator.direction = actuator.step > 0 ? 1 : -1;
      actuator.moving = true;
    }
  }

  private animateActuators(): void {
    for (const actuator of Object.values(this.actuators)) {
      const remaining = actuator.target - (actuator.value + actuator.step);
      if (actuator.direction * remaining < 0) {
        actuator.value = actuator.target;
        actuator.moving = false;
      } else {
        actuator.value += actuator.step;
      }
    }
  }

  private addSquare(squares: RenderSquare[], model: Mat4, sample: MelloSample, mirrorIndex: number): void {
    const fillColor = hlsToRgb(sample.hue, sample.lightness, 1);
    const outlineColor = hlsToRgb(wrap(sample.hue + 0.5, 0, 1), 1 - sample.lightness, 1);
    squares.push({
      model,
      fill: true,
      outline: sample.outline,
      fatLine: false,
      fillColor,
      outlineColor,
      ambient: 0,
      shiny: 1,
      mirrorIndex,
    });
  }

  private historyIndex(index: number): number {
    return ((index % MELLO_HISTORY_LENGTH) + MELLO_HISTORY_LENGTH) % MELLO_HISTORY_LENGTH;
  }
}

function modelFromChain(chain: Mat4, sample: MelloSample): Mat4 {
  let model = multiply(chain, rotationZ(sample.spin));
  model = multiply(model, translation(0, sample.arm, 0));
  model = multiply(model, rotationY(sample.flip));
  model = multiply(model, translation(sample.wrist, 0, 0));
  return multiply(model, translation(-0.1, -0.1, 0));
}
