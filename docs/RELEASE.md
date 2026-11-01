# Release Control

All release decisions remain under founder control.

Allowed without further approval:
- Local builds (`swift build`, `scripts/build-app.sh`) with ad-hoc signing for local use.
- Running tests locally and in CI (build/test only; CI uploads no artifacts).

Requires explicit founder approval:
- GitHub releases or tags, distributing builds
- Developer ID signing, notarization, Mac App Store submission
- Activating production HCG integrations (identity, licensing, registry, ERP, AI Centre)
- Changes to central HCG security rules
- Commercial subscription infrastructure

Release artifacts are prepared only when explicitly requested.
