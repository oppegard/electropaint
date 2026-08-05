# Electropaint — browser reconstruction

Electropaint is a kinetic graphics program built from repeating triangles,
layered transformations, color, and time. This repository is a source-led port
of Electropaint to TypeScript and native WebGL2, designed to run as a standalone
static site in a current browser with no production runtime dependencies.

## Background

David A. Tristram created Electropaint as an SGI IRIX screensaver. The preserved
source carries a 1986 Panel Library/Electropaint copyright notice and describes
both a screensaver and an interactive mode. Its apparent complexity comes from
a compact system: a history of triangles is transformed by controls such as
wheel, spin, flip, arm, wrist, twist, and zoom. The Panel Library's compound
sliders can modulate those values automatically, while its recorder can capture
and replay a changing control state.

The surviving source represents two historical editions:

- The classic IRIS_4D edition uses an indexed 128-color spectrum map.
- The IRIS_GT edition adds RGB color, alpha blending, lighting, material and
  depth controls, ribbons, and additional color channels.

## Project goal

The goal is to preserve the behavior and character of those editions in a
browser, not merely reproduce a similar animation. The port therefore aims to:

- translate the source constants, defaults, history, interpolation, matrix
  order, color behavior, and compound controls into a deterministic 60 Hz
  engine;
- express the original fixed-function graphics behavior explicitly in WebGL2,
  including accumulation, smear, smooth, stippled fade, outlines, alpha,
  lighting, and depth;
- retain the original controls and shortcuts in a usable desktop interface;
- provide versioned JSON recording and replay with stable control IDs; and
- remain a backend-free build that can be hosted on any static file host.

The bundled autoplay sequences are clearly labeled reconstructions. They are
not presented as recovered SGI screensaver scripts. A `source` compatibility
mode preserves known source behavior, while `corrected` mode applies the one
documented visual correction: restoring the omitted outline on the first
mirrored triangle.

## Source material and credits

The primary historical reference for this project is the
[archived IGL project page](https://web.archive.org/web/20060210060733/http://users.volja.net/wesley/igl.html).
IGL was an open-source IrisGL-to-OpenGL compatibility project for Win32 and X11;
its later releases incorporated the Panel Library and Electropaint sources.

The `igl_0.1.8.zip` release from that archive is extracted in
[`igl_0.1.8/`](igl_0.1.8/). It is kept beside the browser implementation as the
behavioral authority and as the basis for the small C reference harness used by
the numeric tests.

Thanks also to the [sgi-demos/igl](https://github.com/sgi-demos/igl) archive for
pointing the way to the surviving IGL material.

Panel Library/Electropaint Copyright © 1986 David A. Tristram. Electropaint™ is
a Registered U.S. Trademark of Tristram Visual.

## License

The browser implementation is distributed under the
[GNU General Public License, version 2](LICENSE). The extracted historical
material remains subject to its original notices and
[`igl_0.1.8/license.txt`](igl_0.1.8/license.txt), which is preserved unchanged.

## Development

```sh
npm install
npm run dev
```

Run the checks with:

```sh
npm test
npm run test:browser
npm run build
```

`npm run fixtures` rebuilds the checked-in numeric fixture from the small C
reference harness. `npm run test:browser:update` updates the Playwright visual
baselines after the Playwright browser engines have been installed.

## Repository layout

- `src/` — deterministic engine, controls, timeline support, UI, and WebGL2
  renderer.
- `tests/` — source-derived unit fixtures and cross-browser Playwright tests.
- `igl_0.1.8/` — extracted historical IGL, Panel Library, and Electropaint
  source material.
- `docs/plans/` — implementation plan and per-deviation implementation notes.
