# Button4 Wheel Paging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved button4 + wheel Page Up/Down action without changing ordinary scrolling or existing button3 gestures.
**Architecture:** Karabiner 16.1 reserves F19 while button4 is held and restores an unused button4 tap on release. The existing active keyboard tap also observes wheel events and only consumes a discrete vertical wheel event while F19 is held, after successfully posting the corresponding page key.
**Tech Stack:** Objective-C, CoreGraphics/AppKit/Carbon, existing C tests, Karabiner JSON; no new dependencies.
**Spec:** docs/superpowers/specs/2026-11-02-button4-wheel-paging-design.md
**Execution:** Native implementation in the current checkout, as requested by the user.

## Global Constraints

- Preserve macOS 13+ support and Karabiner-Elements 16.1 compatibility.
- Preserve button3 gestures and button5. Ordinary, continuous, horizontal, and momentum scrolling passes through unchanged.
- Page Up/Page Down follows the same direction as ordinary scrolling, including the natural scrolling preference.
- Button4 single click remains a click; release after wheel use must not click.
- Do not reintroduce smoothing, scroll physics, new dependencies, or unrelated hold timing changes.

## Review Focus

- No held button: compare the input wheel event before/after and assert identity plus no output.
- Natural scrolling: the same delivered delta always maps to the same page key, with both inversion flags exercised.
- Trackpad/horizontal/momentum: pass each through while F19 is held.
- Button release or event tap loss: ensure paging stops and later wheel events pass.
- Output allocation/post preparation failure: return the original scroll event rather than dropping it.

## Task 1: Complete paging behavior, tests, configuration, and documentation

**Files:** src/main.m, tests/test_drag_direction.m, tests/check_karabiner.py, tests/check_no_smooth_scroll.py, karabiner/button4-wheel-to-f19.json, scripts/install.sh, scripts/uninstall.sh, README.md.
**Interfaces:** F19 down/up is the paging signal. Reuse post_symbolic_hotkey_keyboard_events(CGKeyCode, CGEventFlags). A static CGEventRef paging_scroll_event(CGEventRef) returns NULL only after successfully posting Page Up/Down, otherwise the original event.

- [ ] Add callback tests: F19 + physical up/down emits keycodes 116/121 exactly once; plain wheel emits none; inversion, release, tap disable, continuous/horizontal/momentum input and output creation failure behave as specified above.
- [ ] Run `make mac-test`; watch the new paging cases fail before implementation.
- [ ] Consume F19, add scroll-wheel events to the existing active tap mask, implement paging_scroll_event, and reset paging state on stop/disabled tap.
- [ ] Add optional Karabiner rule: button4 -> F19; to_if_alone -> button4; no repeat:false. Update installer/uninstaller assets and configuration checks.
- [ ] Replace the old blanket ban on wheel observation with checks that smoothing remains absent; runtime passthrough tests protect ordinary scrolling.
- [ ] Document optional rule activation, physical wheel direction, standalone button4 tap behavior, and the unchanged ordinary scroll path.
- [ ] Run `make check mac-test mac-build`, native Karabiner CLI lint, and `git diff --check`; obtain code review before installation.

## Task 2: Install and verify actual inputs

- [ ] Back up the current executable, LaunchAgent, Karabiner assets and active profile before deployment.
- [ ] Install the tested executable and optional asset, enable only the approved paging rule in the selected profile, preserve other settings, and refresh the same helper permission if necessary.
- [ ] Verify helper startup, installed/build binary identity, Karabiner configuration acceptance, ordinary scroll passthrough, paging, and button4 standalone click on actual hardware.
- [ ] Verify the reported direction mismatch between ordinary scroll and button4 paging. New literal natural-scroll cases must fail before removing the redundant inversion and pass afterward.
- [ ] Commit local changes and report remaining hardware/OS uncertainty; do not push without a request.
