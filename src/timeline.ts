import { definitionById, stableControlIds } from "./controls";
import { ElectropaintEngine, TICK_RATE } from "./engine";
import type {
  CompatibilityPolicy,
  ElectropaintMode,
  TimelineEventV1,
  TimelineEventValue,
  TimelineV1,
} from "./types";

export type TimelineValidationResult =
  | { ok: true; timeline: TimelineV1 }
  | { ok: false; error: string };

const isRecord = (value: unknown): value is Record<string, unknown> => (
  typeof value === "object" && value !== null && !Array.isArray(value)
);

export function validateTimeline(value: unknown): TimelineValidationResult {
  if (!isRecord(value)) return { ok: false, error: "Timeline must be a JSON object." };
  if (value.version !== 1) return { ok: false, error: "Only TimelineV1 (version 1) is supported." };
  if (value.mode !== "classic" && value.mode !== "iris-gt") {
    return { ok: false, error: "Timeline mode must be classic or iris-gt." };
  }
  if (value.tickRate !== TICK_RATE) return { ok: false, error: "Timeline tickRate must be 60." };
  if (value.compatibilityPolicy !== "corrected" && value.compatibilityPolicy !== "source") {
    return { ok: false, error: "Timeline compatibilityPolicy must be corrected or source." };
  }
  if (!Array.isArray(value.events)) return { ok: false, error: "Timeline events must be an array." };
  if (!isRecord(value.loop)) return { ok: false, error: "Timeline loop metadata is required." };
  const { enabled, startTick, endTick } = value.loop;
  if (typeof enabled !== "boolean"
    || !Number.isSafeInteger(startTick)
    || !Number.isSafeInteger(endTick)
    || (startTick as number) < 0
    || (endTick as number) <= (startTick as number)) {
    return { ok: false, error: "Timeline loop bounds are invalid." };
  }

  const allowedIds = stableControlIds(value.mode);
  const events: TimelineEventV1[] = [];
  let previousTick = -1;
  for (const rawEvent of value.events) {
    if (!isRecord(rawEvent)
      || !Number.isSafeInteger(rawEvent.tick)
      || (rawEvent.tick as number) < previousTick
      || typeof rawEvent.controlId !== "string"
      || !allowedIds.has(rawEvent.controlId)
      || !isTimelineValue(rawEvent.value)
      || !isValidControlValue(value.mode, rawEvent.controlId, rawEvent.value)) {
      return { ok: false, error: "Timeline contains a malformed, unordered, or unknown control event." };
    }
    if ((rawEvent.tick as number) > (endTick as number)) {
      return { ok: false, error: "Timeline event occurs after loop.endTick." };
    }
    previousTick = rawEvent.tick as number;
    events.push({
      tick: rawEvent.tick as number,
      controlId: rawEvent.controlId,
      value: rawEvent.value,
    });
  }

  const metadata = isRecord(value.metadata)
    ? {
      ...(typeof value.metadata.title === "string" ? { title: value.metadata.title } : {}),
      ...(typeof value.metadata.reconstructed === "boolean"
        ? { reconstructed: value.metadata.reconstructed }
        : {}),
    }
    : undefined;

  return {
    ok: true,
    timeline: {
      version: 1,
      mode: value.mode,
      tickRate: TICK_RATE,
      compatibilityPolicy: value.compatibilityPolicy,
      events,
      loop: {
        enabled,
        startTick: startTick as number,
        endTick: endTick as number,
      },
      ...(metadata ? { metadata } : {}),
    },
  };
}

function isTimelineValue(value: unknown): value is TimelineEventValue {
  return (typeof value === "number" && Number.isFinite(value))
    || typeof value === "boolean"
    || value === "wrap"
    || value === "bounce";
}

