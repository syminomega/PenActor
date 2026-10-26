---
name: bilingual-docs
description: Create, edit, review, rename, or remove PenActor reader-facing Markdown documentation while keeping English and Simplified Chinese versions synchronized. Use for README, docs, and design documentation; app string localization is a separate workflow.
---

# Bilingual documentation

English is the default repository documentation. Maintain Simplified Chinese as
an equally complete translation in the same change.

## File and navigation conventions

- Keep the English file's existing name: `README.md`, `docs/usage.md`, etc.
- Place its Chinese sibling beside it with `.zh-CN` before `.md`:
  `README.zh-CN.md`, `docs/usage.zh-CN.md`, `Design/Icons/README.zh-CN.md`.
- Immediately below each document's first heading, include a language selector:
  English page: `English | [简体中文](<sibling filename>)`;
  Chinese page: `[English](<English filename>) | 简体中文`.
- Link readers to the same-language version of other documentation. Translate
  heading fragments too. Keep language-switch links pointed at the sibling page.
- English `README.md` remains the default landing page. Do not rename it or replace
  it with a redirect or a language chooser.

## Editing paired documents

Read both versions before changing either. Apply the same factual change to both
in the current task, even if only one language was mentioned. New documentation
needs both files; moves/deletions must update both files and their incoming links.
Do not overwrite unrelated edits in either language.

Translate meaning rather than copying sentence structure. Keep scope, caveats,
evidence dates, compatibility claims, commands, paths, identifiers, shortcuts,
measurements, and examples aligned. Keep executable code blocks identical,
including their comments, so readers run the same commands. Chinese prose should
use the terminology in `docs/development.md` / `docs/development.zh-CN.md`.
Do not translate code identifiers, resource filenames, or user-entered names.

Keep matching section structure and avoid English-only new sections or abbreviated
Chinese placeholders. When a change originates in Chinese, update the English
wording as well; neither version may remain knowingly stale.

`AGENTS.md`, `SKILL.md`, and other tool-specific instruction files stay canonical
in English to avoid duplicate agent instructions. Generated files, build outputs,
and third-party/vendor content are outside this documentation workflow. Source
comments remain English; application UI translations belong in the string catalog.

## Validation

Run from the repository root:

```sh
python3 .agents/skills/bilingual-docs/scripts/check_docs.py
```

The helper checks pairs, language selectors, section structure, code-block parity,
and local links/heading anchors. Review the two versions for semantic equivalence;
the helper cannot verify translation quality. Report actual checks and limitations.
For documentation-only changes, do not require an app rebuild or device testing.
