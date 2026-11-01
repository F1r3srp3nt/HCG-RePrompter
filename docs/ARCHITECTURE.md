# Architecture

RePrompter is a Swift 6 package (strict concurrency) with five modules. The
Foundation-only modules compile and test on any Swift 6 toolchain, including
Linux CI containers; the interface is macOS-only.

```
RePrompterApp ──► RePrompterUI ──► RePrompterPersistence ──► RePrompterProviders ──► RePrompterCore
   (@main)        (SwiftUI)        (local JSON stores)       (AI + Keychain)          (Foundation only)
```

| Module | Responsibility |
|---|---|
| `RePrompterCore` | Domain types, input validation and sanitization, segmentation and analysis (`PromptAnalyzer`), preservation checking, the deterministic `LocalFormatter`, the AI request/response contract (`EnhancementContract`, `EnhancementResponseValidator`), word diff, export, templates, documented HCG integration protocols. |
| `RePrompterProviders` | `AIProvider` protocol, `AnthropicProvider` (raw HTTPS Messages API), `HTTPTransport`, `CredentialStore` + `KeychainCredentialStore`, `SecretRedactor`, `RetryPolicy`, and `EnhancementService`, which orchestrates an enhancement. |
| `RePrompterPersistence` | `PromptRecord`, `PromptLibrary` (history + saved + collections + search), `TemplateLibrary` (edits, hidden built-ins, user templates), `AppSettings`, `JSONFileStore` (atomic, 0600), `LibraryBackup` / `BackupImporter`. |
| `RePrompterUI` | `AppModel` (main-actor state), SwiftUI views, design system, menu commands, brand assets. |
| `RePrompterApp` | Entry point, window and Settings scenes, About window, app delegate. |

## Enhancement flow

1. `InputValidator` sanitizes the text (control and bidi characters removed) and enforces limits.
2. **Local Formatting:** `LocalFormatter` places every original sentence, list item and
   code block exactly once into a mode-specific layout. It never adds requirements;
   gaps become clearly labelled *Open Questions*.
3. **AI Provider:** `EnhancementContract.buildPrompt` produces a system prompt and a user
   message. The user's text is fenced in an unguessable, per-request tag and is defined as
   untrusted data. The provider is asked for JSON that matches `responseSchema`.
4. `EnhancementService` retries only transient errors (429 within the policy, 5xx, 529,
   timeouts, network) with exponential backoff. It never retries authentication, invalid
   requests, refusals or truncation, and it honours task cancellation at every step.
5. `EnhancementResponseValidator` parses and validates the JSON (types, sizes, list caps,
   sanitization), then `PreservationChecker` checks that concrete details and negations
   survived. Problems become warnings for the user to review; they are never hidden.
6. The UI shows the result as editable text, a diff and a Changes report. The user accepts,
   rejects or edits it.

If AI is selected and no provider is configured, the service fails with
`notConfigured`. It never substitutes local formatting silently.

## Persistence

Local-first JSON files in `~/Library/Application Support/HCG RePrompter/`:
`library.json`, `templates.json`, `settings.json`. The files are written atomically,
with owner-only permissions (0600 for files, 0700 for the folder). An unreadable file is
moved aside as `*.corrupt-<timestamp>.json` and never deleted. The settings decoder is
tolerant, so missing or unknown keys fall back to defaults.

JSON was chosen over SwiftData/SQLite because the data set is small, the format is
inspectable and portable, it is testable on any platform, and it supports export and
backup directly. The schema carries a version number for future migration.

## Branding

`Branding/hcg-logo.png` is the source HCG logo. `scripts/make-icons.py` generates
`Branding/AppIcon.iconset` and the UI resources (`HCGLogo.png`, `AppIcon.png`).
`BrandAssets` loads them without trapping and falls back to a text wordmark.
