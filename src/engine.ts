import {
  CONTROL_DEFINITIONS,
  controlsForMode,
  defaultSliderState,
  definitionById,
} from "./controls";
import {
  foldTwixt,
  hlsToRgb,
  multiply,
  rotationX,
  rotationY,
  rotationZ,
  scaling,
  transformPoint,
  translation,
  twixt,
  wrap,
  type Mat4,
} from "./math";
import { IamralphtReconstruction, IAMRALPHT_PROFILE, type IamralphtStateSnapshot } from "./iamralpht";
import { MelloReconstruction, MELLO_PROFILE, type MelloStateSnapshot } from "./mello";
import type {
  CompatibilityPolicy,
  ElectropaintMode,
  ModulatedSliderState,
  ReconstructionProfile,
  RenderData,
  RenderRibbonVertex,
  RenderSquare,
  SliderControlDefinition,
  SliderMode,
  TimelineEventV1,
  TimelineEventValue,
  Vec4Color,
} from "./types";

export const HISTORY_LENGTH = 128;
export const TICK_RATE = 60;

interface HistorySample {
  x: number;
  y: number;
  zoom: number;
  arm: number;
  wrist: number;
  twist: number;
  flip: number;
  spin: number;
  outline: boolean;
  fatLine: boolean;
  fill: boolean;
  size: number;
  mapRange: number;
  hue: number;
  lightness: number;
  alpha: number;
  alphaOutline: number;
  shiny: number;
  ambient: number;
}

export interface ElectropaintStateSnapshot {
  mode: ElectropaintMode;
  compatibilityPolicy: CompatibilityPolicy;
  tick: number;
  point: number;
  interpolation: number;
  wheel: number;
  spin: number;
  flip: number;
  color: number;
  foregroundHue: number;
  backgroundHue: number;
  channelProgress: number;
  activeChannel: number;
  puck: { x: number; y: number };
  sliders: Record<string, ModulatedSliderState>;
  values: Record<string, number | boolean>;
  history: HistorySample[];
  reconstructionProfile: ReconstructionProfile | null;
  reconstruction: IamralphtStateSnapshot | MelloStateSnapshot | null;
}

const emptySample = (): HistorySample => ({
  x: 0,
  y: 0,
  zoom: 0,
  arm: 0,
  wrist: 0,
  twist: 0,
  flip: 0,
  spin: 0,
  outline: false,
  fatLine: false,
  fill: false,
  size: 0,
  mapRange: 0,
  hue: 0,
  lightness: 0,
  alpha: 0,
  alphaOutline: 0,
  shiny: 0,
  ambient: 0,
});

const clamp = (value: number, min: number, max: number): number => Math.min(max, Math.max(min, value));

export function advanceSlider(
  slider: ModulatedSliderState,
  definition: SliderControlDefinition,
  speed: number,
): void {
  if (slider.rate === 0 || slider.upper === slider.lower) return;
  const delta = slider.sense
    * slider.rate
    * ((slider.upper - slider.lower) / (definition.max - definition.min))
    * speed;
  slider.value += delta;

  if (slider.mode === "bounce") {
    if (slider.value < slider.lower) {
      slider.value = -slider.value + 2 * slider.lower;
      slider.sense = 1;
    } else if (slider.value > slider.upper) {
      slider.value = -slider.value + 2 * slider.upper;
      slider.sense = -1;
    }
  } else if (slider.value < slider.lower) {
    slider.value = slider.upper - (slider.lower - slider.value);
  } else if (slider.value > slider.upper) {
    slider.value = slider.lower + (slider.value - slider.upper);
  }
  slider.value = clamp(slider.value, slider.lower, slider.upper);
}

function matrixForSample(
  chain: Mat4,
  x: number,
  y: number,
  spin: number,
  arm: number,
  flip: number,
  wrist: number,
  size: number,
): Mat4 {
  let model = multiply(chain, translation(x, y, 0));
  model = multiply(model, rotationZ(spin));
  model = multiply(model, translation(0, arm, 0));
  model = multiply(model, rotationY(flip));
  model = multiply(model, translation(wrist, 0, 0));
  return multiply(model, scaling(size, size, 1));
}

function withAlpha(color: Vec4Color, alpha: number): Vec4Color {
  return { ...color, a: alpha };
}

export class ElectropaintEngine {
  mode: ElectropaintMode;
  compatibilityPolicy: CompatibilityPolicy;
  tick = 0;

