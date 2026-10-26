# Architecture

English | [简体中文](architecture.zh-CN.md)

PenActor uses responsibility-based folders, following Mos's separation of input,
options, application managers, windows, and reusable components. These are source
boundaries within one application target, not separate frameworks.

## Source map

| Directory | Responsibility |
| --- | --- |
| `PenActor/Application/` | App entry point, delegate, menu bar actions, and application lifetime |
| `PenActor/InputEvent/` | AppKit observation, safe event decoding, pen identity, and Pencil gesture statistics |
| `PenActor/PressureCore/` | Quartz tap lifecycle, stroke processing, taper envelopes, and buffered delivery |
| `PenActor/Options/` | Curves, profiles, device defaults, application rules, and compatibility decoding |
| `PenActor/Options/Repositories/` | Validated JSON reads and atomic file replacement |
| `PenActor/Managers/` | Main-actor coordination through `PenMonitor` |
| `PenActor/Diagnostics/` | Bounded observed history, device state, mapping snapshots, and log serialization |
| `PenActor/Windows/PreferencesWindow/` | Native window navigation/sizing and General, Profiles, Debug, and Testing pages |
| `PenActor/Components/` | Reusable SwiftUI controls, pressure displays, and panel styling |
| `PenActor/Utils/` | Identifier formatting and System Settings navigation |
| `PenActor/Localizable.xcstrings` | English and Simplified Chinese UI translations |
| `PenActor/Assets.xcassets/` | Runtime app and menu bar icons |
| `PenActorTests/` | Tests grouped by responsibility; shared fixtures in `Support/` |

`Config/` contains signing configuration, `Design/` contains editable artwork,
and `scripts/` contains build, icon-generation, and diagnostic tools. `build/`
and `Logs/` are ignored local output directories.

## Observation and presentation

`AppKitEventBackend` installs local/global observers on the main actor.
`PenEventDecoder` classifies an event before reading tablet-specific fields:
standalone tablet events and mouse events with tablet subtypes have different
valid accessors. In particular, `mouseMoved` must not read `NSEvent.pressure`.

`PenStore` resolves session IDs into stable device identities and keeps bounded
history. `PenMonitor` captures events immediately, then publishes UI snapshots
at up to 60 Hz. Export reads the capture buffer, including unpublished events.
The store retains at most 500 events, 600 samples per device, 32 devices, and
128 session associations.

Identity resolution prefers vendor/tool unique ID, then serial number, then
model metadata, with a temporary session fallback. A model identity may group
physically different pens; it is not proof of a unique physical device. Keep
versioned keys deterministic because profiles persist them.

## Active pressure processing

The independent path is:

```text
Quartz annotated-session tap
  -> PressureMappingProcessor: device/app matching and stroke-latched settings
  -> pressure curve -> entry envelope
  -> direct return OR BufferedPenEvents -> exit envelope -> replay
```

`PressureRemappingEngine` owns the worker run loop, event tap, replay scheduling,
and locks. The processor and queue are deterministic value types; tests supply
events and times without posting system input. UI work and disk I/O stay outside
tap callbacks. The engine's state lock protects mutable processing state; a
separate output lock serializes posting with stop/update operations.

Profiles apply only to identified, enabled devices and configured target bundle
IDs. The target PID comes from the Quartz event and is resolved using the
running-application map. AppKit's observed foreground application is diagnostic
context, not an equivalent routing decision.

Settings latch at stroke start. Disabling a profile or pausing takes effect
immediately. Mouse and tablet pressure fields are mapped independently; a linear
profile avoids rewriting equal values. Entry taper shares one physical stroke's
progress across event forms.

Exit taper queues event copies until its look-ahead interval expires. Replay uses
`eventSourceUserData = 0x50454E4143544F52` to bypass the app's own tap. The queue
preserves arrival order across devices and has a 2,048-event limit. Keyboard or
target boundaries, cancellation, and overflow drain pending input and release
contacts when necessary. A tap failure stops mapping without repeated automatic
restart. Do not change these ordering or recovery rules as incidental cleanup.

## Configuration and UI ownership

`MappingDefaults` resolves each profile's application rules against that device's
default configuration. Compatibility fields exist for migration and old fixtures;
they must not become new global configuration paths. Repositories validate before
writing. `PenMonitor` coordinates backups and migration and blocks configuration
writes/mapping if loading or migration fails.

`ContentView` hosts pages and global status controls. Each page owns its transient
state. `DeviceProfileDraftState` compares saved and edited values and guards
against late callbacks after selection changes. `PreferencesWindowController`
owns native navigation and resizing. The test pad owns local drawing and gesture
recognition; it never filters another application's input.

Folders and Xcode groups mirror one another. Every Swift file must also have the
correct target membership in `project.pbxproj`; moving a file on disk is not enough.
