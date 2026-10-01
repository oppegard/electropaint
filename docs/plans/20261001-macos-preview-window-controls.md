# macOS preview title and window controls

Status: approved by the user on 2026-10-01; implementation and local checks
complete; PR preparation in progress. The
user confirmed that the title suffix should be the short Git commit hash.

## Proposed changes and reasoning

- Show
  `Electropaint — 1994 default script (abc1234)` in the preview window title.
  Embed the first seven characters of the build's Git HEAD in the preview
  bundle during `macos/build.sh`, before signing, and read it at launch. This
  identifies the same source revision as the existing download filenames.
  Define a clear `unknown` fallback for builds without Git metadata.
- Add a native File menu with Close Window bound to Command-W, routed through
  AppKit's responder chain to `performClose:`. Preserve the existing
  `applicationShouldTerminateAfterLastWindowClosed:` hook and termination
  cleanup so closing the single window quits the app and stops animation.
- Add a native View menu with Toggle Full Screen bound to Control-Command-F,
  routed to `toggleFullScreen:`. Explicitly enable the preview window's
  full-screen primary collection behavior and use AppKit's native full-screen
  transition. The shortcut should both enter and exit full screen.
- Make an unmodified Space press toggle pause/resume in the focused preview
  window, including full screen. Handle this in the preview application;
  ignore key-repeat events so holding Space does not repeatedly toggle.
  Use the view's existing stopAnimation/startAnimation lifecycle: it retains
  the engine state and resets elapsed-time bookkeeping, so resuming continues
  the script without restarting or catching up for time spent paused. Keep
  the last rendered frame visible while paused.
- Document the title and shortcuts in `macos/README.md`. Keep changes scoped
  to the preview application and build metadata, with no new dependencies.
- Create a PR containing these changes and the approved implementation plan
  and current checklist in a collapsed Implementation Plan section.

Apple's full-screen guidance:
https://developer.apple.com/design/human-interface-guidelines/going-full-screen

## Validation

- Build the universal preview and screensaver bundles and check preview
  metadata and signatures. Verify its embedded hash matches Git HEAD.
- Run ShellCheck on modified shell scripts and `git diff --check`.
- Exercise the built preview's displayed title, Command-W shutdown, red close
  button shutdown, Command-Q, and Control-Command-F entry/exit. Check animation
  and resize behavior after leaving full screen. If native UI access is
  unavailable, report the unverified interaction checks explicitly.
- Verify Space freezes the displayed frame and resumes the same script;
  check holding Space, repeated pause/resume, and toggling in full screen.
- Run the existing native bundle smoke check where Metal access is available.
- Inspect PR checks and report any remaining validation limitations.

## Task checklist

- [x] Inspect repository instructions and native preview lifecycle.
- [x] Verify Apple's full-screen shortcut convention.
- [x] Write proposed implementation plan.
- [x] Clarify the requested title suffix.
- [x] Obtain user approval before coding.
- [x] Embed build identity and update preview title.
- [x] Add native Close Window and full-screen commands.
- [x] Add Space pause/resume using the existing animation lifecycle.
- [x] Update documentation and complete relevant validation.
- [ ] Commit, push, and create the PR with this plan and checklist.

## Implementation evidence

- Universal arm64/x86_64 build passes, with preview plist validation and strict
  signature verification. The embedded seven-character hash matches HEAD.
- Native bundle smoke check passes: loading, Metal compilation, independent
  views, resizing, and animation stop/restart.
- ShellCheck and `git diff --check` pass.
- UI checks confirm the title suffix, Space pause with an unchanged frame
  across captures, resume, full-screen entry/exit, and Command-W application
  termination after the full-screen transition completes. Space events were
  also exercised in full screen. Holding Space is handled by rejecting repeat
  events; physical key-hold behavior has not been manually tested.
- These checks ran on Apple Silicon; Intel execution remains untested.