  private point = 0;
  private interpolation = 0;
  private wheel = 0;
  private globalSpin = 0;
  private globalFlip = 0;
  private globalColor = 704;
  private foregroundHue = 0.5;
  private backgroundHue = 0.5;
  private channelProgress = 0;
  private activeChannel = 0;
  private puck = { x: 0, y: 0 };
  private sliders = new Map<string, ModulatedSliderState>();
  private values = new Map<string, number | boolean>();
  private history: HistorySample[] = Array.from({ length: HISTORY_LENGTH }, emptySample);
  private reconstruction: IamralphtReconstruction | MelloReconstruction | null = null;

  constructor(mode: ElectropaintMode = "classic", compatibilityPolicy: CompatibilityPolicy = "corrected") {
    this.mode = mode;
    this.compatibilityPolicy = compatibilityPolicy;
    this.reset(mode, compatibilityPolicy);
  }

  reset(mode = this.mode, compatibilityPolicy = this.compatibilityPolicy): void {
    this.mode = mode;
    this.compatibilityPolicy = compatibilityPolicy;
    this.tick = 0;
    this.point = 0;
    this.interpolation = 0;
    this.wheel = 0;
    this.globalSpin = 0;
    this.globalFlip = 0;
    this.globalColor = 704;
    this.foregroundHue = 0.5;
    this.backgroundHue = 0.5;
    this.channelProgress = 0;
    this.activeChannel = 0;
    this.puck = { x: 0, y: 0 };
    this.sliders.clear();
    this.values.clear();
    this.history = Array.from({ length: HISTORY_LENGTH }, emptySample);
    this.reconstruction = null;

    for (const definition of controlsForMode(mode)) {
      if (definition.kind === "slider") {
        this.sliders.set(definition.id, defaultSliderState(definition));
      } else if (definition.kind === "toggle" || definition.kind === "value") {
        this.values.set(definition.id, definition.defaultValue);
      }
    }
  }

  step(): void {
    if (this.reconstruction) {
      this.reconstruction.step();
      this.tick += 1;
      return;
    }
    if (this.booleanValue("stop")) {
      this.tick += 1;
      return;
    }

    const speed = this.slider("speed").value;
    this.interpolation += speed;
    const crossedPoint = this.interpolation >= 1;
    this.point += Math.floor(this.interpolation);
    this.interpolation %= 1;

    if (this.mode === "iris-gt") {
      this.channelProgress = wrap(
        this.channelProgress + this.numberValue("channel-rate") * speed,
        0,
        1,
      );
    }

    const index = this.historyIndex(this.point);
    const sample = this.history[index] ?? emptySample();
    sample.x = this.puck.x;
    sample.y = this.puck.y;
    sample.zoom = this.slider("zoom").value;
    sample.arm = this.slider("arm").value;
    sample.wrist = this.slider("wrist").value;
    sample.twist = this.slider("twist").value;
    sample.outline = this.booleanValue("outline");
    sample.fatLine = this.booleanValue("fat-lines");
    sample.fill = this.booleanValue("fill");
    sample.size = this.slider("size").value;

    const wheelDelta = speed * this.slider("wheel").value;
    if (this.mode === "iris-gt") {
      sample.alpha = this.numberValue(`alpha-${this.activeChannel}`);
      sample.alphaOutline = this.numberValue("alpha-outline");
      sample.shiny = this.slider("shiny").value;
      sample.ambient = this.slider("ambient").value;
      this.foregroundHue = wrap(this.slider(`hue-${this.activeChannel}`).value, 0, 1);
      sample.hue = this.foregroundHue;
      sample.lightness = this.slider(`lightness-${this.activeChannel}`).value;
      this.backgroundHue = wrap(
        this.backgroundHue + speed * this.numberValue("background-hue-rate") * 0.05,
        0,
        1,
      );
      this.selectAutomaticChannel();
    } else {
      sample.mapRange = this.slider("map-range").value;
      this.globalColor = wrap(
        this.globalColor + speed * this.slider("map-rate").value,
        640,
        768,
      );
    }

    if (crossedPoint) {
      this.globalFlip = wrap(this.globalFlip + this.slider("flip").value, 0, 360);
      this.globalSpin = wrap(this.globalSpin + this.slider("spin").value, 0, 360);
      sample.flip = this.globalFlip;
      sample.spin = this.globalSpin;
    }
    this.history[index] = sample;
    this.wheel = wrap(this.wheel - wheelDelta, 0, 360);

    for (const definition of controlsForMode(this.mode)) {
      if (definition.kind !== "slider") continue;
      const sliderState = this.sliders.get(definition.id);
      if (sliderState) advanceSlider(sliderState, definition, speed);
    }
    this.tick += 1;
  }

