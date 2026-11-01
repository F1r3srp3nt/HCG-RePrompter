# Changelog

All notable changes to HCG RePrompter. The format follows Keep a Changelog; versions follow Semantic Versioning.

## [Unreleased] — 0.1.0 (pre-release development build)

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
