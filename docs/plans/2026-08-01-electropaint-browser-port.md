# Faithful Electropaint Browser Port

## Summary

Create a standalone static site under `web/` using TypeScript, native WebGL2,
Vite, and no production runtime dependencies. The bundled Electropaint C
sources remain the behavioral authority.

The demo will:

- Autoplay a clearly labeled reconstructed showcase.
- Default to classic IRIS_4D mode and offer IRIS_GT mode.
- Reproduce all original controls and keyboard shortcuts in a modern desktop
  layout.
- Support current Chrome, Firefox, Safari, and Edge.
- Include fullscreen operation and modern JSON recording/replay.

## Implementation

### Fidelity model and animation engine

- Translate the original constants, defaults, 128-entry history buffer,
  interpolation, angle wrapping, slider modulation, matrix order, and four-way
  mirrored triangle construction into a deterministic TypeScript engine.
- Run simulation at a fixed 60 Hz using the source's port-adjusted default
  speed of `0.05`; render independently with `requestAnimationFrame`. Pause
  hidden tabs without catch-up jumps.

  > **Implementation note — change:** The fixed-step loop processes at most
  > eight overdue ticks per animation frame and then discards any remaining
  > accumulator instead of attempting an unbounded catch-up. The original plan
  > only called out hidden-tab catch-up; the cap also prevents a long foreground
  > frame from causing a spiral of work and a visible burst of animation.

  > **Implementation note — change:** Rendering is skipped while neither the
  > engine tick nor a render-affecting UI revision has changed. The original
  > wording treated rendering as independent and side-effect-free, but smear,
  > smooth, and fade advance the ping-pong framebuffer on every render. Gating
  > those renders keeps stopped and reduced-motion frames visually frozen.

- Implement every compound slider with value, upper/lower bounds, modulation
  rate, wrap/bounce mode, and reset behavior. Mode switches reset to that
  edition's original defaults.

  > **Implementation note — change:** Reset is a two-stage operation for wheel,
  > spin, and flip. The first press restores the compound slider and its bounds;
  > if the slider is already at its default, a second press clears the derived
  > accumulated transform. A simple one-stage reset was initially implied, but
  > this behavior is required by the source and avoids unexpectedly discarding
  > the accumulated pose on the first press.

- Add `corrected` and `source` compatibility policies. The sole initial
  correction is drawing the missing outline on the first mirrored triangle;
  source mode preserves the omission. Do not make other speculative visual
  corrections.
- Preserve the original square embedded viewport and use its aspect-adjusted
  projection in browser fullscreen.

### WebGL2 renderer

- Implement the fixed-function transformation pipeline explicitly with shaders
  and source-equivalent projection, depth, alpha blending, lighting, and HLS
  conversion.
- Classic mode reproduces the 128-color spectrum map, indexed color stepping,
  complementary background, fill/outline/fat-line modes, smear, smooth, and the
  original 16-step 4x4 stippled fade.
- IRIS_GT reproduces RGB/alpha rendering, two directional lights, material
  controls, depth buffering, ribbons, and five hue/light channels with dwell
  and active-channel selection.
- Use explicit edge geometry for one- and three-pixel outlines because native
  WebGL line widths vary by browser.
- Use ping-pong framebuffers for source-equivalent clear, accumulation, smear,
  smooth, and fade behavior.

  > **Implementation note — change:** Each ping-pong framebuffer also owns a
  > depth renderbuffer. Treating the targets as color-only would make IRIS_GT
  > depth testing operate against the default framebuffer rather than the scene
  > being accumulated, so depth had to move into the same offscreen targets as
  > color.

- Restore renderer state after WebGL context loss; show an explanatory fallback
  when WebGL2 is unavailable.

  > **Implementation note — change:** Context recovery recreates shaders,
  > buffers, textures, and renderbuffers, then redraws from the current
  > deterministic engine state. It does not preserve the pre-loss smear/fade
  > texture. The original plan's literal renderer-state restoration is not
  > possible for GPU-only accumulation after the browser invalidates the WebGL
  > context; rebuilding the current scene provides deterministic recovery and
  > accumulation resumes from there.

### Controls and playback

- Present the canvas beside a modern control panel while retaining original
  labels, ranges, defaults, puck behavior, reset buttons, and shortcuts.

  > **Implementation note — change:** The legacy puck is represented by a
  > floating browser-native pointer surface backed by explicit `position.x` and
  > `position.y` controls, with arrow-key adjustment added for keyboard access.
  > Recreating the Panel Library's pointer-coordinate/actuator plumbing would
  > conflict with stable timeline IDs and would not provide an accessible
  > browser control, while the resulting two-axis behavior remains equivalent.

