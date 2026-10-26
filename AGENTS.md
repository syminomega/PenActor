# Repository guide

PenActor is a macOS menu bar app using Swift 6, SwiftUI, AppKit, and a shared Xcode
scheme named `PenActor`. Minimum deployment is macOS 14. There are no external
package dependencies.

## Start here

- Check `git status --short` and preserve existing user changes.
- Read `docs/architecture.md` for ownership and source boundaries.
- Read `docs/development.md` for build/test commands and signing conventions.
- Treat `docs/research.md` as historical evidence, not an implementation request.

## Editing

- Match responsibility-based folders and corresponding Xcode groups. Add every
  new/moved Swift source to the correct app or test target.
- Keep English as the default documentation and maintain Simplified Chinese
  siblings for reader-facing documents. For any documentation creation, edit,
  review, move, or removal, read and apply
  `.agents/skills/bilingual-docs/SKILL.md` and update both languages together.
  Keep code comments and agent instructions in English. Localize all new user-facing copy
  with English source phrases in `PenActor/Localizable.xcstrings` (`sourceLanguage: en`),
  complete Simplified Chinese (`zh-Hans`) translations, and matching English values.
  Follow the localization section in `docs/development.md`; keep stable data and
  user content separate from translated display labels.
- Preserve persisted identities, preference keys, schema compatibility, event
  routing, pressure precision, and stroke/replay ordering during refactoring.
- Keep UI/disk work out of event-tap callbacks and honor existing actor/lock ownership.
- Add availability guards for APIs newer than macOS 14.

## Validation

Build after source moves or target-membership changes. Run relevant tests for
logic changes and the full suite for broad refactors. Keep validation in separate
derived-data directories; do not overwrite the daily installed app with test
products or change its signing identity as part of verification. Automated fixtures
must not inject system input or modify the user's real configuration.

For documentation changes, run
`python3 .agents/skills/bilingual-docs/scripts/check_docs.py` and review both
languages for matching meaning.

For localization changes, run `python3 scripts/check-localizations.py` and test
both languages using the development guide commands.

Report checks actually performed and distinguish fixtures from device validation.
