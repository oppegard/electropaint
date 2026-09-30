# Native macOS Electropaint screensaver

Status: approved by the user on 2026-09-30; implementation and automated
verification complete on branch `feat/macos-screensaver`. Manual system-host
and visual acceptance checks remain.

## Goal

Deliver an installable `Electropaint.saver` that plays the 1994 default
“mello” script immediately, with no customization or configuration sheet.
Preserve the shipped 1994 animation and presentation, including its single
visible wing and accidental wide, flipped camera.

## Authority and rationale

Use the preserved 1994 C decompilation as behavioral truth:
https://github.com/sgi-demos/sgi-demos/tree/main/demos/ep-1994-ogl-decomp

That archive documents the provenance through Brendan Shanks's typed
ElectroPortis fork and drvink's decompilation. Pin the upstream revision,
preserve notices, and document the exact files and any necessary adaptations.
The older `igl_0.1.8/` material remains historical context, but must not
override behavior specific to the 1994 binary.

Prefer compiling the preserved C animation engine behind a small native
adapter. Its GL abstraction should emit ordered primitives and transforms
for Metal rendering. If inspection shows that this separation requires
substantial source changes, record the evidence and revise this plan before
substituting a rewritten engine. The current TypeScript implementation is a
secondary comparison, not an oracle.

Use Apple's ScreenSaver framework and Metal with no third-party production
dependencies. Avoid depending on a browser host or deprecated OpenGL for
the delivered screensaver.

## Proposed changes

- Add a self-contained `macos/` implementation with a ScreenSaverView
  subclass, native C adapter, Metal renderer, bundle metadata, and preserved
  source/provenance. Leave the browser product available.
- Preserve script initialization, actuator order, random-number behavior,
  sequence timing, history indexing, transform order, HLS conversion,
  geometry, outlines, draw order, and shipped projection directly from C.
- Establish animation cadence from the original harness; explicitly
  document any wall-clock scheduling needed by the macOS host. Prevent
  bursts of catch-up work after sleep or host suspension.
- Render black backgrounds, source-equivalent fills and complementary
  outlines with Retina sizing, aspect-correct projection, and resize support.
- Give each screensaver view its own animation state and rendering resources;
  inspect original global state before defining how independent views are
  isolated. Handle preview, start/stop, and multiple displays without leaking
  timers or GPU resources.
- Provide command-line build and verification scripts for Apple Silicon and
  Intel, using the installed macOS SDK. Add a small native preview app to
  exercise the same view outside the system screensaver host.
- Document build, installation, preview, supported macOS versions, licensing,
  and signing limitations. Produce a locally usable build; distribution
  signing/notarization is outside this initial scope.

## Validation

- Compare adapter output with the preserved C under a fixed test seed over
  initialization and long runs that cross slow/fast script phase changes.
  Check ordered geometry, colors, transforms, and projection, not only a
  handful of animation snapshots.
- Build the `.saver` bundle and validate its principal class, architecture,
  metadata, and framework loading. Build the preview application.
- Exercise preview, resizing, stop/restart, and independent views. Visually
  compare against the shipped 1994 reference presentation when possible.
- Run existing browser tests/build to confirm repository integration.
- State explicitly any system-host, hardware, or architecture checks that
  cannot be performed on this machine. It currently has Command Line Tools
  but no full Xcode installation.

## Task checklist

- [x] Inspect repository, current 1994 reconstruction, and source provenance.
- [x] Check local native build tools and write this plan.
- [x] Obtain user approval of this plan before coding.
- [x] Inspect and pin the authoritative 1994 source; record source mapping.
- [x] Implement the C adapter and source-based regression verification.
- [x] Implement the Metal renderer and screensaver lifecycle.
- [x] Add bundle build scripts and native preview application.
- [x] Verify native artifacts, animation fidelity, and browser checks.
- [x] Document installation and validation results; deliver `.saver` artifact.

## Implementation evidence and adaptations

The sgi-demos path returned HTTP 404 when downloading its source. The typed
upstream it credits remains available: `bslabs/electroportis`, pinned at
`8a8d165f28dc267491fd0bac0d2c5fae54e8587c`. The engine and public header are
vendored unchanged with hashes and notices recorded in `macos/README.md`.

The original global state is swapped under a mutex; each view owns its C heap
graph and equivalent 48-bit RNG. No engine rewrite was necessary. The GL
interface is replaced by a matrix/primitive adapter and Metal rendering.
The original GLUT harness has no fixed time rate; this host uses 60 Hz and
bounds catch-up to eight ticks. The screensaver retains the shipped camera
and collapsed mirrors. Native outlines are one physical pixel.

Verification on this Apple Silicon Mac:

- AddressSanitizer/UndefinedBehaviorSanitizer: 12,000 frames with interleaved
  independent views and aspect changes, plus 100 allocation/destruction cycles.
