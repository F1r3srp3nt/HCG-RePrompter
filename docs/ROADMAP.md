# Roadmap

## Milestones
- **M0 – Repository and architecture** ✅ package structure, CI, documentation, tests
- **M1 – Native macOS interface** ✅ workspace, navigation, settings, clipboard
- **M2 – Prompt enhancement** ✅ Anthropic provider, six modes, contract validation, error handling, local formatter
- **M3 – History and templates** ✅ persistence, saved prompts, collections, templates, search
- **M4 – Quality and packaging** 🟡 accessibility labels and keyboard navigation; automated tests; local bundle script.
  Still open: hands-on accessibility audit with VoiceOver, and real-device QA on Apple Silicon.

## Offline workspace milestone (current)
- ✅ Reliable launch and a layout that fits the minimum window
- ✅ Create, title, edit, save, reopen, copy original; session restore; unsaved-change protection
- ✅ Visible, disabled “Reprompt with HCG AI”; empty Result pane with status message
- ⏳ Next: connect the HCG AI service (ai.hakmicapitalgroup.com) through `HCGRepromptService`
  once it is operational and its API is verified. Founder approval is required before activation.

## Candidates after 0.1.0
- Streaming responses with live preview
- Additional providers behind `AIProvider`
- Template placeholder fill-in form
- Per-prompt version history (multiple enhancement iterations)
- Localization; better non-English analysis
- XCUITest coverage of key flows

## HCG integration boundaries

Version 0.1.0 is standalone. It builds and runs without the HCG website, ERP or AI Centre.

| System | 0.1.0 status | Rule |
|---|---|---|
| HCG Shared Identity / HCG Connect | Interface only (`HCGIdentityProviding`) | No own authentication or identity infrastructure is built |
| Central licensing / permissions | Interface only (`HCGEntitlementChecking`) | No licensing or subscription system |
| HCG Product Registry | Interface only (`HCGProductRegistryReporting`) | Metadata only, never prompt content |
| HCG ERP | Not connected | No direct database connections |
| HCG AI Centre | Not connected | Activation requires explicit founder approval |

No production HCG endpoints are defined anywhere in the code.

## Separation from the Oslo Sprint Hackathon project
Token-cost optimization, AI spending analysis, multi-model cost allocation, context-window cost
management and price-based model routing are explicitly out of scope.