  applyControlEvent(event: Pick<TimelineEventV1, "controlId" | "value">): boolean {
    const { controlId, value } = event;
    const separator = controlId.lastIndexOf(".");
    const baseId = separator < 0 ? controlId : controlId.slice(0, separator);
    const field = separator < 0 ? "" : controlId.slice(separator + 1);
    const definition = definitionById(baseId);
    if (!definition || !definition.modes.includes(this.mode)) return false;

    if (definition.kind === "slider") {
      const state = this.sliders.get(baseId);
      if (!state) return false;
      if (field === "reset") {
        state.lower = definition.min;
        state.upper = definition.max;
        state.rate = 0;
        if (state.value !== definition.defaultValue) {
          state.value = definition.defaultValue;
        } else {
          if (baseId === "wheel") this.wheel = 0;
          if (baseId === "spin") this.globalSpin = 0;
          if (baseId === "flip") this.globalFlip = 0;
        }
        return true;
      }
      if (field === "mode" && (value === "wrap" || value === "bounce")) {
        state.mode = value;
        return true;
      }
      if (typeof value !== "number" || !Number.isFinite(value)) return false;
      if (field === "value") state.value = clamp(value, state.lower, state.upper);
      else if (field === "lower") {
        state.lower = clamp(value, definition.min, state.upper);
        state.value = clamp(state.value, state.lower, state.upper);
      } else if (field === "upper") {
        state.upper = clamp(value, state.lower, definition.max);
        state.value = clamp(state.value, state.lower, state.upper);
      } else if (field === "rate") {
        state.rate = clamp(value, 0, (definition.max - definition.min) / 2);
      } else return false;
      return true;
    }

    if (definition.kind === "puck") {
      if (typeof value !== "number" || !Number.isFinite(value)) return false;
      if (field === "x" || field === "y") {
        this.puck[field] = clamp(value, definition.min, definition.max);
        return true;
      }
      return false;
    }

    if (definition.kind === "toggle") {
      if (typeof value !== "boolean") return false;
      this.values.set(baseId, value);
      if (baseId.startsWith("active-") && value) {
        const selected = Number(baseId.slice("active-".length));
        this.activeChannel = selected;
        for (let index = 0; index < 5; index += 1) {
          this.values.set(`active-${index}`, index === selected);
        }
      }
      return true;
    }

    if (typeof value !== "number" || !Number.isFinite(value)) return false;
    const oldValue = this.numberValue(baseId);
    this.values.set(baseId, clamp(value, definition.min, definition.max));
    if (baseId.startsWith("dwell-")) {
      this.redistributeDwell(Number(baseId.slice("dwell-".length)), oldValue);
    }
    return true;
  }

  apply(controlId: string, value: TimelineEventValue): boolean {
    return this.applyControlEvent({ controlId, value });
  }

  setReconstruction(profile: ReconstructionProfile | undefined): void {
    if (profile === IAMRALPHT_PROFILE) this.reconstruction = new IamralphtReconstruction();
    else if (profile === MELLO_PROFILE) this.reconstruction = new MelloReconstruction();
    else this.reconstruction = null;
  }

  get reconstructionProfile(): ReconstructionProfile | null {
    if (this.reconstruction instanceof IamralphtReconstruction) return IAMRALPHT_PROFILE;
    if (this.reconstruction instanceof MelloReconstruction) return MELLO_PROFILE;
    return null;
  }

  toggle1994Look(): boolean | null {
    return this.reconstruction instanceof MelloReconstruction
      ? this.reconstruction.toggleShippedLook()
      : null;
  }

  getControlValue(controlId: string): TimelineEventValue | undefined {
    const separator = controlId.lastIndexOf(".");
    if (separator >= 0) {
      const baseId = controlId.slice(0, separator);
      const field = controlId.slice(separator + 1);
      if (baseId === "position" && (field === "x" || field === "y")) return this.puck[field];
      const state = this.sliders.get(baseId);
      if (state && field in state) return state[field as keyof ModulatedSliderState] as number | SliderMode;
      return undefined;
    }
    return this.values.get(controlId);
  }

  captureState(): ElectropaintStateSnapshot {
    return {
      mode: this.mode,
      compatibilityPolicy: this.compatibilityPolicy,
      tick: this.tick,
      point: this.point,
      interpolation: this.interpolation,
      wheel: this.wheel,
      spin: this.globalSpin,
      flip: this.globalFlip,
      color: this.globalColor,
      foregroundHue: this.foregroundHue,
      backgroundHue: this.backgroundHue,
      channelProgress: this.channelProgress,
      activeChannel: this.activeChannel,
      puck: { ...this.puck },
      sliders: Object.fromEntries(
        [...this.sliders].map(([id, state]) => [id, { ...state }]),
      ),
      values: Object.fromEntries(this.values),
      history: this.history.map((sample) => ({ ...sample })),
      reconstructionProfile: this.reconstructionProfile,
      reconstruction: this.reconstruction?.captureState() ?? null,
    };
  }

