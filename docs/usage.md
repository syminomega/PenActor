# Usage and diagnostics

English | [简体中文](usage.zh-CN.md)

## Service and permissions

General settings control whether observation starts and settings open at launch.
Closing settings leaves the service running. Mapping is always paused after an
app restart; explicitly enable a saved profile when ready. **⌘⇧R** pauses all
mapping; **⌘⇧P** starts or stops the input service.

Local pen testing can work without Input Monitoring permission. Global observation
uses Input Monitoring; active pressure mapping requires Accessibility. Request
buttons open the corresponding System Settings privacy page, with a fallback to
the privacy overview. If the app is missing from the list, add the installed
`PenActor.app`, then follow any system request to relaunch. Recheck permission in
General settings afterward.

An installed app's path, bundle ID, and signing identity matter for permission
recognition. An enabled entry for an older identity does not establish access for
the current build. See [signing](development.md#signing) when updating local builds.

## Device defaults and profiles

1. Bring a pen into range and draw so PenActor can identify it.
2. Select the device in Profiles and optionally give it a display name.
3. Save its default pressure curve and entry/exit settings.
4. Create or select a named profile, add target applications, and save.
5. Enable the profile while the service is running and permissions are available.

Each device has its own defaults. Application rules can inherit those defaults,
override curve/entry/exit independently, or pass through unchanged. Changing a
saved setting takes effect on the next stroke. Only one profile per device can be
enabled at a time. Unknown devices and applications outside the selected profile's
targets pass through. Clearing debug history does not delete profiles or names.

The curve is a monotone interpolation between editable control points. Entry
taper fades in pressure using accumulated screen distance or elapsed time,
whichever reaches its limit first. Exit taper delays matching pen events and
fades the queued tail after lift-off. Both taper options default to off.

Exit duration is also a base input delay (10–200 ms). Queue ordering and scheduling
can add more delay. Very short strokes may fade substantially when entry and exit
overlap; the app does not synthesize stationary pressure samples. Compare a brush
with taper disabled, entry only, then exit enabled before choosing settings.
Stopping or disabling mapping can end a buffered stroke early.

## Debug and Testing pages

Debug shows live values, metadata, recent events, and independent tap diagnostics.
The live pressure bar follows the latest reading directly. History persists when
input stops; silence does not establish disconnection. Automatic device selection
changes when the active pen changes and can be disabled for manual inspection.

Pressure is a normalized system value, not physical force. Tilt is normalized,
rotation is in degrees, absolute coordinates belong to tablet space, and screen
coordinates are global screen points. Missing pressure is not zero. Capability
bits describe driver declarations, not confirmed working hardware features.

Testing draws pressure-dependent strokes using local pen events. Move the window
onto the iPad for Sidecar. Pencil double-tap and squeeze callbacks apply only to
this window and are not attributed to a specific pen. AppKit and SwiftUI reports
of the same double tap are paired. SwiftUI Pencil callbacks require macOS 14.5;
AppKit `changeMode` remains available on the older supported system.

## Persistence

Files live in `~/Library/Application Support/PenActor/`:

| File | Current schema | Contents |
| --- | --- | --- |
| `profiles.json` | 6 | Profile IDs, names, device identities, and application rules |
| `defaults.json` | 4 | Device display names and default configurations |

Readers accept profile schemas 1–6 and defaults schemas 1–4. Migration backs up
existing files under `Backups/device-scoped-<UUID>/` before writing. Removed legacy
smoothing fields are discarded; curve and taper settings are preserved. Unknown
unsupported data or invalid configuration blocks writes instead of overwriting the
original files. Enabled profile IDs are not persisted.

## JSON exports

Use **Export JSON** in Debug. The file is a snapshot taken when the button is
pressed, ordered oldest first, containing all devices rather than only the
selected device. Events arriving while the save panel is open are excluded.
Exports use schema 4, formatted UTF-8 JSON, unrounded numeric values, and UTC
ISO 8601 reception dates with milliseconds.

| Field | Meaning |
| --- | --- |
| `events` | Up to 500 retained AppKit events, native type codes, identity at capture, samples, screen coordinates, and foreground context |
| `devices` | Resolved identities, session IDs, and latest metadata/proximity |
| `totalObservedEvents`, `retainedEventCount`, `discardedEventCount` | Capture coverage; older events may already be evicted |
| `profiles`, `mapping.defaults` | Saved configuration at export time |
| `mapping.diagnostics` | Up to 500 independent tap diagnostics with input/output pressure, route, profile, taper, and delivery mode |
| `mapping.bufferedEventCount` | Events still waiting for output |
| `pencilGestures` | Cumulative local gesture summary |

Use event `timestamp` differences for system-event timing; `receivedAt` records
local reception. `sample.pressure = null` means unreadable pressure, whereas `0`
means a valid zero. Proximity events have no sample.

AppKit observation may already contain mapped pressure. Tap diagnostics record
pressure before and after processing and are not paired one-to-one with AppKit
events. Output values are read back after writing and can include quantization.
Diagnostics describe prepared output, not acknowledgment from the target app.

Logs include potentially identifying hardware metadata, app context, and drawing
positions. They are saved locally and never automatically uploaded. Export files
and `Logs/` are ignored by Git. For offline timing analysis:

```sh
python3 scripts/analyze-pen-log.py /path/to/PenActor-log.json
```
