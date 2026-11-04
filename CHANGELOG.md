# Changelog

All notable changes to HCG RePrompter. The format follows Keep a Changelog; versions follow Semantic Versioning.

## [Unreleased] — offline workspace milestone

### Changed
- The app is now an offline prompt workspace. All generation paths are disabled (buttons, menus and
  shortcuts): no AI requests, no local rewriting, no API keys, no sign-in, no network use.
- Workspace layout rebuilt without nested split views, the system inspector or minimum-width frames.
  The previous layout required about 1,170 pt inside a 980 pt minimum window, the likely trigger of the
  AppKit constraint-update exception. Wide windows show Original and Result side by side (Original
  gets 64%); narrow windows switch between them. The inspector is a plain side panel.
- History, Library and Templates use a fixed-width list beside a flexible detail view.
- Accent colour changed to restrained HCG cyan.
- Window minimum is now 860 × 560.

### Added
- Save, reopen and copy-original workflow with unsaved-change protection (Save / Don’t Save / Cancel).
- Session restore: the open prompt, including unsaved edits, is autosaved to `workspace.json` and
  restored at launch.
- Isolated HCG AI integration point (`HCGRepromptService`, `DisconnectedHCGAIService`) and a visible,
  disabled “Reprompt with HCG AI” button; the Result pane explains that reprompting will be available
  when HCG AI is connected.
- Tests for drafts and sessions (Linux), plus macOS workflow tests and a window resize/inspector
  stress test.

### Removed from the app
- AI provider settings, API-key entry, provider disclosure, enhancement modes, Local Formatting and the
  result/compare/changes views. Stored prompts and earlier results are preserved untouched.

## 0.1.0 (pre-release development build)

### Added
- Swift 6 package with modules Core, Providers, Persistence, UI and App; macOS 15 target.
- Prompt analysis: segmentation, requirement/constraint/output classification, ambiguity and missing-information detection.
- Six enhancement modes: Quick Improve, Structured, Professional, Developer, Creative, Custom.
- Anthropic Claude provider (Messages API, API version 2026-10-21, structured JSON output), connection test, retry with backoff, cancellation.
- Deterministic Local Formatting (no AI), clearly labelled as non-AI.
- Response contract validation and preservation checking, with user-visible warnings.
- Workspace with editable output, accept/reject/revert, comparison (side-by-side and inline diff) and a Changes report.
- Live inspector with local analysis.
- Local history, saved prompts, collections, search, rename, duplicate, delete, clear history, history limit.
- Export to plain text, Markdown and JSON; validated backup import/export.
- Ten editable built-in templates across seven categories; user templates.
- Keychain credential storage, HTTPS-only networking, first-use provider disclosure, no telemetry.
- HCG branding: HCG logo, generated app icon, About window, native menus and keyboard shortcuts.
- Documented (unimplemented) HCG integration interfaces.
- Automated tests (Swift Testing) and CI for Linux and macOS.
