# PenActor

English | [简体中文](README.zh-CN.md)

PenActor is a macOS menu bar utility for inspecting tablet input and adjusting pen
pressure in selected applications. It uses Swift 6, SwiftUI, and AppKit, with no
third-party dependencies. The minimum supported system is macOS 14.
The interface supports English and Simplified Chinese and follows macOS language
preferences, including per-app language settings. Relaunch after changing languages.

## Features

- Observe local and global tablet events, device metadata, and pressure history.
- Keep device defaults and named profiles with application-specific overrides.
- Edit monotone pressure curves and optional entry/exit tapering.
- Test pen strokes and local Pencil double-tap/squeeze callbacks.
- Export diagnostic snapshots as JSON for offline analysis.

## Install a prebuilt release

Download the universal DMG and matching SHA-256 file from
[GitHub Releases](https://github.com/syminomega/PenActor/releases), then drag
PenActor into Applications. If no binary release is listed, build from source below.
Current builds use a development signature and are not notarized by Apple.
See [installation and first-launch troubleshooting](docs/installation.md) for
checksum checks, macOS security prompts, and the app-specific quarantine command.

## Getting started

Open `PenActor.xcodeproj` in Xcode, select the shared **PenActor** scheme and
**My Mac**, then run. For a tablet, install its manufacturer's macOS driver. For
Apple Pencil, connect an iPad through Sidecar and move the test window onto it.

The app starts in the menu bar. Opening settings shows a Dock icon; closing
settings keeps the input service running. Use **General** (`通用`) to check Input
Monitoring and Accessibility access. Mapping starts paused on every launch.

In **Profiles** (`配置`), select an identified device, save its defaults, add a
profile and target applications, then explicitly enable the profile. Use
**Debug** (`调试`) to inspect events and **Testing** (`测试`) to draw locally.
**⌘⇧R** pauses all mapping.

## Build and test

```sh
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Development build

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests test
```

Signing defaults to ad-hoc unless a local configuration overrides it. Keep test
builds separate from the app used daily; see the [development guide](docs/development.md).

## Documentation

- [Installation](docs/installation.md): DMG setup, first launch, and security prompts.
- [Usage and diagnostics](docs/usage.md): configuration, permissions, tapering, and JSON exports.
- [Architecture](docs/architecture.md): source layout, ownership, and event flow.
- [Development](docs/development.md): builds, tests, signing, localization, and contribution conventions.
- [Research notes](docs/research.md): retained observations and unresolved device questions.
- [Icon sources](Design/Icons/README.md): design assets and regeneration.

PenActor observes system event values after driver/Sidecar processing, rather
than raw hardware force. Diagnostic fixtures do not establish compatibility with
every device, drawing app, or brush. Logs stay local and can contain device IDs,
application context, and drawing coordinates.
