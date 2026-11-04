<p align="center">
  <img src="Branding/AppIcon-1024.png" width="128" alt="HCG RePrompter icon">
</p>

# HCG RePrompter

**Native macOS prompt-engineering workstation by Hakmi Capital Group (HCG).**
Version 0.1.0 (offline workspace milestone) — pre-release development build, not commercially released.

> Improve the instruction without changing the intention.

RePrompter turns ordinary, incomplete or unstructured prompts into clearer,
better-organized instructions for AI systems, while preserving the user's
meaning, requirements and constraints — and it explains every change instead of
claiming the result is "better" by an arbitrary score.

## Current milestone: offline prompt workspace

This build is a working **offline** prompt workspace. AI reprompting arrives in
a later milestone, once the HCG AI service is operational and its API is
verified.

| Area | What works |
|---|---|
| Workspace | Title and original-prompt editor (most of the window), word and character counts, Save (⌘S), Copy Original (⇧⌘C) |
| Library | Save prompts to a local library, reopen them, rename, duplicate, organize into collections, search, delete, export (TXT / Markdown / JSON), backup import/export |
| Pick up where you left off | The open prompt, including unsaved edits, is autosaved and restored when you relaunch |
| Unsaved edits | Starting a new prompt, opening another or using a template asks Save / Don’t Save / Cancel first |
| Layout | Original and Result side by side on wide windows; on narrow windows an Original / Result switcher (your text is kept). Optional inspector (⌥⌘I). |
| Templates | 10 curated, editable templates across 7 categories; create your own |
| Inspector | Prompt details plus a local, non-AI analysis: objective, requirements, constraints, missing information, vague wording |
| HCG AI (future) | A visible, disabled **Reprompt with HCG AI** button. The Result pane reads “Reprompting will be available when HCG AI is connected.” |
| Privacy | No network use, no API keys, no sign-in, no telemetry. Owner-only data files. |

**Not in this milestone:** prompts are not generated, rewritten or sent anywhere.
Every generation path is disabled, including menus and shortcuts.

## Requirements

- macOS 15 or later (Apple Silicon primary; Intel builds are not tested)
- **Xcode 16 or later, selected as the active developer directory.** Building with
  only the Command Line Tools selected can fail with `no such module 'Testing'`.
  Check with `xcode-select -p` (it should point inside `Xcode.app`) and fix with
  `sudo xcode-select -s /Applications/Xcode.app`.

## Build and run

```bash
# Run from source
swift run RePrompter

# Run tests (no network)
swift test

# Assemble a local, ad-hoc signed app bundle: build/HCG RePrompter.app
scripts/build-app.sh release
open "build/HCG RePrompter.app"
```

Or open `Package.swift` in Xcode, select the **RePrompter** scheme and run.

Your data lives in `~/Library/Application Support/HCG RePrompter/`
(`library.json`, `templates.json`, `settings.json`, `workspace.json`).

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New prompt |
| ⌘S | Save to library |
| ⇧⌘C | Copy original prompt |
| ⌘F | Search prompts |
| ⌥⌘1 / ⌥⌘2 | Show Original / Result |
| ⌥⌘I | Show / hide inspector |
| ⌘1 – ⌘5 | Workspace, Library, All Prompts, Templates, Settings |
| ⌘, | Settings |

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Security and privacy model](docs/SECURITY.md)
- [Testing](docs/TESTING.md)
- [Roadmap and HCG integration boundaries](docs/ROADMAP.md)
- [Release control](docs/RELEASE.md)
- [Changelog](CHANGELOG.md)

## Known limitations

- No AI reprompting yet (see above). The earlier Anthropic adapter remains in
  `Sources/RePrompterProviders` with its tests, but the app does not use it.
- The local analysis in the inspector is heuristic and English-centred.
- The bundle from `scripts/build-app.sh` is ad-hoc signed for local use only.
- Switching between the side-by-side and narrow layouts keeps your text; the
  editor stays in place when only the Original pane is visible.

## Project separation

RePrompter is independent of the Oslo Sprint Hackathon project. It contains no
token-cost analytics, model-price routing or AI spending analysis.

---

© 2026 Hakmi Capital Group. All rights reserved.
