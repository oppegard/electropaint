import "./styles.css";
import { controlsForMode } from "./controls";
import { ElectropaintEngine, TICK_RATE } from "./engine";
import { iamralphtReconstructionForMode, reconstructionForMode } from "./reconstructed";
import { ElectropaintRenderer } from "./renderer";
import { TimelinePlayback, TimelineRecorder, validateTimeline } from "./timeline";
import type {
  CompatibilityPolicy,
  ControlDefinition,
  ElectropaintMode,
  SliderControlDefinition,
  TimelineEventValue,
  TimelineV1,
} from "./types";

const app = document.querySelector<HTMLElement>("#app");
if (!app) throw new Error("Electropaint application root is missing");

app.innerHTML = `
  <header class="masthead">
    <div>
      <p class="eyebrow">1986 / 2026</p>
      <h1>Electro<span>paint</span></h1>
      <p class="byline">by David A. Tristram · faithful browser reconstruction</p>
    </div>
    <div class="edition-switcher" aria-label="Session and historical edition">
      <label for="session">Session</label>
      <select id="session">
        <option value="showcase">Source showcase</option>
        <option value="elektropaintjs">Elektropaint.js screensaver</option>
        <option value="custom" hidden>Imported / custom</option>
      </select>
      <label for="mode">Edition</label>
      <select id="mode">
        <option value="classic">IRIS_4D · indexed</option>
        <option value="iris-gt">IRIS_GT · RGB</option>
      </select>
      <label for="policy">Compatibility</label>
      <select id="policy">
        <option value="corrected">Corrected</option>
        <option value="source">Source exact</option>
      </select>
    </div>
  </header>

  <section class="workspace">
    <div class="stage-shell">
      <div class="stage" id="stage">
        <canvas id="electropaint" width="400" height="400" aria-label="Animated Electropaint canvas"></canvas>
        <div class="webgl-message" id="webgl-message" role="status" hidden></div>
        <div class="stage-overlay">
          <span class="live-dot" aria-hidden="true"></span>
          <span id="playback-label">Reconstructed showcase</span>
          <span id="tick-label">000000</span>
        </div>
      </div>
      <div class="transport" aria-label="Timeline transport">
        <button type="button" id="record">Record</button>
        <button type="button" id="append">Append</button>
        <button type="button" id="record-stop">Stop rec</button>
        <button type="button" id="replay">Replay</button>
        <button type="button" id="continue">Continue</button>
        <button type="button" id="import">Import</button>
        <button type="button" id="export">Export</button>
        <button type="button" id="fullscreen">Full screen <kbd>F</kbd></button>
        <input id="import-file" type="file" accept="application/json,.json" hidden />
      </div>
      <p class="session-status" id="session-status" role="status"></p>
    </div>

    <aside class="control-panel" id="control-panel">
      <div class="panel-heading">
        <div>
          <p class="eyebrow">Panel</p>
          <h2>electro-paint</h2>
        </div>
        <button type="button" id="about">About</button>
      </div>
      <div id="controls"></div>
    </aside>
  </section>

  <footer>
    <p>Panel Library / Electropaint © 1986 David A. Tristram.</p>
    <p>Electropaint™ is a Registered U.S. Trademark of Tristram Visual. GPL-compatible reconstruction from the bundled C source.</p>
  </footer>

  <dialog id="about-dialog">
    <button class="dialog-close" type="button" aria-label="Close">×</button>
    <p class="eyebrow">About</p>
    <h2>Electropaint</h2>
    <p>Panel Library / Electropaint Copyright © 1986 David A. Tristram.</p>
    <p>Electropaint™ is a Registered U.S. Trademark of Tristram Visual.</p>
    <p>This browser edition is a source-led reconstruction. Its bundled autoplay timelines are new reconstructions, not recovered SGI screensaver scripts.</p>
    <p>The Elektropaint.js session reconstructs Ralph Thomas's 2013 WebKit interpretation with deterministic random walks and native WebGL squares.</p>
    <p><a href="https://www.tristram.com/" rel="noreferrer">Tristram Visual</a></p>
  </dialog>
`;

