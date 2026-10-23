# Refresh-independent native Electropaint animation

Status: approved by the user on 2026-09-30; implemented on
`feat/macos-display-refresh`, created from refreshed main after PR #3 merged.

## Goal

Automatically render smoothly at the display's available refresh rate,
including 120 Hz ProMotion and supported external monitors, while preserving
the current 60 Hz simulation speed and the 1994 default script. Add no settings
or alternate animation mode.

## Evidence and fidelity boundary

The current ScreenSaverView requests callbacks every 1/60 second. Its accumulator
already keeps simulation at 60 Hz, but it only renders when a simulation step
occurs; requesting faster callbacks alone would repeat frames rather than smooth
motion. Preview.m also drives frames with a separate 60 Hz timer.

The preserved C draw routine uses `twixt__GiPff` to interpolate history samples
and `foldtwixt__GiPffT3` for wrapped angles/HLS components. Script updates,
actuator updates, random consumption and history insertion occur in
`display__Gv`, independently of those draw helpers. `wheel` is a global rotation
updated by the simulation and also needs interpolation. Fill/outline flags
are discrete state and must change on canonical simulation boundaries.

The original harness did not establish a fixed wall-clock frame rate. Our
existing 60 Hz port is the playback-speed baseline. Extra interpolated images
cannot be described as pixel-identical historical frames: those frames did not
exist. The achievable contract is unchanged canonical 60 Hz drawing/sequence
behavior, additional source-based intermediate poses, and refresh-independent
elapsed-time playback.

Sources:

- Apple's fixed rates and ProMotion up to 120 Hz:
  https://support.apple.com/en-gb/102297
- Supported external resolutions/rates vary by Mac, monitor and connection:
  https://support.apple.com/en-us/122212
- Display-synchronized Metal scheduling:
  https://developer.apple.com/documentation/quartzcore/cametaldisplaylink

## Proposed changes

- Separate simulation advance from read-only rendering in the native adapter.
  Retain the unchanged vendored C files and the existing step API for the
  independent source oracle.
- Keep the script, RNG, actuator updates and history at exactly 60 simulation
  steps per second of uninterrupted playback. Drawing extra frames must not
  change any of that state.
- Buffer adjacent canonical drawing states and interpolate their source
  parameters before rebuilding transforms and HLS colors. Reuse the source's
  interpolation and wrap conventions rather than blending rendered images or
  deforming transformed screen-space vertices. Interpolate global wheel
  rotation as well. Preserve discrete outline/fill transitions.
- Use a consistent one-step presentation buffer if needed to obtain both
  interpolation endpoints without extrapolation. Document its approximately
  16.7 ms startup/presentation delay; it must not change ongoing animation speed.
  Prove canonical-frame equivalence after accounting for that fixed delay.
- Use CAMetalDisplayLink on macOS 14 and later, tied to the view's Metal layer,
  and an appropriate display-synchronized fallback for macOS 11–13. Drive
  both the screensaver and preview through this single scheduling owner.
  Avoid running the host animation callback and an independent preview timer
  as additional frame drivers.
- Use display presentation timestamps and actual elapsed time, rather than
  assuming the display is an integer multiple of 60 Hz. Handle variable refresh,
  59.94 Hz and nonmultiples such as 144 Hz without changing simulation speed.
- Track display changes and resizing. Bound work after stalls, pause/resume
  without large catch-up bursts, and coalesce/drop obsolete callbacks. Keep
  GPU submissions and view lifetimes safe during stop and destruction.
- Update documentation and the new PR's implementation plan with the
  fidelity contract, scheduling behavior and hardware validation limits.

## Verification

- Keep the 12,000-frame original C/OpenGL oracle passing for canonical frames.
- Compare interpolated endpoints with their corresponding canonical frames,
  including startup, angle/hue wrapping, outlines and phase transitions.
- Prove that extra renders leave simulation state, RNG and future canonical
  frames unchanged, including interleaved independent views.