  renderData(): RenderData {
    if (this.reconstruction) {
      return this.reconstruction.renderData(this.mode, this.compatibilityPolicy, this.tick);
    }
    const squares: RenderSquare[] = [];
    const ribbons: RenderRibbonVertex[][] = [];
    const count = Math.trunc(this.slider("count").value);
    let chain = rotationX(this.wheel);
    let colorIndex = this.globalColor;

    for (let historyPoint = this.point; historyPoint > this.point - count; historyPoint -= 1) {
      const index = this.historyIndex(historyPoint);
      const previousIndex = this.historyIndex(index - 1);
      const current = this.history[index] ?? emptySample();
      const previous = this.history[previousIndex] ?? emptySample();
      const interpolated = this.interpolateSample(current, previous);
      let fillColor: Vec4Color;
      let outlineColor: Vec4Color;

      if (this.mode === "classic") {
        const outlineIndex = wrap(Math.trunc(colorIndex) + 64, 640, 768);
        colorIndex = wrap(colorIndex - current.mapRange, 640, 768);
        fillColor = this.paletteColor(colorIndex);
        outlineColor = this.paletteColor(outlineIndex);
      } else {
        fillColor = withAlpha(hlsToRgb(interpolated.hue, interpolated.lightness, 1), interpolated.alpha);
        outlineColor = withAlpha(
          hlsToRgb(wrap(interpolated.hue + 0.5, 0, 1), 1 - interpolated.lightness, 1),
          interpolated.alphaOutline,
        );
      }

      const local = matrixForSample(
        chain,
        interpolated.x,
        interpolated.y,
        interpolated.spin,
        interpolated.arm,
        interpolated.flip,
        interpolated.wrist,
        interpolated.size,
      );
      for (let mirrorIndex = 0; mirrorIndex < 4; mirrorIndex += 1) {
        const model = mirrorIndex === 0
          ? local
          : matrixForSample(
            chain,
            interpolated.x,
            interpolated.y,
            interpolated.spin,
            interpolated.arm,
            interpolated.flip,
            interpolated.wrist,
            interpolated.size,
          );
        squares.push({
          model,
          fill: current.fill,
          outline: current.outline && (this.compatibilityPolicy === "corrected" || mirrorIndex !== 0),
          fatLine: current.fatLine,
          fillColor,
          outlineColor,
          ambient: interpolated.ambient,
          shiny: interpolated.shiny,
          mirrorIndex,
        });

        if (mirrorIndex === 0) chain = multiply(chain, scaling(1, -1, 1));
        else if (mirrorIndex === 1) chain = multiply(chain, rotationZ(180));
        else if (mirrorIndex === 2) chain = multiply(chain, scaling(1, -1, 1));
      }
      chain = multiply(chain, rotationZ(interpolated.twist));
      chain = multiply(chain, translation(0, 0, interpolated.zoom));
    }

    if (this.mode === "iris-gt" && this.booleanValue("ribbons")) {
      ribbons.push(...this.buildRibbons(count));
    }

    return {
      mode: this.mode,
      compatibilityPolicy: this.compatibilityPolicy,
      tick: this.tick,
      squares,
      ribbons,
      background: this.backgroundColor(),
      smear: this.booleanValue("smear"),
      smooth: this.booleanValue("smooth"),
      fade: this.mode === "classic" && this.booleanValue("fade"),
      depth: this.mode === "iris-gt" && this.booleanValue("depth"),
      lighting: this.mode === "iris-gt" && this.booleanValue("lighting"),
      ribbonMode: this.mode === "iris-gt" && this.booleanValue("ribbons"),
    };
  }

  private buildRibbons(count: number): RenderRibbonVertex[][] {
    const ribbons: RenderRibbonVertex[][] = [];
    let base = rotationX(this.wheel);
    for (let ribbonIndex = 0; ribbonIndex < 4; ribbonIndex += 1) {
      const vertices: RenderRibbonVertex[] = [];
      let chain = base;
      for (let historyPoint = this.point; historyPoint > this.point - count; historyPoint -= 1) {
        const index = this.historyIndex(historyPoint);
        const previousIndex = this.historyIndex(index - 1);
        const current = this.history[index] ?? emptySample();
        const previous = this.history[previousIndex] ?? emptySample();
        const sample = this.interpolateSample(current, previous);
        const model = matrixForSample(
          chain, sample.x, sample.y, sample.spin, sample.arm, sample.flip, sample.wrist, sample.size,
        );
        const color = withAlpha(hlsToRgb(sample.hue, sample.lightness, 1), sample.alpha);
        vertices.push(
          { position: transformPoint(model, [0, 0, 0]), color },
          { position: transformPoint(model, [0.2, 0, 0]), color },
        );
        const signedTwist = ribbonIndex < 2 ? sample.twist : -sample.twist;
        chain = multiply(chain, rotationZ(signedTwist));
        chain = multiply(chain, translation(0, 0, sample.zoom));
      }
      ribbons.push(vertices);
      base = ribbonIndex % 2 === 1
        ? multiply(base, scaling(1, -1, 1))
        : multiply(base, rotationZ(180));
    }
    return ribbons;
  }