function required<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Required element ${selector} is missing`);
  return element;
}

const canvas = required<HTMLCanvasElement>("#electropaint");
const stage = required<HTMLElement>("#stage");
const controlPanel = required<HTMLElement>("#control-panel");
const controlsRoot = required<HTMLElement>("#controls");
const sessionSelect = required<HTMLSelectElement>("#session");
const modeSelect = required<HTMLSelectElement>("#mode");
const policySelect = required<HTMLSelectElement>("#policy");
const sessionStatus = required<HTMLElement>("#session-status");
const playbackLabel = required<HTMLElement>("#playback-label");
const tickLabel = required<HTMLElement>("#tick-label");
const webglMessage = required<HTMLElement>("#webgl-message");
const importFile = required<HTMLInputElement>("#import-file");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

let engine = new ElectropaintEngine("classic", "corrected");
let activeTimeline = structuredClone(reconstructionForMode("classic"));
let playback = new TimelinePlayback(activeTimeline);
const recorder = new TimelineRecorder();
let hasRecording = false;
let motionPaused = reducedMotion;
let renderRevision = 0;
let renderedRevision = -1;
let renderedTick = -1;

const renderer = new ElectropaintRenderer(canvas, (message) => {
  webglMessage.hidden = message === null;
  webglMessage.textContent = message ?? "";
  canvas.classList.toggle("unavailable", message !== null);
  renderRevision += 1;
});

function setStatus(message: string, kind: "normal" | "error" = "normal"): void {
  sessionStatus.textContent = message;
  sessionStatus.dataset.kind = kind;
}

function decimals(definition: SliderControlDefinition): number {
  const span = definition.max - definition.min;
  if (span <= 2) return 3;
  if (span <= 20) return 2;
  return 1;
}

function stepFor(min: number, max: number): string {
  const span = max - min;
  if (span <= 1) return "0.001";
  if (span <= 10) return "0.01";
  if (span <= 200) return "0.1";
  return "1";
}

function rangeInput(
  controlId: string,
  label: string,
  min: number,
  max: number,
  value: number,
  className = "",
): HTMLLabelElement {
  const wrapper = document.createElement("label");
  wrapper.className = `range-row ${className}`;
  const text = document.createElement("span");
  text.textContent = label;
  const input = document.createElement("input");
  input.type = "range";
  input.min = String(min);
  input.max = String(max);
  input.step = stepFor(min, max);
  input.value = String(value);
  input.dataset.controlId = controlId;
  const output = document.createElement("output");
  output.dataset.outputFor = controlId;
  output.textContent = value.toFixed(spanDecimals(min, max));
  wrapper.append(text, input, output);
  return wrapper;
}

function spanDecimals(min: number, max: number): number {
  const span = max - min;
  if (span <= 2) return 3;
  if (span <= 20) return 2;
  return 1;
}

function renderSlider(definition: SliderControlDefinition): HTMLElement {
  const state = engine.captureState().sliders[definition.id];
  if (!state) throw new Error(`Missing slider state for ${definition.id}`);
  const details = document.createElement("details");
  details.className = "compound-control";
  const summary = document.createElement("summary");
  summary.title = definition.description;
  const label = document.createElement("span");
  label.textContent = definition.label;
  const value = document.createElement("output");
  value.dataset.outputFor = `${definition.id}.value`;
  value.textContent = state.value.toFixed(decimals(definition));
  summary.append(label, value);
  details.append(summary);

  const body = document.createElement("div");
  body.className = "compound-body";
  body.append(
    rangeInput(`${definition.id}.value`, "value", definition.min, definition.max, state.value, "primary-range"),
    rangeInput(`${definition.id}.upper`, "upper", definition.min, definition.max, state.upper),
    rangeInput(`${definition.id}.lower`, "lower", definition.min, definition.max, state.lower),
    rangeInput(`${definition.id}.rate`, "rate", 0, (definition.max - definition.min) / 2, state.rate),
  );

  const actions = document.createElement("div");
  actions.className = "compound-actions";
  const mode = document.createElement("select");
  mode.dataset.controlId = `${definition.id}.mode`;
  mode.setAttribute("aria-label", `${definition.label} modulation mode`);
  for (const optionValue of ["bounce", "wrap"] as const) {
    const option = document.createElement("option");
    option.value = optionValue;
    option.textContent = optionValue;
    option.selected = state.mode === optionValue;
    mode.append(option);
  }
  const reset = document.createElement("button");
  reset.type = "button";
  reset.textContent = "Reset";
  reset.dataset.controlId = `${definition.id}.reset`;
  actions.append(mode, reset);
  body.append(actions);
  details.append(body);
  return details;
}

function renderControl(definition: ControlDefinition): HTMLElement {
  if (definition.kind === "slider") return renderSlider(definition);
  if (definition.kind === "puck") {
    const group = document.createElement("fieldset");
    group.className = "puck-control";
    const legend = document.createElement("legend");
    legend.textContent = definition.label;
    const surface = document.createElement("div");
    surface.className = "puck-surface";
    surface.tabIndex = 0;
    surface.setAttribute("role", "application");
    surface.setAttribute("aria-label", "Floating position puck; drag or use arrow keys");
    const cursor = document.createElement("span");
    cursor.className = "puck-cursor";
    cursor.setAttribute("aria-hidden", "true");
    surface.append(cursor);
    group.append(
      legend,
      surface,
      rangeInput(`${definition.id}.x`, "x", definition.min, definition.max, definition.defaultX),
      rangeInput(`${definition.id}.y`, "y", definition.min, definition.max, definition.defaultY),
    );
    return group;
  }
  if (definition.kind === "toggle") {
    const label = document.createElement("label");
    label.className = "toggle-control";
    label.title = definition.description;
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = definition.defaultValue;
    input.dataset.controlId = definition.id;
    const text = document.createElement("span");
    text.textContent = definition.label;
    label.append(input, text);
    if (definition.shortcut) {
      const key = document.createElement("kbd");
      key.textContent = definition.shortcut.toUpperCase();
      label.append(key);
    }
    return label;
  }
  return rangeInput(
    definition.id,
    definition.label,
    definition.min,
    definition.max,
    definition.defaultValue,
  );
}

function renderControls(): void {
  controlsRoot.replaceChildren();
  const definitions = controlsForMode(engine.mode);
  const puckSection = document.createElement("section");
  const togglesSection = document.createElement("section");
  const slidersSection = document.createElement("section");
  const colorsSection = document.createElement("section");
  puckSection.className = "control-section";
  togglesSection.className = "control-section toggle-grid";
  slidersSection.className = "control-section slider-grid";
  colorsSection.className = "control-section color-grid";

  for (const definition of definitions) {
    const control = renderControl(definition);
    if (definition.kind === "puck") puckSection.append(control);
    else if (definition.kind === "toggle") togglesSection.append(control);
    else if (definition.id.startsWith("hue-")
      || definition.id.startsWith("lightness-")
      || definition.id.startsWith("alpha-")
      || definition.id.startsWith("dwell-")
      || definition.id.startsWith("active-")
      || ["background-hue-rate", "channel-rate"].includes(definition.id)) {
      colorsSection.append(control);
    } else slidersSection.append(control);
  }
  controlsRoot.append(puckSection, togglesSection, slidersSection);
  if (colorsSection.childElementCount > 0) {
    const heading = document.createElement("h3");
    heading.textContent = "Color channels";
    colorsSection.prepend(heading);
    controlsRoot.append(colorsSection);
  }
  bindControls();
  syncControls();
}

function valueFromElement(element: HTMLInputElement | HTMLSelectElement | HTMLButtonElement): TimelineEventValue {
  if (element instanceof HTMLButtonElement) return true;
  if (element instanceof HTMLInputElement && element.type === "checkbox") return element.checked;
  if (element instanceof HTMLSelectElement) return element.value === "wrap" ? "wrap" : "bounce";
  return Number(element.value);
}

function handleControl(element: HTMLInputElement | HTMLSelectElement | HTMLButtonElement): void {
  const controlId = element.dataset.controlId;
  if (!controlId) return;
  const value = valueFromElement(element);
  if (!engine.apply(controlId, value)) return;
  renderRevision += 1;
  recorder.capture(engine.tick, controlId, value);
  if (recorder.isRecording) hasRecording = true;
  if (playback.isPlaying) {
    playback.continueLive();
    playbackLabel.textContent = "Custom session";
    sessionSelect.value = "custom";
  }
  syncControls();
}

function bindControls(): void {
  controlsRoot.querySelectorAll<HTMLInputElement>("input[data-control-id]").forEach((element) => {
    element.addEventListener("input", () => handleControl(element));
  });
  controlsRoot.querySelectorAll<HTMLSelectElement>("select[data-control-id]").forEach((element) => {
    element.addEventListener("change", () => handleControl(element));
  });
  controlsRoot.querySelectorAll<HTMLButtonElement>("button[data-control-id]").forEach((element) => {
    element.addEventListener("click", () => handleControl(element));
  });
  controlsRoot.querySelectorAll<HTMLElement>(".puck-surface").forEach((surface) => {
    const update = (event: PointerEvent): void => {
      const bounds = surface.getBoundingClientRect();
      const x = Math.max(-1, Math.min(1, ((event.clientX - bounds.left) / bounds.width) * 2 - 1));
      const y = Math.max(-1, Math.min(1, 1 - ((event.clientY - bounds.top) / bounds.height) * 2));
      applyPuck(x, y);
    };
    surface.addEventListener("pointerdown", (event) => {
      surface.setPointerCapture(event.pointerId);
      update(event);
    });
    surface.addEventListener("pointermove", (event) => {
      if (surface.hasPointerCapture(event.pointerId)) update(event);
    });
    surface.addEventListener("keydown", (event) => {
      const offsets: Record<string, [number, number]> = {
        ArrowLeft: [-0.05, 0],
        ArrowRight: [0.05, 0],
        ArrowDown: [0, -0.05],
        ArrowUp: [0, 0.05],
      };
      const offset = offsets[event.key];
      if (!offset) return;
      event.preventDefault();
      const x = Number(engine.getControlValue("position.x") ?? 0);
      const y = Number(engine.getControlValue("position.y") ?? 0);
      applyPuck(Math.max(-1, Math.min(1, x + offset[0])), Math.max(-1, Math.min(1, y + offset[1])));
    });
  });
}

function applyPuck(x: number, y: number): void {
  engine.apply("position.x", x);
  engine.apply("position.y", y);
  recorder.capture(engine.tick, "position.x", x);
  recorder.capture(engine.tick, "position.y", y);
  if (recorder.isRecording) hasRecording = true;
  if (playback.isPlaying) {
    playback.continueLive();
    playbackLabel.textContent = "Custom session";
    sessionSelect.value = "custom";
  }
  renderRevision += 1;
  syncControls();
}

function syncControls(): void {
  controlsRoot.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-control-id]").forEach((element) => {
    const controlId = element.dataset.controlId;
    if (!controlId) return;
    const value = engine.getControlValue(controlId);
    if (value === undefined) return;
    if (element instanceof HTMLInputElement && element.type === "checkbox") {
      element.checked = value === true;
    } else if (document.activeElement !== element) {
      element.value = String(value);
    }
  });
  controlsRoot.querySelectorAll<HTMLOutputElement>("output[data-output-for]").forEach((output) => {
    const controlId = output.dataset.outputFor;
    if (!controlId) return;
    const value = engine.getControlValue(controlId);
    if (typeof value === "number") {
      const baseId = controlId.split(".")[0] ?? "";
      const definition = controlsForMode(engine.mode).find((candidate) => candidate.id === baseId);
      const precision = definition?.kind === "slider" ? decimals(definition) : 3;
      output.value = value.toFixed(precision);
    }
  });
  const puckCursor = controlsRoot.querySelector<HTMLElement>(".puck-cursor");
  if (puckCursor) {
    const x = Number(engine.getControlValue("position.x") ?? 0);
    const y = Number(engine.getControlValue("position.y") ?? 0);
    puckCursor.style.left = `${(x + 1) * 50}%`;
    puckCursor.style.top = `${(1 - y) * 50}%`;
  }
  tickLabel.textContent = String(engine.tick).padStart(6, "0");
}

function startTimeline(timeline: TimelineV1, message?: string): void {
  activeTimeline = structuredClone(timeline);
  playback = new TimelinePlayback(activeTimeline);
  playback.start(engine);
  motionPaused = reducedMotion;
  playback.beforeStep(engine);
  engine.step();
  playback.afterStep(engine);
  renderRevision += 1;
  modeSelect.value = engine.mode;
  policySelect.value = engine.compatibilityPolicy;
  const isIamralpht = timeline.metadata?.profile === "iamralpht-elektropaintjs";
  sessionSelect.value = isIamralpht
    ? "elektropaintjs"
    : timeline.metadata?.reconstructed ? "showcase" : "custom";
  playbackLabel.textContent = isIamralpht
    ? "Elektropaint.js reconstruction"
    : timeline.metadata?.reconstructed
      ? "Reconstructed showcase"
      : timeline.metadata?.title ?? "Imported timeline";
  renderControls();
  controlsRoot.inert = isIamralpht;
  controlsRoot.setAttribute("aria-disabled", String(isIamralpht));
  controlPanel.classList.toggle("session-locked", isIamralpht);
  setStatus(message ?? (reducedMotion
    ? isIamralpht
      ? "Reduced motion is enabled; Ralph Thomas’s Elektropaint.js reconstruction is paused on its initial frame."
      : "Reduced motion is enabled; the reconstructed session is paused on its initial frame."
    : isIamralpht
      ? "Playing Ralph Thomas’s Elektropaint.js behavior as a deterministic reconstructed session. Choose Continue to return to live controls."
      : "Playing a deterministic reconstructed showcase at 60 Hz."));
}

function selectedReconstruction(mode: ElectropaintMode): TimelineV1 {
  const timeline = sessionSelect.value === "elektropaintjs"
    ? iamralphtReconstructionForMode(mode)
    : structuredClone(reconstructionForMode(mode));
  timeline.compatibilityPolicy = policySelect.value as CompatibilityPolicy;
  return timeline;
}

function switchMode(mode: ElectropaintMode): void {
  const timeline = selectedReconstruction(mode);
  startTimeline(timeline);
}

sessionSelect.addEventListener("change", () => switchMode(modeSelect.value as ElectropaintMode));
modeSelect.addEventListener("change", () => switchMode(modeSelect.value as ElectropaintMode));
policySelect.addEventListener("change", () => {
  const policy = policySelect.value as CompatibilityPolicy;
  const timeline = selectedReconstruction(engine.mode);
  timeline.compatibilityPolicy = policy;
  startTimeline(timeline, `Restarted ${engine.mode} in ${policy} compatibility mode.`);
});

function releaseReconstructionForLiveControls(): boolean {
  if (!engine.reconstructionProfile) return false;
  playback.continueLive();
  engine.reset(modeSelect.value as ElectropaintMode, policySelect.value as CompatibilityPolicy);
  sessionSelect.value = "custom";
  controlsRoot.inert = false;
  controlsRoot.setAttribute("aria-disabled", "false");
  controlPanel.classList.remove("session-locked");
  renderControls();
  renderRevision += 1;
  return true;
}

required<HTMLButtonElement>("#record").addEventListener("click", () => {
  releaseReconstructionForLiveControls();
  playback.continueLive();
  motionPaused = false;
  recorder.start(engine.tick, false);
  hasRecording = false;
  playbackLabel.textContent = "Recording";
  setStatus("Recording control events into a new TimelineV1.");
});

required<HTMLButtonElement>("#append").addEventListener("click", () => {
  releaseReconstructionForLiveControls();
  playback.continueLive();
  motionPaused = false;
  recorder.start(engine.tick, true);
  playbackLabel.textContent = "Appending recording";
  setStatus("Appending control events to the current recording.");
});

required<HTMLButtonElement>("#record-stop").addEventListener("click", () => {
  recorder.stop();
  playbackLabel.textContent = "Recording stopped";
  setStatus(hasRecording ? "Recording stopped and ready to export or replay." : "Recording stopped; no control events were captured.");
});

required<HTMLButtonElement>("#replay").addEventListener("click", () => {
  const timeline = hasRecording
    ? recorder.timeline(engine.mode, engine.compatibilityPolicy)
    : activeTimeline;
  recorder.stop();
  motionPaused = false;
  startTimeline(timeline, "Replaying TimelineV1 from its initial state.");
  motionPaused = false;
});

required<HTMLButtonElement>("#continue").addEventListener("click", () => {
  const restarted = releaseReconstructionForLiveControls();
  playback.continueLive();
  engine.apply("stop", false);
  renderRevision += 1;
  motionPaused = false;
  playbackLabel.textContent = "Live controls";
  setStatus(restarted
    ? "The prerecorded reconstruction ended; live controls restarted from the selected edition’s defaults."
    : "Timeline playback released; simulation is continuing from the current state.");
  syncControls();
});

required<HTMLButtonElement>("#import").addEventListener("click", () => importFile.click());
importFile.addEventListener("change", async () => {
  const file = importFile.files?.[0];
  importFile.value = "";
  if (!file) return;
  try {
    const parsed: unknown = JSON.parse(await file.text());
    const result = validateTimeline(parsed);
    if (!result.ok) {
      setStatus(`Import rejected: ${result.error} The current session was not changed.`, "error");
      return;
    }
    hasRecording = false;
    startTimeline(result.timeline, `Imported “${result.timeline.metadata?.title ?? file.name}”.`);
    motionPaused = false;
  } catch (error) {
    setStatus(`Import rejected: ${error instanceof Error ? error.message : String(error)}. The current session was not changed.`, "error");
  }
});

required<HTMLButtonElement>("#export").addEventListener("click", () => {
  const timeline = hasRecording
    ? recorder.timeline(engine.mode, engine.compatibilityPolicy)
    : activeTimeline;
  const blob = new Blob([`${JSON.stringify(timeline, null, 2)}\n`], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `electropaint-${engine.mode}-timeline-v1.json`;
  link.click();
  URL.revokeObjectURL(url);
  setStatus("Exported TimelineV1 JSON.");
});

required<HTMLButtonElement>("#fullscreen").addEventListener("click", () => {
  if (document.fullscreenElement) void document.exitFullscreen();
  else void stage.requestFullscreen();
});
document.addEventListener("fullscreenchange", () => { renderRevision += 1; });
window.addEventListener("resize", () => { renderRevision += 1; });

const aboutDialog = required<HTMLDialogElement>("#about-dialog");
required<HTMLButtonElement>("#about").addEventListener("click", () => aboutDialog.showModal());
required<HTMLButtonElement>(".dialog-close").addEventListener("click", () => aboutDialog.close());
aboutDialog.addEventListener("click", (event) => {
  if (event.target === aboutDialog) aboutDialog.close();
});

document.addEventListener("keydown", (event) => {
  const target = event.target;
  if (target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement) return;
  if (event.key.toLowerCase() === "f") {
    event.preventDefault();
    if (document.fullscreenElement) void document.exitFullscreen();
    else void stage.requestFullscreen();
    return;
  }
  if (engine.reconstructionProfile) return;
  const definition = controlsForMode(engine.mode).find(
    (candidate) => candidate.kind === "toggle" && candidate.shortcut === event.key.toLowerCase(),
  );
  if (definition?.kind !== "toggle") return;
  const current = engine.getControlValue(definition.id) === true;
  const value = !current;
  engine.apply(definition.id, value);
  renderRevision += 1;
  recorder.capture(engine.tick, definition.id, value);
  if (playback.isPlaying) playback.continueLive();
  playbackLabel.textContent = "Custom session";
  sessionSelect.value = "custom";
  syncControls();
});

document.addEventListener("visibilitychange", () => {
  lastFrame = performance.now();
  accumulator = 0;
  if (!document.hidden) setStatus("Simulation resumed without a hidden-tab catch-up jump.");
});

let lastFrame = performance.now();
let accumulator = 0;
const fixedMilliseconds = 1000 / TICK_RATE;
let controlSyncCounter = 0;

function frame(now: number): void {
  const elapsed = Math.min(now - lastFrame, 250);
  lastFrame = now;
  if (!document.hidden && !motionPaused) {
    accumulator += elapsed;
    let steps = 0;
    while (accumulator >= fixedMilliseconds && steps < 8) {
      playback.beforeStep(engine);
      engine.step();
      playback.afterStep(engine);
      accumulator -= fixedMilliseconds;
      steps += 1;
    }
    if (steps === 8) accumulator = 0;
  }
  if (renderer.available && (renderedTick !== engine.tick || renderedRevision !== renderRevision)) {
    renderer.render(engine.renderData());
    renderedTick = engine.tick;
    renderedRevision = renderRevision;
  }
  controlSyncCounter = (controlSyncCounter + 1) % 6;
  if (controlSyncCounter === 0) syncControls();
  requestAnimationFrame(frame);
}

startTimeline(activeTimeline);
if (import.meta.env.DEV) {
  window.addEventListener("electropaint-test-advance", (event) => {
    const requested = event instanceof CustomEvent && typeof event.detail === "number"
      ? Math.max(0, Math.trunc(event.detail))
      : 0;
    motionPaused = true;
    for (let index = 0; index < requested; index += 1) {
      playback.beforeStep(engine);
      engine.step();
      playback.afterStep(engine);
      renderer.render(engine.renderData());
    }
    renderedTick = engine.tick;
    renderedRevision = renderRevision;
    syncControls();
  });
}
requestAnimationFrame(frame);
