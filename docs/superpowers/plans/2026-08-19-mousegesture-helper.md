# MouseGesture Helper Rev 2 Implementation Note

The original plan included smooth wheel scrolling. Rev 2 deliberately removes that subsystem after real-device testing showed undesirable stutter/scroll errors.

Current scope:

- Keep Karabiner `button3 -> F20`.
- Keep F20 short click -> Mission Control.
- Keep F20 300 ms hold -> App Exposé.
- Keep F20 + horizontal drag -> Spaces.
- Keep F20 + vertical drag -> Mission Control/App Exposé gesture.
- Remove all scroll-wheel event observation, suppression, synthetic output, physics code, configuration, build inputs, and tests.
- Verify production source contains no `kCGEventScrollWheel`, `kCGScrollWheelEvent*`, `MG_SCROLL_*`, or `SmoothScroll` references.