  private interpolateSample(current: HistorySample, previous: HistorySample): HistorySample {
    const t = this.interpolation;
    return {
      x: twixt(current.x, previous.x, t),
      y: twixt(current.y, previous.y, t),
      zoom: twixt(current.zoom, previous.zoom, t),
      arm: twixt(current.arm, previous.arm, t),
      wrist: twixt(current.wrist, previous.wrist, t),
      twist: twixt(current.twist, previous.twist, t),
      flip: foldTwixt(current.flip, previous.flip, t, 360),
      spin: foldTwixt(current.spin, previous.spin, t, 360),
      outline: current.outline,
      fatLine: current.fatLine,
      fill: current.fill,
      size: twixt(current.size, previous.size, t),
      mapRange: current.mapRange,
      hue: foldTwixt(current.hue, previous.hue, t, 1),
      lightness: foldTwixt(current.lightness, previous.lightness, t, 1),
      alpha: twixt(current.alpha, previous.alpha, t),
      alphaOutline: twixt(current.alphaOutline, previous.alphaOutline, t),
      shiny: twixt(current.shiny, previous.shiny, t),
      ambient: twixt(current.ambient, previous.ambient, t),
    };
  }

  private backgroundColor(): Vec4Color {
    if (!this.booleanValue("background")) return { r: 0, g: 0, b: 0, a: 1 };
    if (this.mode === "classic") {
      return this.paletteColor(wrap(Math.trunc(this.globalColor) + 64, 640, 768));
    }
    return withAlpha(hlsToRgb(this.backgroundHue, 0.5, 1), this.numberValue("alpha-background"));
  }

  private paletteColor(index: number): Vec4Color {
    const paletteIndex = wrap(Math.trunc(index), 640, 768) - 640;
    return hlsToRgb(paletteIndex / 128, 0.5, 1);
  }

  private selectAutomaticChannel(): void {
    let total = 0;
    let selected = 0;
    for (let index = 0; index < 5; index += 1) {
      total += this.numberValue(`dwell-${index}`);
      if (total > this.channelProgress) {
        selected = index;
        break;
      }
    }
    this.activeChannel = selected;
    for (let index = 0; index < 5; index += 1) {
      this.values.set(`active-${index}`, index === selected);
    }
  }

  private redistributeDwell(changed: number, oldValue: number): void {
    const newValue = this.numberValue(`dwell-${changed}`);
    let otherTotal = 0;
    for (let index = 0; index < 5; index += 1) {
      if (index !== changed) otherTotal += this.numberValue(`dwell-${index}`);
    }
    const difference = newValue - oldValue;
    for (let index = 0; index < 5; index += 1) {
      if (index === changed) continue;
      const current = this.numberValue(`dwell-${index}`);
      const adjusted = otherTotal === 0
        ? current - difference / 5
        : current - difference * current / otherTotal;
      this.values.set(`dwell-${index}`, clamp(adjusted, 0, 1));
    }
  }

  private slider(id: string): ModulatedSliderState {
    const sliderState = this.sliders.get(id);
    if (!sliderState) throw new Error(`Slider ${id} is unavailable in ${this.mode} mode`);
    return sliderState;
  }

  private booleanValue(id: string): boolean {
    return this.values.get(id) === true;
  }

  private numberValue(id: string): number {
    const value = this.values.get(id);
    return typeof value === "number" ? value : 0;
  }

  private historyIndex(index: number): number {
    return ((index % HISTORY_LENGTH) + HISTORY_LENGTH) % HISTORY_LENGTH;
  }
}

export const SOURCE_DEFAULTS = Object.freeze(
  Object.fromEntries(CONTROL_DEFINITIONS.map((definition) => [
    definition.id,
    definition.kind === "slider"
      ? definition.defaultValue
      : definition.kind === "puck"
        ? [definition.defaultX, definition.defaultY]
        : definition.defaultValue,
  ])),
);
