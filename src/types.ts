export type ElectropaintMode = "classic" | "iris-gt";
export type CompatibilityPolicy = "corrected" | "source";
export type SliderMode = "wrap" | "bounce";
export type ReconstructionProfile = "iamralpht-elektropaintjs";

export interface ModulatedSliderState {
  value: number;
  lower: number;
  upper: number;
  rate: number;
  mode: SliderMode;
  sense: 1 | -1;
}

interface ControlBase {
  id: string;
  label: string;
  modes: readonly ElectropaintMode[];
  description: string;
}

export interface SliderControlDefinition extends ControlBase {
  kind: "slider";
  min: number;
  max: number;
  defaultValue: number;
  defaultMode: SliderMode;
}

export interface ToggleControlDefinition extends ControlBase {
  kind: "toggle";
  defaultValue: boolean;
  shortcut?: string;
}

export interface ValueControlDefinition extends ControlBase {
  kind: "value";
  min: number;
  max: number;
  defaultValue: number;
}

export interface PuckControlDefinition extends ControlBase {
  kind: "puck";
  min: number;
  max: number;
  defaultX: number;
  defaultY: number;
}

export type ControlDefinition =
  | SliderControlDefinition
  | ToggleControlDefinition
  | ValueControlDefinition
  | PuckControlDefinition;

export type TimelineEventValue = number | boolean | SliderMode;

export interface TimelineEventV1 {
  tick: number;
  controlId: string;
  value: TimelineEventValue;
}

export interface TimelineV1 {
  version: 1;
  mode: ElectropaintMode;
  tickRate: 60;
  compatibilityPolicy: CompatibilityPolicy;
  events: TimelineEventV1[];
  loop: {
    enabled: boolean;
    startTick: number;
    endTick: number;
  };
  metadata?: {
    title?: string;
    reconstructed?: boolean;
    profile?: ReconstructionProfile;
  };
}

export interface Vec4Color {
  r: number;
  g: number;
  b: number;
  a: number;
}

export interface RenderSquare {
  model: number[];
  fill: boolean;
  outline: boolean;
  fatLine: boolean;
  fillColor: Vec4Color;
  outlineColor: Vec4Color;
  ambient: number;
  shiny: number;
  mirrorIndex: number;
}

export interface RenderRibbonVertex {
  position: [number, number, number];
  color: Vec4Color;
}

export interface RenderData {
  mode: ElectropaintMode;
  compatibilityPolicy: CompatibilityPolicy;
  tick: number;
  squares: RenderSquare[];
  ribbons: RenderRibbonVertex[][];
  background: Vec4Color;
  smear: boolean;
  smooth: boolean;
  fade: boolean;
  depth: boolean;
  lighting: boolean;
  ribbonMode: boolean;
}