- Independent original OpenGL path: 12,000 frames, exact colors and ordered
  batches; maximum clip-coordinate error `1.1920929e-05`.
- Universal arm64/x86_64 saver and preview build; plist and ad-hoc signature
  validation pass. Linked frameworks confirm OpenGL is absent from the product.
- Actual bundle loading and Metal shader compilation pass, along with
  preview/full-size initialization, resize and stop/restart checks. This check
  required running outside the sandbox to access the Metal device.
- ShellCheck, 20 existing browser tests, browser production build and
  `git diff --check` pass.

Artifacts: `macos/build/Electropaint.saver` and
`macos/build/Electropaint Preview.app` (ignored build outputs).

Visual UI inspection could not proceed because the Mac is locked. The preview
app was launched successfully, but its pixels were not inspected. Installation
and operation through System Settings, lock screen, physical multiple displays,
sleep/wake, Intel hardware and older supported macOS releases remain manual
acceptance checks. The smoke test is not a substitute for those checks.

## Requested release automation

The user requested committing and pushing this branch and adding GitHub
Actions builds that publish a prerelease named `latest`.

- Build universal macOS artifacts on macOS 15 with read-only repository access.
- Run CPU sanitizer checks without requiring a hosted runner GPU; retain the
  full OpenGL comparison and Metal smoke checks for local verification.
- Package both bundles with macOS `ditto` to preserve executable permissions
  and signatures, and publish ZIPs plus SHA-256 checksums.
- Publish only on pushes to `main` after merge. Pull requests build only;
  implementation-branch pushes and manual dispatch do not publish.
  Verify the main SHA against merged PR metadata before publishing, so direct
  pushes to main cannot publish a prerelease.
- Isolate publishing in a job with `contents: write`; serialize updates to the
  rolling `latest` tag and prerelease, with source SHA in the release notes.

Checklist:

- [x] Add build/packaging/prerelease workflow and document its triggers.
- [x] Validate with Actionlint, ShellCheck and local packaging checks.
- [x] Commit and push the implementation and workflow.
- [x] Check the PR workflow run; publishing requires the user's merge to main.

The initial unsigned implementation commit was pushed with HTTPS/GitHub CLI
authentication after the configured SSH/1Password signing agent failed.
Git signing settings remain unchanged. Actionlint, ShellCheck, CPU sanitizer
checks and ZIP/checksum packaging checks pass. The merged-PR publishing gate
was checked against the existing PR #2 merge metadata.

Draft PR #3's macOS build and Linux checks passed. The macOS workflow uploaded
the saver/preview ZIPs and checksums as `electropaint-macos`, with 14-day
retention. Its publish job was skipped as intended. No prerelease was created
by the PR run; the first publication awaits a merge to main.

## macOS license notice

At the user's request, added `macos/LICENSE` to record GPL-2.0-only coverage
for the native code and preserve the custom historical notices verbatim.
Both saver and preview bundles include it alongside the unchanged upstream
notice and complete GPL text. This documents the existing terms; it does
not resolve compatibility between the custom upstream terms and the GPL.

## PR artifact download links

At the user's request, expose the upload action's artifact URL in the run
summary and a single maintained PR comment. Keep build permissions read-only;
use a separate comment job with only PR write permission for same-repository
PRs. Skip comments for outdated commits or closed PRs. Fork PRs retain the
run-summary link. Retention remains 14 days, and downloads require sign-in.

## Icon and downloaded-build instructions

At the user's request, add a reproducible neon square-spiral icon generated
with AppKit, package a full-resolution `.icns` in both bundles, and set their
bundle icon metadata. Document Apple's per-app Open Anyway flow for the
ad-hoc signed, unnotarized download. Do not change system security settings.

Local validation: inspected the generated 1024-pixel icon, built all ten iconset
sizes into ICNS, and verified the icon metadata and resource in both bundles.
Universal builds, signature checks, ShellCheck and whitespace checks pass.

## Preview app quit command

At the user's request, install the standard application menu with a
`Quit Electropaint` item and Command-Q shortcut targeting NSApplication's
termination action. The existing termination handler stops the timer and saver.

## Build ZIP names

At the user's request, suffix downloadable ZIPs and the Actions artifact name
with the checked-out commit's seven-character SHA. Include `latest` in main
prerelease names. Propagate the artifact name between upload/download jobs,
regenerate checksums and release notes, and identify the actual build SHA in
the PR comment. Remove only older generated latest ZIPs after a successful
prerelease replacement to retain the rolling release's existing behavior.

PR builds now explicitly check out the PR head commit, rather than GitHub's
synthetic test merge. The filename and download comment identify that single
actual build SHA.

- [x] Package both bundles in one ZIP and upload without an additional
  archive wrapper, preserving executable permissions.