- Feed synthetic timestamp streams at 47.95, 48, 50, 59.94, 60, 75, 120, 144,
  165 and 240 Hz, plus changing rates and delayed callbacks. Verify equal
  elapsed time yields equal simulation advancement and more intermediate
  images at high rates. Test stop/resume and bounded catch-up separately.
- Build universal bundles, run sanitizers and native lifecycle checks, and
  verify the PR build/artifact path. Validate actual smooth presentation on
  high-refresh hardware when available; do not claim physical 120 Hz support
  was observed from synthetic tests alone.

## Checklist

- [x] Inspect current scheduling and preserved interpolation helpers.
- [x] Verify Apple refresh-rate and display-link documentation.
- [x] Obtain approval of this plan before coding.
- [x] Separate fixed-step simulation and source-based interpolated rendering.
- [x] Add display-synchronized lifecycle and preview scheduling.
- [x] Verify canonical fidelity and refresh-independent timing.
- [x] Document hardware limits, update PR, and commit/push the change.

## Implementation and evidence

- Added a fixed-step clock and an independent read-only render API. The first
  frame holds until there are two endpoints; subsequent presentation buffers
  one step. Drawing reuses the original history and wrap interpolation helpers.
- Metal display links own rendering on macOS 14+, paused across stop/start.
  Monitor changes update the frame-rate request. macOS 11–13 uses coalesced
  CoreVideo callbacks delivered to the main thread. A timer covers detached
  views or display-link initialization failures; the preview timer was removed.
- CPU sanitizers passed the timing streams and 12,000 endpoint/purity pairs,
  including interleaved views and resized renders. The unchanged 12,000-frame
  OpenGL oracle passed with exact colors/draw order and maximum clip-coordinate
  error 1.1920929e-05. Vendored C and header hashes remain unchanged.
- Universal arm64/x86_64 bundle builds, actionlint and shellcheck passed.
- Native tests exercise Metal callbacks, duplicate host suppression, resize,
  detach, stop/restart and view release. The 2026-09-30 local display session was locked.
  A minimal standalone Metal application confirmed the same three initial
  callbacks followed by suspension; GPU commands completed without error.
  The unlocked-session follow-up below verifies continuous/resumed callbacks.
  Physical high-refresh playback, macOS 11–13 and Intel runtime behavior
  remain hardware validation items.
- Metal callbacks follow Apple's supplied-drawable presentation contract:
  commit rendering work, then present before the display-link deadline.
  https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:)

## Unlocked hardware validation — 2026-10-01

- Re-ran the native lifecycle suite with the session unlocked. Continuous
  Metal callbacks and resumed callbacks passed without the locked-session
  skips, along with resizing, detach/fallback, duplicate host suppression,
  stop/restart and view release.
- Measured the downloaded PR artifact built from
  `f669b3c832e2977d23c6fe198aca1a63443375e8` on the Built-in Retina Display,
  which reports a maximum of 60 Hz. A three-second run recorded 178 drawing
  callbacks, approximately 59.23 Hz across their target timestamps, and 171
  positive-time drawable presentation notifications before sampling.
- The user confirmed smooth motion, correct window resizing and Command-Q
  behavior in the downloaded artifact's preview app. This display cannot
  establish physical 120 Hz playback; higher-rate, macOS 11–13 and Intel
  hardware checks remain outstanding.

## Merge-conflict repair — 2026-10-01

- Integrate main's preview controls and primary-display screensaver restriction
  without restoring its separate preview timer or replacing the refresh driver.
- Apply display selection in the shared timestamp-rendering path. Secondary
  and unresolved displays render black and pause the clock; previews remain
  exempt. Preserve both suites of lifecycle and display-selection checks.
- [x] Confirm PR conflict and inspect both branch histories.
- [x] Resolve renderer, smoke-test and documentation conflicts.
- [x] Verify universal build and combined native smoke checks.
- [x] Commit and push the merge resolution.
- Verification passed: universal arm64/x86_64 build, combined native lifecycle
  and primary/secondary/unknown display tests, shellcheck, actionlint and
  `git diff --check`. Controlled display tests use the fallback driver and
  restore real screen objects before AppKit event processing.
