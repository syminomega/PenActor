# Development

English | [简体中文](development.zh-CN.md)

## Requirements and commands

Use Xcode with Swift 6 and a macOS SDK that can compile the project's guarded
macOS 27 APIs. Deployment remains macOS 14. The shared scheme is **PenActor**;
there are no third-party package dependencies.

From the repository root:

```sh
# Compile both supported architectures without launching the app.
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/Release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

# Run the full fixture and UI suite in a separate build directory.
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests test

# Run one test suite (test IDs remain stable across source-file splits).
xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests -only-testing:PenActorTests/PressureMappingTests test
```

Add `arch=arm64` or `arch=x86_64` to the macOS test destination if needed. Test
sources mirror application responsibilities. Shared fixtures and backend doubles
live in `PenActorTests/Support/`; the two XCTest classes retain their original
names, with test methods grouped into extensions.

The test host uses a temporary profile repository, skips startup observation, and
does not migrate real configuration. Quartz fixtures do not post real system
input; tap failure paths use injected factories. UI tests exercise rendering,
navigation, window sizing, draft state, and the pressure meter. Some rendering
tests write PNG previews to the system temporary directory.

Use builds/tests from a separate derived-data directory when the daily app is
running. Do not install a test product over the daily app. Actual Sidecar/tablet
and drawing-app verification remains separate from the fixture suite.

## Signing

The bundle ID is `dev.SyminStudio.PenActor`; the test bundle appends `.tests`.
`Config/Signing.xcconfig` provides a portable ad-hoc default and optionally includes
the ignored `Config/Signing.local.xcconfig`. For a stable local development identity,
configure the local file through your existing Xcode signing setup, for example:

```xcconfig
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOURTEAMID
```

Keep the same bundle ID, team, and installation path for daily builds. Ad-hoc
signatures change with code and can require permission authorization again.
Changing to a new identity can also require authorization; a stable signature
does not guarantee that every OS update preserves TCC state.

An existing Apple signing identity can also build a universal Release app:

```sh
security find-identity -v -p codesigning
scripts/build-signed.sh <40-character-identity-SHA-1> <10-character-team-ID>
```

The script verifies the resulting signature and team and writes to
`build/Signed/Build/Products/Release/PenActor.app`. It does not install certificates,
change trust, grant privacy access, or replace the installed app. DMG packaging
is available below; notarization and automatic release uploads are not configured.

Avoid keeping full app-shaped signing probes or versioned backups with the same
bundle ID. Launch Services can discover them even with a different extension and
show confusing names in privacy settings. Keep necessary backups as ZIP archives.

## DMG packaging

Create a universal Release DMG using the current Xcode signing configuration:

```sh
scripts/package-dmg.sh
```

The script builds into `build/Packaging`, packages the app without altering its
signature, and writes `build/Release/PenActor-<version>-macos-universal.dmg` plus
its `.dmg.sha256` checksum. The version comes from the compiled app's Info.plist.
The image contains `PenActor.app`, an Applications shortcut, and both installation
guides. It verifies the app signature, both architectures, compiled languages,
image integrity, and mounted contents. Existing output files are not overwritten.

To package an already-built app, or select another artifact directory:

```sh
scripts/package-dmg.sh \
  --app build/Signed/Build/Products/Release/PenActor.app \
  --output-dir build/ReleaseCandidate
```