- Expose only controls belonging to the selected historical edition; include
  About and source/trademark attribution.
- Define a versioned `TimelineV1` JSON format containing mode, 60 Hz tick rate,
  compatibility policy, ordered control events, and loop metadata.

  > **Implementation note — change:** Import validation was expanded from
  > structural validation to atomic semantic validation. Event values must match
  > the target control's type and range, events must be ordered and fall within
  > the loop bounds, and control IDs must belong to the selected edition. This
  > prevents a structurally valid import from being partially clamped or applied
  > before a later incompatible event is discovered.

- Support record, append, stop, replay, continue, import, and export using
  stable control IDs rather than legacy pointer coordinates or actuator
  indexes.

  > **Implementation note — change:** The historical `stop` control freezes
  > simulation state but still increments timeline ticks. Freezing the timeline
  > clock as well, as a literal stop might suggest, deadlocks playback because a
  > later `stop: false` event can never be reached. Recording stop remains a
  > separate transport action and does not freeze the simulation.

- Ship separate deterministic reconstructed timelines for classic and IRIS_GT
  modes. Autoplay the selected mode's timeline and visibly identify it as a
  reconstruction.
- Respect `prefers-reduced-motion` by rendering the initial frame paused instead
  of autoplaying.

  > **Implementation note — change:** The reduced-motion initial frame is tick
  > 1, after applying tick-0 reconstruction events and performing one fixed
  > simulation step, rather than the empty tick-0 engine state. This produces a
  > representative first Electropaint frame while still preventing autoplay.

## Interfaces

- `ElectropaintMode`: `classic | iris-gt`
- `CompatibilityPolicy`: `corrected | source`
- `ControlDefinition` and `ModulatedSliderState`: authoritative IDs, ranges,
  defaults, shortcuts, and modulation state.
- `ElectropaintEngine`: reset, fixed-step update, apply control event, capture
  state, and produce render data.
- `TimelineV1`: validated, versioned recording format; malformed or incompatible
  imports report an error without changing the current session.

The final Vite build must use relative asset paths and require no backend,
making `dist/` deployable to GitHub Pages or any static host.

## Test Plan

- Generate checked-in numeric fixtures from a small test-only C reference
  harness for interpolation, angle folding, slider animation, palette
  conversion, and representative transformed vertices.
- Unit-test source defaults, all control ranges, wrap/bounce boundaries,
  ring-buffer rollover, mode resets, color conversion, timeline validation,
  recording, and deterministic replay.
- Use Playwright at a fixed 400x400 viewport and device-pixel ratio of 1 for
  per-browser visual snapshots covering defaults, motion, fill/outline, fat
  lines, fade/smear, colored background, IRIS_GT alpha/lighting, ribbons, and
  depth.

  > **Implementation note — change:** Playwright uses a 1200x900 page viewport
  > at device-pixel ratio 1, while the canvas under assertion is forced to an
  > exact 400x400 capture. A 400x400 page viewport could not contain the desktop
  > controls and made layout changes affect the rendering baseline; isolating
  > the canvas preserves the intended 400x400 visual comparison.

  > **Implementation note — change:** The browser matrix is Chromium, Firefox,
  > and WebKit. Chromium covers the rendering engine shared by current Chrome
  > and Edge, while WebKit is the automatable proxy for Safari. This replaces
  > separate branded Chrome, Edge, and Safari runs with reproducible engine-level
  > coverage available through Playwright.
- Compare appearance against the archived Electropaint screenshots; use
  source-derived numeric fixtures as the stronger authority where compressed
  screenshots are ambiguous.
- Verify fullscreen entry/exit, keyboard shortcuts, visibility pause/resume,
  reduced-motion startup, context recovery, malformed imports, and WebGL2
  failure messaging.
- Acceptance requires identical engine/render data for repeated timeline runs,
  source-mode numeric agreement with fixtures, approved browser snapshots, and
  a clean production build with no console errors.

## Assumptions

- Classic IRIS_4D is the default historical edition; IRIS_GT is an alternate
  mode.
- Desktop mouse and keyboard are required; mobile and touch-specific UX are out
  of scope.
- The missing SGI screensaver script will not be represented as recovered. Both
  bundled showcase timelines are explicitly described as reconstructions.
- GLectric and Sonik are historical references only and will not contribute
  algorithms to the Electropaint port.
- The port remains GPL-compatible and retains David A. Tristram's Electropaint
  copyright and trademark notices.
- Deployment infrastructure is out of scope; the deliverable is
  deployment-ready static output.
