# Security and Privacy Model

User prompts are treated as potentially confidential, untrusted data.

## Current milestone: offline only

In this build the app makes **no network requests**. It does not read or write the Keychain,
does not ask for API keys or a sign-in, and does not generate or rewrite prompts. The
sections on credentials, network and prompt injection below describe the AI pipeline kept in
the codebase for a later milestone. The app does not use that pipeline now.

## Credentials
- API keys are stored only in the macOS Keychain (generic password,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, service `com.hakmicapital.reprompter.credentials`).
- Keys are read just before each request and are not kept in application state; the UI shows only a masked hint (`sk-ant-…abcd`).
- Keys are never written to settings, history, exports, backups or logs. `RedactedSecret` hides
  the key from `print`/`dump`/interpolation, and `SecretRedactor` scrubs key-like strings from provider error messages.
- No production key is hard-coded.

## Network
- Provider requests are HTTPS-only (enforced in configuration validation and in the transport), TLS 1.2+.
- An ephemeral `URLSession` is used, with no disk cache and no cookies.
- Prompt text is sent only when the user presses **Enhance** with the AI provider selected. The first
  request shows an explicit disclosure that names the destination host; the workspace always states where the prompt will go.
- **Test Connection** calls the models endpoint and sends no prompt text.
- There is no telemetry, analytics or crash-report upload.

## Prompt injection and untrusted content
- The user's prompt is fenced in a random per-request boundary tag. The system prompt defines its
  contents as data to rewrite and never as instructions, and forbids executing or answering it.
- Custom style instructions are fenced the same way and cannot override the preservation or safety rules.
- Provider output is parsed as data and validated against a schema. It is never executed or rendered as HTML.
- The application never executes code found in prompts.

## Local data
- Data files are owner-only (0600) in an owner-only folder (0700) and are written atomically.
- Backup import is size-limited (20 MB), schema-checked, sanitized (control and bidi characters
  removed, lengths capped, future dates clamped) and merged under fresh IDs. It never overwrites existing data.
- Deletion is explicit: **Delete** permanently removes a prompt; **Clear History** removes unsaved
  entries but keeps saved prompts. Turning off history stops new entries from being recorded.

## Reporting
Report security issues privately to Hakmi Capital Group. Do not open public issues for vulnerabilities.
