import type {
  ControlDefinition,
  ElectropaintMode,
  ModulatedSliderState,
  SliderControlDefinition,
} from "./types";

const BOTH = ["classic", "iris-gt"] as const;
const CLASSIC = ["classic"] as const;
const GT = ["iris-gt"] as const;

const slider = (
  id: string,
  label: string,
  min: number,
  max: number,
  defaultValue: number,
  modes: readonly ElectropaintMode[] = BOTH,
  description = label,
  defaultMode: "wrap" | "bounce" = "bounce",
): SliderControlDefinition => ({
  id, label, kind: "slider", min, max, defaultValue, modes, description, defaultMode,
});

export const CONTROL_DEFINITIONS: readonly ControlDefinition[] = [
  { id: "position", label: "position", kind: "puck", min: -1, max: 1, defaultX: 0, defaultY: 0, modes: BOTH, description: "Floating position puck" },
  slider("zoom", "zoom", -0.5, 0.5, 0),
  slider("twist", "twst", -100, 100, 0, BOTH, "Twist rotation"),
  slider("speed", "spd", 0, 1, 0.05, BOTH, "Port-adjusted simulation speed"),
  slider("count", "n", 1, 127, 32, BOTH, "Maximum visible history points"),
  slider("map-rate", "rat", -20, 20, 1, CLASSIC, "Indexed color change rate"),
  slider("map-range", "rng", 0, 100, 1, CLASSIC, "Indexed color separation"),
  slider("ambient", "amb", 0, 1, 0, GT, "Material ambient response"),
  slider("shiny", "shn", 0, 1, 1, GT, "Material shininess"),
  slider("wheel", "whl", -60, 60, 0, BOTH, "Whole-form x rotation"),
  slider("spin", "spn", -20, 20, 0, BOTH, "Per-point z rotation"),
  slider("flip", "flp", -20, 20, 0, BOTH, "Per-point y rotation"),
  slider("arm", "arm", 0, 3, 0, BOTH, "Radial arm translation"),
  slider("wrist", "wrst", 0, 3, 0, BOTH, "Wrist translation"),
  slider("size", "sz", 0.1, 10, 1, BOTH, "Triangle size"),
  { id: "outline", label: "outline", kind: "toggle", defaultValue: false, shortcut: "o", modes: BOTH, description: "Draw complementary outlines" },
  { id: "fat-lines", label: "fat lines", kind: "toggle", defaultValue: false, shortcut: "i", modes: BOTH, description: "Use three-pixel outlines" },
  { id: "fill", label: "fill", kind: "toggle", defaultValue: true, shortcut: "u", modes: BOTH, description: "Fill triangles" },
  { id: "smooth", label: "smooth", kind: "toggle", defaultValue: false, shortcut: "m", modes: BOTH, description: "Use source dual-buffer smoothing" },
  { id: "smear", label: "smear", kind: "toggle", defaultValue: false, shortcut: "q", modes: BOTH, description: "Retain the previous frame" },
  { id: "fade", label: "fade", kind: "toggle", defaultValue: false, shortcut: "w", modes: CLASSIC, description: "Apply the 16-step stippled fade" },
  { id: "background", label: "back", kind: "toggle", defaultValue: false, shortcut: "e", modes: BOTH, description: "Use the complementary animated background" },
  { id: "ribbons", label: "ribbons", kind: "toggle", defaultValue: false, shortcut: "r", modes: GT, description: "Join history points as triangle-mesh ribbons" },
  { id: "depth", label: "z-buf", kind: "toggle", defaultValue: false, shortcut: "z", modes: GT, description: "Enable depth buffering" },
  { id: "lighting", label: "light", kind: "toggle", defaultValue: false, shortcut: "l", modes: GT, description: "Enable two directional lights" },
  { id: "stop", label: "stop", kind: "toggle", defaultValue: false, shortcut: "s", modes: BOTH, description: "Pause simulation" },
  { id: "alpha-outline", label: "outa", kind: "value", min: 0, max: 1, defaultValue: 1, modes: GT, description: "Outline alpha" },
  { id: "alpha-background", label: "baka", kind: "value", min: 0, max: 1, defaultValue: 1, modes: GT, description: "Background alpha" },
  { id: "background-hue-rate", label: "outr", kind: "value", min: -20, max: 20, defaultValue: 0.2, modes: GT, description: "Background hue rate" },
  { id: "channel-rate", label: "channel rate", kind: "value", min: 0, max: 1, defaultValue: 0, modes: GT, description: "Rate of automatic color-channel selection" },
  ...Array.from({ length: 5 }, (_, index): ControlDefinition[] => [
    slider(`hue-${index}`, `hue ${index + 1}`, 0, 2, 1, GT, `Hue channel ${index + 1}`, "wrap"),
    slider(`lightness-${index}`, `light ${index + 1}`, 0, 1, 0.5, GT, `Lightness channel ${index + 1}`, "wrap"),
    { id: `alpha-${index}`, label: `alpha ${index + 1}`, kind: "value", min: 0, max: 1, defaultValue: 1, modes: GT, description: `Alpha channel ${index + 1}` },
    { id: `dwell-${index}`, label: `dwell ${index + 1}`, kind: "value", min: 0, max: 1, defaultValue: index === 0 ? 1 : 0, modes: GT, description: `Dwell share for channel ${index + 1}` },
    { id: `active-${index}`, label: `channel ${index + 1}`, kind: "toggle", defaultValue: index === 0, modes: GT, description: `Select color channel ${index + 1}` },
  ]).flat(),
];

export function controlsForMode(mode: ElectropaintMode): readonly ControlDefinition[] {
  return CONTROL_DEFINITIONS.filter((definition) => definition.modes.includes(mode));
}

export function definitionById(id: string): ControlDefinition | undefined {
  return CONTROL_DEFINITIONS.find((definition) => definition.id === id);
}

export function defaultSliderState(definition: SliderControlDefinition): ModulatedSliderState {
  return {
    value: definition.defaultValue,
    lower: definition.min,
    upper: definition.max,
    rate: definition.id === "hue-0" ? 0.01 : 0,
    mode: definition.defaultMode,
    sense: 1,
  };
}

export function stableControlIds(mode: ElectropaintMode): Set<string> {
  const ids = new Set<string>();
  for (const definition of controlsForMode(mode)) {
    if (definition.kind === "slider") {
      for (const field of ["value", "lower", "upper", "rate", "mode", "reset"]) {
        ids.add(`${definition.id}.${field}`);
      }
    } else if (definition.kind === "puck") {
      ids.add(`${definition.id}.x`);
      ids.add(`${definition.id}.y`);
    } else {
      ids.add(definition.id);
    }
  }
  return ids;
}
