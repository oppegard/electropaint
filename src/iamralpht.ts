import {
  multiply,
  rotationX,
  rotationY,
  rotationZ,
  scaling,
  translation,
  type Mat4,
} from "./math";
import type {
  CompatibilityPolicy,
  ElectropaintMode,
  ReconstructionProfile,
  RenderData,
  Vec4Color,
} from "./types";

// Reconstructs Ralph Thomas's Elektropaint.js implementation:
// https://github.com/iamralpht/elektropaintjs
export const IAMRALPHT_PROFILE: ReconstructionProfile = "iamralpht-elektropaintjs";
export const IAMRALPHT_SEED = 0x45504a53;
export const IAMRALPHT_HISTORY_LENGTH = 40;

interface Wing {
  radius: number;
  angle: number;
  deltaAngle: number;
  zDelta: number;
  roll: number;
  pitch: number;
  yaw: number;
  color: Vec4Color;
}

export interface IamralphtStateSnapshot {
  randomState: number;
  wings: Wing[];
}

interface RandomWalkOptions {
  min?: number;
  max?: number;
  stability?: number;
  wrap?: boolean;
  maxAcceleration?: number;
  maxSpeed?: number;
}

class SeededRandom {
  constructor(private state: number) {}

  next(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let value = this.state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  }

  capture(): number {
    return this.state;
  }
}

class RandomWalk {
  private readonly min: number;
  private readonly max: number;
  private readonly stability: number;
  private readonly shouldWrap: boolean;
  private readonly maxAcceleration: number;
  private readonly maxSpeed: number;
  private value = 0;
  private delta = 0;
  private count = 1000;
  private acceleration = 0;

  constructor(
    private readonly random: SeededRandom,
    options: RandomWalkOptions = {},
  ) {
    this.min = options.min ?? 0;
    this.max = options.max ?? 1;
    this.stability = options.stability ?? 50;
    this.shouldWrap = options.wrap ?? false;
    this.maxAcceleration = options.maxAcceleration ?? 0.005;
    this.maxSpeed = options.maxSpeed ?? 0.02;
  }

  generate(): number {
    this.count += 1;
    if (this.count > this.stability) {
      this.acceleration = (this.random.next() - 0.5) * 2 * this.maxAcceleration;
      this.count = 0;
    }
    this.delta = Math.min(this.maxSpeed, Math.max(-this.maxSpeed, this.delta + this.acceleration));
    this.value += this.delta;
    if (this.shouldWrap) {
      this.value = ((this.value - this.min) % (this.max - this.min)) + this.min;
    } else {
      this.value = Math.min(this.max, Math.max(this.min, this.value));
    }
    return this.value;
  }
}

export class IamralphtReconstruction {
  private readonly random: SeededRandom;
  private readonly red: RandomWalk;
  private readonly green: RandomWalk;
  private readonly blue: RandomWalk;
  private readonly roll: RandomWalk;
  private readonly pitch: RandomWalk;
  private readonly yaw: RandomWalk;
  private readonly radius: RandomWalk;
  private readonly angle: RandomWalk;
  private readonly deltaAngle: RandomWalk;
  private readonly zDelta: RandomWalk;
  private wings: Wing[] = [];

  constructor(seed = IAMRALPHT_SEED) {
    this.random = new SeededRandom(seed);
    this.red = new RandomWalk(this.random, { min: 0, max: 1, stability: 95 });
    this.green = new RandomWalk(this.random, { min: 0, max: 1, stability: 40 });
    this.blue = new RandomWalk(this.random, { min: 0, max: 1, stability: 70 });
    this.roll = new RandomWalk(this.random, {
      min: 0, max: 360, stability: 80, wrap: true, maxSpeed: 0.5, maxAcceleration: 0.125,
    });
    this.pitch = new RandomWalk(this.random, {
      min: 0, max: 360, stability: 40, wrap: true, maxSpeed: 1, maxAcceleration: 0.125,
    });
    this.yaw = new RandomWalk(this.random, {
      min: 0, max: 360, stability: 50, wrap: true, maxSpeed: 0.75, maxAcceleration: 0.125,
    });
    this.radius = new RandomWalk(this.random, {
      min: -15, max: 15, stability: 150, maxSpeed: 0.05, maxAcceleration: 0.005,
    });
    this.angle = new RandomWalk(this.random, {
      min: 0, max: 360, stability: 120, wrap: true, maxSpeed: 1, maxAcceleration: 0.025,
    });
    this.deltaAngle = new RandomWalk(this.random, {
      min: 0, max: 360, stability: 80, wrap: true, maxSpeed: 0.1, maxAcceleration: 0.01,
    });
    this.zDelta = new RandomWalk(this.random, {
      min: 0.4, max: 0.7, stability: 200, maxSpeed: 0.005, maxAcceleration: 0.0005,
    });
    this.wings = Array.from({ length: IAMRALPHT_HISTORY_LENGTH }, () => this.newWing());
  }

  step(): void {
    this.wings.pop();
    this.wings.unshift(this.newWing());
  }

  captureState(): IamralphtStateSnapshot {
    return {
      randomState: this.random.capture(),
      wings: this.wings.map((wing) => ({ ...wing, color: { ...wing.color } })),
    };
  }

  renderData(
    mode: ElectropaintMode,
    compatibilityPolicy: CompatibilityPolicy,
    tick: number,
  ): RenderData {
    const worldHeight = 20 * Math.tan((30 * Math.PI) / 360);
    const radiusScale = worldHeight / 40;
    const depthScale = worldHeight * 0.02;
    const shapeScale = worldHeight / 4;
    let chain: Mat4 = multiply(translation(0, -worldHeight / 4, 0), rotationX(45));
    const squares = this.wings.map((wing, index) => {
      chain = multiply(chain, translation(0, 0, wing.zDelta * depthScale));
      let model = multiply(chain, rotationZ(wing.angle + index * wing.deltaAngle));
      model = multiply(model, translation(wing.radius * radiusScale, 0, 0));
      model = multiply(model, rotationZ(-wing.yaw));
      model = multiply(model, rotationY(-wing.pitch));
      model = multiply(model, rotationX(wing.roll));
      model = multiply(model, scaling(shapeScale, shapeScale, shapeScale));
      model = multiply(model, translation(-0.1, -0.1, 0));
      return {
        model,
        fill: true,
        outline: true,
        fatLine: false,
        fillColor: { ...wing.color },
        outlineColor: { r: 1, g: 1, b: 1, a: 1 },
        ambient: 0,
        shiny: 1,
        mirrorIndex: 0,
      };
    });

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
    };
  }

  private newWing(): Wing {
    return {
      radius: this.radius.generate(),
      angle: this.angle.generate(),
      deltaAngle: this.deltaAngle.generate(),
      zDelta: this.zDelta.generate(),
      roll: this.roll.generate(),
      pitch: this.pitch.generate(),
      yaw: this.yaw.generate(),
      color: {
        r: this.red.generate(),
        g: this.green.generate(),
        b: this.blue.generate(),
        a: 1,
      },
    };
  }
}