The provided app must have bundle ID `dev.SyminStudio.PenActor`, a valid code
signature, both arm64/x86_64 slices, and both compiled language resources. Without
a local signing override, a fresh default build uses ad-hoc signing. The current
maintainer build uses Apple Development signing. Neither is a Developer ID-signed,
notarized public-distribution build. For that workflow, obtain a Developer ID
Application identity and follow Apple's
[notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
The packaging script does not alter signing configuration, install/launch the app,
grant permissions, remove quarantine, or submit a notarization request.

For GitHub distribution, create a release in
[the repository's Releases page](https://github.com/syminomega/PenActor/releases),
choose a tag matching the packaged app version, and attach **both** the DMG and
its checksum file. Include the current signing/notarization status and a link to
[installation instructions](installation.md) in the release notes. Commit/push the
packaging and documentation changes before publishing their links. The script
only creates local artifacts; it does not create tags, push commits, or publish a
GitHub release. Test an actual browser download and first launch on a separate
Mac; local packaging checks cannot reproduce a clean recipient's Gatekeeper/TCC state.

## Change conventions

- Group code by responsibility; keep disk layout and Xcode groups aligned.
- Split unrelated models, repositories, event processing, and views. Keep tightly
  coupled private helpers beside their owner rather than adding empty abstractions.
- Keep English as the default documentation and maintain a complete Simplified
  Chinese sibling in the same change. Keep source comments in English. Preserve
  existing UI language unless a task explicitly changes product copy/localization.
- Explain ownership, API restrictions, and ordering assumptions in comments;
  avoid comments that merely repeat the code.
- Preserve persisted keys, schema compatibility, pressure-field precision, stroke
  boundaries, and cancellation/replay semantics during structural refactors.
- Run related tests for logic changes. Run a build after moving sources or changing
  target membership, and the full suite for cross-cutting refactors.
- Record actual validation and its limits; fixture success is not device certification.

## Localization and translation

### Supported languages and resources

PenActor ships **Simplified Chinese (`zh-Hans`)** and **English (`en`)**. The app
uses macOS language preferences, including the system's per-app language setting.
There is no separate in-app language preference. Relaunch after changing the
preferred language.

`PenActor/Localizable.xcstrings` is the single Xcode String Catalog for SwiftUI,
AppKit, errors, help, accessibility, and display labels. English is the development
and source language: use readable English phrases as keys and keep Simplified
Chinese translations in the same catalog. The project’s `developmentRegion` and
catalog `sourceLanguage` are `en`; `knownRegions` includes `en` and `zh-Hans`.
English is the development-language fallback. Keep these settings consistent.
Include the catalog in the app's resource build phase. This project has no storyboards or separate Interface Builder catalog.

Maintain translations alongside feature work. PenActor's macOS 14 minimum
supports `String(localized:comment:)`.
Prefer explicit localization when a string is stored in a model property
or passed through a helper accepting `String`:

```swift
let title = String(localized: "Pressure curve", comment: "Pressure response editor title")
Text(title)

// Translate the complete sentence, keeping values as typed interpolations.
let name = String(localized: "Profile \(profileNumber)", comment: "New profile name")
```

Direct SwiftUI literals can also be extracted, but plain `String` variables,
ternaries, and custom helper arguments are not automatically localized. Resolve
those explicitly. Do not concatenate translated fragments into sentences. Use
complete interpolated phrases and `ListFormatter` for human-readable lists.

### Adding and reviewing copy

1. Add a readable English source phrase and a useful translator comment for
   ambiguous terms or dynamic arguments. Reuse a key only when its meaning is the same.
2. Build in Xcode to extract strings, then complete **both** catalog language
   columns; the English value must match its source key. Do not use Chinese phrases
   as localization keys or rewrite stable data values to create English keys.
   Preserve argument types such as `%@`, `%lld`, `%llu`, and `%d`.
   Use positional placeholders when translation requires changing argument order.
3. Keep proper names (`PenActor`, `Sidecar`, `Apple Pencil`, `SwiftUI`) and keyboard
   symbols unchanged. Use macOS terms such as Input Monitoring / 输入监控 and
   Accessibility / 辅助功能 consistently.
4. Translate titles, buttons, empty states, errors, tooltips, and accessibility
   labels/values. Check default and minimum window sizes in both languages;
   concise English wording must still preserve the original meaning.
5. Run the catalog validator and both language test runs before completing a
   change that adds or alters user-facing copy.

| English | Simplified Chinese | Meaning |
| --- | --- | --- |
| Profile | 配置 | A named set of application rules for one device |
| Device defaults | 设备默认 | The base pressure configuration for one device |
| Entry taper | 入锋 | Pressure fade-in at stroke start |
| Exit taper | 出锋 | Buffered pressure fade-out at stroke end |
| Pass through | 透传 / 不映射 | Leave system input unchanged |

### Stable data versus display text

Never translate bundle IDs, JSON keys, preference keys, deterministic device
identity keys, application rule identifiers, or user-entered names. Existing
profile names remain exactly as saved; only newly generated default names use
the current language.

Some legacy Codable raw values are Chinese, including event sources, squeeze
states, and tool names. Keep them unchanged. Use `EventSource.label`,
`PencilSqueezeStatus.label`, and `PenDeviceInfo.localizedToolType` for presentation.
Device identity resolution continues to use the original tool value.

Mapping status and diagnostic reason strings are also retained verbatim in logs;
`localizedStatus` and `localizedReason` translate them only for the UI by matching
legacy raw values to explicit `String(localized:)` calls with English source keys.
Xcode can extract these display keys normally. Never pass a Chinese raw value as
a localization key. Unknown diagnostic values pass through unchanged. Do not
perform localization inside high-frequency event-tap processing. Exported diagnostic
values and explanatory log notes are not a translated user interface.

### Validation commands

```sh
python3 scripts/check-localizations.py

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Localization -testLanguage en -testRegion US test

xcodebuild -project PenActor.xcodeproj -scheme PenActor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Localization -testLanguage zh-Hans -testRegion CN test
```

The validator checks the English source language/keys, source-value consistency,
language coverage, completed values, stale entries, and format arguments.
`LocalizationTests` checks the compiled language resources, formatted values,
and stable data. The existing rendering/window suite runs in
the selected test language. Tests must compare display text with localized
expectations; assertions about persisted or diagnostic values remain invariant.

When adding another language, update the project's localizations, translate every
catalog entry, extend the validator's supported language set, and add the language
to rendering and formatting verification. Do not add empty language columns as a
claim of support.


## Bilingual documentation

English is the default landing page and documentation language. Keep `README.md`
and the existing English filenames, with complete Chinese translations beside
those files using a `.zh-CN.md` suffix. For example, `docs/usage.md` pairs with
`docs/usage.zh-CN.md`. This documentation filename convention is independent of
the application's `zh-Hans` localization identifier.

Each page has an English/简体中文 selector below its title. Links within a language
should stay in that language, including translated heading anchors. Keep factual
content, section structure, examples, numerical values, and limitations aligned.
Executable fenced code blocks remain identical in both versions. When creating,
editing, moving, or deleting a reader-facing document, update both languages and
all affected links in the same change. Do not leave a translation placeholder or
silently defer the second language.

The repository skill
[bilingual-docs](../.agents/skills/bilingual-docs/SKILL.md) provides this workflow.
`AGENTS.md` requires using it for documentation work. You can also invoke it
explicitly as `$bilingual-docs`. Agent instructions (`AGENTS.md`, `SKILL.md`, and
other tool entry files) remain canonical in English; generated/vendor files and
source comments do not require paired documents.

Run the documentation checker from the repository root:

```sh
python3 .agents/skills/bilingual-docs/scripts/check_docs.py
```

It verifies translation pairs, language selectors, matching section structure,
identical code blocks, and local links/heading anchors. Review both versions for
semantic equivalence as well: structural checks cannot judge translation quality.
Documentation-only edits need this check and a content review; they do not require
an application rebuild or device testing.
