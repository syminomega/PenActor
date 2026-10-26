# Retained research notes

English | [简体中文](research.zh-CN.md)

These are historical observations, not current compatibility guarantees or a list
of implemented features. This file consolidates earlier input, timing, and Sidecar
research notes; obsolete version-by-version implementation plans were removed.

## Initial Pencil pressure (2026-10-21)

The user observed three Sidecar/Pencil strokes in Photoshop 2026 with an initial
AppKit pressure of `0.0784`. Later values sometimes fell before rising again
(one sequence reached `0.0118`). These were four-decimal UI readings, not a
full-precision JSON capture. The capture code did not fill in that initial value.
The evidence does not determine whether the cause was hardware, Sidecar, input
processing, or brush behavior. Nonzero first contact alone is not an error.

The user reported that static pressure remapping in PenActor 0.2.0 affected the
drawing response. App/brush/curve combinations were not systematically recorded.
This does not validate buffered tapering or establish that the initial-pressure
behavior was fixed. A useful future comparison would record paired PS/CSP logs
with the same brush dynamics and taper settings.

## Event delivery frequency (2026-10-26)

Earlier analysis of user-provided logs extracted `leftMouseDragged` intervals
within complete down-to-up strokes, excluding hover and cross-stroke gaps:

| AppKit observation | Sidecar/Pencil | Wacom Intuos Pro |
| --- | ---: | ---: |
| Complete strokes | 3 | 1 |
| Drag events | 228 | 423 |
| Aggregate delivery frequency | 83.75/s | 106.18/s |
| Mean interval | 11.94 ms | 9.42 ms |
| Median interval | 12.34 ms | 7.54 ms |
| P95 interval | 21.16 ms | 13.19 ms |
| Maximum interval | 31.57 ms | 42.64 ms |
| Intervals above 16.67 ms | 36/225 | 12/422 |

Pencil ran in Photoshop with mapping and entry taper enabled; Wacom ran locally
with mapping disabled. Those different conditions prevent attributing the result
to hardware, Sidecar, or mapping cost alone. Two retained Pencil tap segments
showed roughly 238 events/s, but older logs lacked tap type codes, so companion
packets could not be excluded. Neither measurement establishes hardware sample
rate. AppKit coalescing and UI refresh rate are separate from hardware sampling.

Recompute using `scripts/analyze-pen-log.py` and original logs. Personal source
logs are intentionally excluded from the repository.

## Sidecar finger long-press (2026-10-22)

The user reported that a finger resting on the Sidecar screen while drawing could
open Photoshop's brush context menu and sometimes leave interaction stuck.
An experimental annotated-session tap saw ordinary mouse/trackpad right-clicks
but did not observe the Sidecar long-press. This experiment was removed from the
shipping code in 0.6.3, together with unverified smoothing controls.

The prior investigation found gesture controls inside the target application's
view/recognizer hierarchy, but no supported public cross-process switch for
selectively disabling Sidecar long-press while preserving pinch/rotation. An
application's `NSIsTouchNative` declaration is not an external per-gesture toggle.
A PID-specific tap comparison remains untested. Do not describe blanket right-click
blocking or sending Escape as a verified fix for this issue.

Future device work should record OS/application versions, pen/finger ordering,
down/up/cancel events, app focus changes, normal mouse input, and multi-finger
behavior. A real-device observation is needed before restoring an experimental
control to the app.
