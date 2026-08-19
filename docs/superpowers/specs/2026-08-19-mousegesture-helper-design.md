# MouseGesture Helper Design (rev 2)

## Purpose

Provide a tiny user-level macOS helper that complements Karabiner-Elements: Karabiner reserves physical mouse button3 by translating it to F20, while the helper consumes F20 and mouse motion to provide Mission Control/App Exposé/interactive Space gestures. **The helper does not observe, suppress, transform, or generate scroll-wheel events.** All scrolling is left to macOS and the physical device's default behavior.

## Components

- `GestureLogic.c/.h`: platform-neutral button3 click/hold/drag state machine.
- `DockSwipe.m/.h`: macOS DockSwipe output for interactive horizontal/vertical gestures.
- `main.m`: installs a session event tap for F20 and mouse motion only, dispatches gesture actions, and leaves scroll events untouched.
- `karabiner/button3-to-f20.json`: reserves button3 as F20 without touching button4/button5 or scroll.
- `scripts/*`: build/install/uninstall and LaunchAgent setup.

## Behavior

- F20 short press/release -> Mission Control (`Control+Up`).
- F20 held for 300 ms without drag -> App Exposé (`Control+Down`).
- F20 + horizontal mouse motion beyond threshold -> interactive Space DockSwipe.
- F20 + vertical mouse motion beyond threshold -> interactive Mission Control/App Exposé DockSwipe.
- Scroll wheel, trackpad scrolling, Magic Mouse scrolling -> not included in the event tap mask and therefore not modified.

## Constraints

- button4/button5 remain untouched.
- Existing Karabiner button3 click/hold rules must be disabled to avoid conflicts.
- Accessibility permission is required for the native event tap.
- DockSwipe uses undocumented event fields on macOS 13-26 and may need maintenance across OS updates.
- macOS 27+ uses shortcut fallback until the IOHIDEvent DockSwipe path is implemented.
