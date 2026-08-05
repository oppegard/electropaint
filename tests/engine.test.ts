import { describe, expect, it } from "vitest";
import fixture from "./fixtures/reference.json";
import { CONTROL_DEFINITIONS, defaultSliderState } from "../src/controls";
import { advanceSlider, ElectropaintEngine, HISTORY_LENGTH, SOURCE_DEFAULTS } from "../src/engine";
import {
  foldTwixt,
  hlsToRgb,
  identity,
  multiply,
  rotationY,
  rotationZ,
  scaling,
  transformPoint,
  translation,
  twixt,
} from "../src/math";
import { CLASSIC_RECONSTRUCTION } from "../src/reconstructed";
import { TimelineRecorder, runTimeline, validateTimeline } from "../src/timeline";
import type { SliderControlDefinition } from "../src/types";

describe("source-derived numerics", () => {
  it("matches interpolation and angle folding fixtures", () => {
    expect(twixt(20, 10, 0.25)).toBeCloseTo(fixture.twixt, 10);
    expect(foldTwixt(10, 350, 0.5, 360)).toBeCloseTo(fixture.foldTwixt, 10);
  });

  it("matches the C HLS conversion", () => {
    const color = hlsToRgb(0.5, 0.5, 1);
    expect([color.r, color.g, color.b]).toEqual(fixture.hls);
  });

  it("matches a representative transformed vertex", () => {
    let matrix = identity();
    matrix = multiply(matrix, translation(0.1, -0.2, 0));
    matrix = multiply(matrix, rotationZ(30));
    matrix = multiply(matrix, translation(0, 0.5, 0));
    matrix = multiply(matrix, rotationY(20));
    matrix = multiply(matrix, translation(0.25, 0, 0));
    matrix = multiply(matrix, scaling(2, 2, 1));
    const vertex = transformPoint(matrix, [0.2, 0, 0]);
    vertex.forEach((value, index) => expect(value).toBeCloseTo(fixture.vertex[index] ?? NaN, 10));
  });
});

describe("compound controls", () => {
  const testDefinition: SliderControlDefinition = {
    id: "test",
    label: "test",
    kind: "slider",
    min: 0,
    max: 1,
    defaultValue: 0.95,
    defaultMode: "bounce",
    modes: ["classic"],
    description: "fixture",
  };

  it("reflects at bounce boundaries", () => {
    const state = { ...defaultSliderState(testDefinition), value: 0.95, rate: 0.2 };
    advanceSlider(state, testDefinition, 0.5);
    expect(state.value).toBeCloseTo(fixture.bounce, 10);
    expect(state.sense).toBe(-1);
  });

  it("wraps at boundaries", () => {
    const state = { ...defaultSliderState(testDefinition), value: 0.95, rate: 0.2, mode: "wrap" as const };
    advanceSlider(state, testDefinition, 0.5);
    expect(state.value).toBeCloseTo(fixture.wrap, 10);
  });

  it("retains all source ranges and defaults", () => {
    expect(SOURCE_DEFAULTS.speed).toBe(0.05);
    expect(SOURCE_DEFAULTS.count).toBe(32);
    expect(SOURCE_DEFAULTS.fill).toBe(true);
    expect(CONTROL_DEFINITIONS.find(({ id }) => id === "twist")).toMatchObject({ min: -100, max: 100 });
    expect(CONTROL_DEFINITIONS.find(({ id }) => id === "count")).toMatchObject({ min: 1, max: 127 });
  });
});

describe("engine state", () => {
  it("rolls its 128-entry history without changing array size", () => {
    const engine = new ElectropaintEngine();
    engine.apply("speed.value", 1);
    for (let index = 0; index < HISTORY_LENGTH + 12; index += 1) engine.step();
    const state = engine.captureState();
    expect(state.point).toBe(HISTORY_LENGTH + 12);
    expect(state.history).toHaveLength(HISTORY_LENGTH);
  });

  it("resets to edition-specific controls on mode changes", () => {
    const engine = new ElectropaintEngine("classic");
    engine.apply("map-rate.value", 12);
    engine.reset("iris-gt", "source");
    const state = engine.captureState();
    expect(state.mode).toBe("iris-gt");
    expect(state.compatibilityPolicy).toBe("source");
    expect(state.sliders["map-rate"]).toBeUndefined();
    expect(state.sliders.ambient?.value).toBe(0);
    expect(state.sliders.shiny?.value).toBe(1);
  });

  it("preserves the source's two-stage global reset behavior", () => {
    const engine = new ElectropaintEngine();
    engine.apply("wheel.value", 4);
    for (let index = 0; index < 20; index += 1) engine.step();
    const rotated = engine.captureState().wheel;
    expect(rotated).not.toBe(0);
    engine.apply("wheel.reset", true);
    expect(engine.captureState().sliders.wheel?.value).toBe(0);
    expect(engine.captureState().wheel).toBe(rotated);
    engine.apply("wheel.reset", true);
    expect(engine.captureState().wheel).toBe(0);
  });

  it("keeps timeline time moving while stop freezes simulation state", () => {
    const engine = new ElectropaintEngine();
    const before = engine.captureState();
    engine.apply("stop", true);
    engine.step();
    const after = engine.captureState();
    expect(after.tick).toBe(before.tick + 1);
    expect(after.point).toBe(before.point);
    expect(after.interpolation).toBe(before.interpolation);
  });

  it("preserves or corrects the first missing outline", () => {
    const source = new ElectropaintEngine("classic", "source");
    source.apply("outline", true);
    source.apply("speed.value", 1);
    source.step();
    expect(source.renderData().triangles.slice(0, 2).map(({ outline }) => outline)).toEqual([false, true]);

    const corrected = new ElectropaintEngine("classic", "corrected");
    corrected.apply("outline", true);
    corrected.apply("speed.value", 1);
    corrected.step();
    expect(corrected.renderData().triangles[0]?.outline).toBe(true);
  });
});

describe("TimelineV1", () => {
  it("rejects malformed imports", () => {
    const result = validateTimeline({ ...CLASSIC_RECONSTRUCTION, tickRate: 30 });
    expect(result).toEqual({ ok: false, error: "Timeline tickRate must be 60." });
  });

  it("rejects type-incompatible and out-of-range control events", () => {
    expect(validateTimeline({
      ...CLASSIC_RECONSTRUCTION,
      events: [{ tick: 0, controlId: "outline", value: 1 }],
    }).ok).toBe(false);
    expect(validateTimeline({
      ...CLASSIC_RECONSTRUCTION,
      events: [{ tick: 0, controlId: "speed.value", value: 2 }],
    }).ok).toBe(false);
  });

  it("replays deterministically", () => {
    const first = runTimeline(CLASSIC_RECONSTRUCTION, 720).captureState();
    const second = runTimeline(CLASSIC_RECONSTRUCTION, 720).captureState();
    expect(second).toEqual(first);
  });

  it("records and appends stable control IDs", () => {
    const recorder = new TimelineRecorder();
    recorder.start(10);
    recorder.capture(12, "outline", true);
    recorder.stop();
    recorder.start(20, true);
    recorder.capture(21, "size.value", 2);
    const timeline = recorder.timeline("classic", "corrected");
    expect(timeline.events).toEqual([
      { tick: 2, controlId: "outline", value: true },
      { tick: 4, controlId: "size.value", value: 2 },
    ]);
    expect(validateTimeline(timeline).ok).toBe(true);
  });
});
