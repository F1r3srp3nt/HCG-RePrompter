<p align="center">
  <img src="Branding/AppIcon-1024.png" width="128" alt="HCG RePrompter icon">
</p>

# HCG RePrompter

**Native macOS prompt-engineering workstation by Hakmi Capital Group (HCG).**
Version 0.1.0 — pre-release development build, not commercially released.

> Improve the instruction without changing the intention.

RePrompter turns ordinary, incomplete or unstructured prompts into clearer,
better-organized instructions for AI systems, while preserving the user's
meaning, requirements and constraints — and it explains every change instead of
claiming the result is "better" by an arbitrary score.

## Features (v0.1.0)

| Area | What works |
|---|---|
| Workspace | Original prompt editor, six enhancement modes, editable enhanced output, accept / reject / revert edits, "use as original" for iteration |
| Enhancement modes | Quick Improve, Structured, Professional, Developer, Creative, Custom (your own style instructions) |
| AI provider | Anthropic Claude (Messages API, structured JSON output) with your own API key; cancellation, retry for transient errors, connection test |
| Non-AI fallback | **Local Formatting (no AI)** — a deterministic, offline formatter, always labelled as non-AI and never used silently |
| Validation | Response contract validation, preservation check of numbers, names, identifiers, quotes, URLs, code and negated instructions |
| Comparison | Side-by-side and inline diff; Changes report: what changed, requirements preserved, optional suggestions, open questions, ambiguities, assumptions, warnings |
| Inspector | Live local analysis: objective, requirements, constraints, expected output, missing information, ambiguities |
| Library | Local history, saved prompts, collections, search, rename, duplicate, delete, export (TXT / Markdown / JSON), backup import/export |
| Templates | 10 curated, editable templates across 7 categories; create your own |
| Security | API key in macOS Keychain only, HTTPS only, explicit disclosure before the first external request, no telemetry, owner-only data files |

## Requirements

- macOS 15 or later (Apple Silicon primary; Intel builds are not tested)
- Xcode 16 or later (Swift 6 toolchain)
- An Anthropic API key for AI enhancement (optional — Local Formatting works without one)

## Build and run

```bash
# Run from source
swift run RePrompter

# Run tests (no network, no paid API calls)
swift test

# Assemble a local, ad-hoc signed app bundle: build/HCG RePrompter.app
scripts/build-app.sh release
open "build/HCG RePrompter.app"
```

Or open `Package.swift` in Xcode, select the **RePrompter** scheme and run.

## Configuration

1. Open **Settings → AI Provider** (⌘,).
2. Paste your Anthropic API key and choose **Save to Keychain**.
3. Optionally choose a model (default `claude-opus-5-5`; suggestions include
   `claude-sonnet-5-5` and `claude-haiku-5-5`), reasoning effort, output limit and timeout.
4. **Test Connection** verifies the key and model without sending prompt text.

The first AI request shows a disclosure explaining that the prompt is sent to
the provider. Choose **Local · no AI** in the workspace to stay fully offline.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New prompt |
| ⌘↩ | Enhance |
| ⌘. | Cancel enhancement |
| ⇧⌘C | Copy enhanced prompt |
| ⌘S | Save to library |
| ⌘F | Search prompts |
| ⌥⌘I | Show / hide inspector |
| ⌘1 – ⌘5 | Workspace, History, Saved, Templates, Settings |
| ⌘, | Settings |

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Security and privacy model](docs/SECURITY.md)
- [Testing](docs/TESTING.md)
- [Roadmap and HCG integration boundaries](docs/ROADMAP.md)
- [Release control](docs/RELEASE.md)
- [Changelog](CHANGELOG.md)

## Known limitations

- One AI provider (Anthropic) in 0.1.0; the provider layer is designed for more.
- Requests are non-streaming; long prompts wait for the full response (with a configurable timeout).
- The local analyzer and formatter are heuristic and English-centred. They never invent requirements, but their classification can be imperfect.
- The bundle from `scripts/build-app.sh` is ad-hoc signed for local use only. After a rebuild, macOS may ask again for permission to read the stored Keychain item.
- Diff for very large texts falls back to line-level comparison.
- UI automation (XCUITest) is not included; app workflows are tested at the model layer.

## Project separation

RePrompter is independent of the Oslo Sprint Hackathon project. It contains no
token-cost analytics, model-price routing or AI spending analysis.

---

© 2026 Hakmi Capital Group. All rights reserved.
