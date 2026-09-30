# Electropaint for macOS

A native ScreenSaver bundle running David Tristram's 1994 “mello” default
script, rendered through Metal. It starts immediately and has no settings.
Requires macOS 11 or later and a Metal-capable Mac. Both Apple Silicon and
Intel slices are built; Intel execution still needs testing on Intel hardware.

## Build and install

Install Apple's Command Line Tools (`xcode-select --install`) if needed, then:

```sh
bash macos/build.sh
open 'macos/build/Electropaint Preview.app'
```

Double-click `macos/build/Electropaint.saver` to install through macOS, then
select Electropaint in System Settings → Screen Saver. The build uses an
ad-hoc signature for local use. It is not Developer ID signed or notarized;
downloaded copies may require approval through macOS Privacy & Security.

The preview application runs the same ScreenSaverView and Metal renderer.
Resizing its window changes the projection without restarting the script.
The screensaver pauses on stop and resumes on start. Each view owns its
animation state; there is no customization sheet, alternate session, or key
binding to change the animation.

## Source fidelity

The authority is the typed ElectroPortis decompilation, pinned to
[`8a8d165f28dc267491fd0bac0d2c5fae54e8587c`](https://github.com/bslabs/electroportis/tree/8a8d165f28dc267491fd0bac0d2c5fae54e8587c).
`vendor/ep.c` and `vendor/ep.h` are byte-for-byte upstream files. The default
script is embedded in that C file; this build executes its original parser,
actuator code, history, HLS conversion, and drawing sequence directly.

`EPAdapter.c` intercepts the graphics interface and emits Metal vertices.
It swaps every mutable engine global under a mutex to isolate the original
heap graph per view, frees that graph on destruction, and supplies a per-view
48-bit random generator equivalent to `srand48`/`drand48`. Production seeds
use time, as upstream does; tests use zero, as upstream's `TEST` build does.
The native graphics shim and empty platform header replace upstream's
OpenGL-dependent headers. No changes to the preserved engine are required.

The original harness advances one simulation frame per display invocation,
without a fixed wall-clock rate. This version schedules at 60 Hz, with at most
eight ticks after a delayed callback. It retains the binary's 300-degree GLU
projection (an inverted 60-degree view at distance four) and zero-size mirror
copies, which are discarded before submitting Metal lines. Depth testing,
culling, blending, and antialiasing remain disabled. OpenGL clip depth is
converted to Metal's range; fills are triangulated and outlines use one
physical-pixel native lines. Rasterization edge coverage can differ from
historical OpenGL hardware.

The shipped one-wing presentation differs from the restored four-wing mode
offered by the [sgi-demos reference](https://github.com/sgi-demos/sgi-demos/tree/main/demos/ep-1994-ogl-decomp).
This screensaver preserves the shipped presentation.

Preserved SHA-256 values:

```text
fa0287ce4b03e9fdd4537620dc5f0ee95dc4c154162f1cfd000471a56243fc28  ep.c
a30ed159d0a74c33a0677b3d638d4265f1dd0743a4cd66ce647463bdbfe59c70  ep.h
11156627907032592a75d0a3e4f7ed5d451f51960389a7911ed33227236f6026  LICENSE.md
```

## Verification

```sh
bash macos/test.sh
bash macos/build.sh
bash macos/smoke-test.sh
shellcheck macos/build.sh macos/test.sh macos/smoke-test.sh
npm test
npm run build
```

The engine test uses AddressSanitizer and UndefinedBehaviorSanitizer over
12,000 frames with interleaved independent views, aspect changes, and repeated
allocation/destruction. The independent reference test compiles the unchanged
engine with libc's RNG and native OpenGL matrices; it compares all ordered
geometry and colors for 12,000 frames. OpenGL is used only by this test oracle,
and is not linked into the screensaver or preview app.

GitHub Actions builds universal bundles on pull requests and pushes to `main`.
Updates to `main` after merging a PR update the
[`latest` prerelease](https://github.com/oppegard/electropaint/releases/tag/latest)
with screensaver/preview ZIPs and SHA-256 checksums. The rolling tag follows the source commit of the
last successful publishing run; release notes link to that exact source.
Pull requests upload workflow artifacts without changing the prerelease.
For PRs from this repository, a bot maintains a download comment linking to
the latest successful build for the current commit. Artifacts expire after
14 days and require GitHub sign-in. Fork PRs retain the run-summary download
link; their read-only tokens cannot post the comment.
Publishing verifies that the main commit belongs to a merged PR; direct
pushes to main build artifacts but do not update the prerelease.
Hosted builds use `bash macos/test.sh --engine-only` because GPU/OpenGL access
is not guaranteed. The full reference and native smoke checks remain local.

The bundle smoke test checks actual principal-class loading, Metal shader
compilation, preview/full-size view initialization, resize and restart. System
Settings installation, lock-screen operation, multiple physical displays,
sleep/wake and Intel execution require manual testing on the respective host.

## Licensing

[`LICENSE`](LICENSE) records the project code's GPL-2.0-only terms and preserves
the historical source's custom notices. The unchanged upstream notice remains
in [`vendor/LICENSE.md`](vendor/LICENSE.md). Both built bundles include the
macOS notice as `LICENSE`, the upstream notice as `LICENSE.md`, and the full
GPL text as `GPL-2.0.txt` in `Contents/Resources`.

The historical code is not relicensed under the GPL. Its ownership, sale and
source-sharing statements require clarification from the rights holder before
claiming GPL-compatible redistribution rights for the combined executable;
including license files alone does not resolve that issue.