function isValidControlValue(
  mode: ElectropaintMode,
  controlId: string,
  value: TimelineEventValue,
): boolean {
  const separator = controlId.lastIndexOf(".");
  const baseId = separator < 0 ? controlId : controlId.slice(0, separator);
  const field = separator < 0 ? "" : controlId.slice(separator + 1);
  const definition = definitionById(baseId);
  if (!definition || !definition.modes.includes(mode)) return false;
  if (definition.kind === "toggle") return typeof value === "boolean";
  if (definition.kind === "puck") {
    return (field === "x" || field === "y")
      && typeof value === "number"
      && value >= definition.min
      && value <= definition.max;
  }
  if (definition.kind === "value") {
    return typeof value === "number" && value >= definition.min && value <= definition.max;
  }
  if (field === "mode") return value === "wrap" || value === "bounce";
  if (field === "reset") return value === true;
  if (typeof value !== "number") return false;
  if (field === "rate") return value >= 0 && value <= (definition.max - definition.min) / 2;
  return (field === "value" || field === "lower" || field === "upper")
    && value >= definition.min
    && value <= definition.max;
}

export class TimelineRecorder {
  private events: TimelineEventV1[] = [];
  private startTick = 0;
  private appendOffset = 0;
  private active = false;

  start(currentTick: number, append = false): void {
    if (!append) this.events = [];
    this.appendOffset = append && this.events.length > 0
      ? (this.events.at(-1)?.tick ?? 0) + 1
      : 0;
    this.startTick = currentTick;
    this.active = true;
  }

  stop(): void {
    this.active = false;
  }

  get isRecording(): boolean {
    return this.active;
  }

  capture(currentTick: number, controlId: string, value: TimelineEventValue): void {
    if (!this.active) return;
    this.events.push({
      tick: this.appendOffset + Math.max(0, currentTick - this.startTick),
      controlId,
      value,
    });
  }

  timeline(
    mode: ElectropaintMode,
    compatibilityPolicy: CompatibilityPolicy,
    title = "Electropaint recording",
  ): TimelineV1 {
    const lastTick = this.events.at(-1)?.tick ?? 0;
    return {
      version: 1,
      mode,
      tickRate: TICK_RATE,
      compatibilityPolicy,
      events: this.events.map((event) => ({ ...event })),
      loop: { enabled: false, startTick: 0, endTick: Math.max(1, lastTick + 1) },
      metadata: { title, reconstructed: false },
    };
  }
}

export class TimelinePlayback {
  private nextEvent = 0;
  private active = false;

  constructor(public timeline: TimelineV1) {}

  start(engine: ElectropaintEngine): void {
    engine.reset(this.timeline.mode, this.timeline.compatibilityPolicy);
    this.nextEvent = 0;
    this.active = true;
  }

  continueLive(): void {
    this.active = false;
  }

  get isPlaying(): boolean {
    return this.active;
  }

  beforeStep(engine: ElectropaintEngine): void {
    if (!this.active) return;
    while (this.nextEvent < this.timeline.events.length) {
      const event = this.timeline.events[this.nextEvent];
      if (!event || event.tick > engine.tick) break;
      if (event.tick === engine.tick) engine.applyControlEvent(event);
      this.nextEvent += 1;
    }
  }

  afterStep(engine: ElectropaintEngine): void {
    if (!this.active || engine.tick < this.timeline.loop.endTick) return;
    if (!this.timeline.loop.enabled) {
      this.active = false;
      return;
    }
    this.start(engine);
    const start = this.timeline.loop.startTick;
    while (engine.tick < start) {
      this.beforeStep(engine);
      engine.step();
    }
  }
}

export function runTimeline(timeline: TimelineV1, ticks = timeline.loop.endTick): ElectropaintEngine {
  const engine = new ElectropaintEngine(timeline.mode, timeline.compatibilityPolicy);
  const playback = new TimelinePlayback({
    ...timeline,
    loop: { ...timeline.loop, enabled: false },
  });
  playback.start(engine);
  for (let tick = 0; tick < ticks; tick += 1) {
    playback.beforeStep(engine);
    engine.step();
    playback.afterStep(engine);
  }
  return engine;
}
