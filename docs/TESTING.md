# Testing

All automated tests use mock transports, mock providers and temporary
directories. They make no network calls and incur no API costs.

```bash
swift test                                  # all tests available on this platform
REPROMPTER_KEYCHAIN_TESTS=1 swift test      # macOS: also exercise the real Keychain
```

| Suite | Covers |
|---|---|
| Input handling | Empty input, oversized input, custom-mode instructions, sanitization |
| Segmentation | Sentences, abbreviations, decimals, lists, headings, code fences, no content loss |
| Requirement extraction | Objective, requirements, constraints and output classification; ambiguities; missing information |
| Prompt preservation | Anchor extraction; dropped numbers and identifiers; inverted negations; verbatim code |
| Enhancement modes | All six modes preserve every anchor and invent no words; mode-specific layout; large input |
| Request/response contract | Schema, unguessable fencing of injection attempts, per-mode guidance |
| Malformed responses | Non-JSON, missing fields, wrong types, oversized output, list caps, sanitization |
| Anthropic provider | Documented request shape and headers, no sampling parameters, status-code mapping, refusals, truncation, redaction, connection test |
| Enhancement service | Retries and backoff, `retry-after`, permanent failures, cancellation in flight and while waiting, no silent fallback |
| Sensitive credentials | Key validation, masking, redaction, reflection safety, Keychain round trip (macOS) |
| Persistence | Library operations, search, history limit, history deletion, file permissions, corrupt-file recovery |
| Templates, backup, export | Overrides and reset, import validation and merge, TXT/MD/JSON export, safe file names |
| App workflows (macOS) | Local and AI flows, disclosure, cancellation, accept/reject/edit, save/delete/clear, history off, key storage |

## Environments
- **Linux (Docker `swift:6.0-noble`)**: Core, Providers and Persistence. This is used during development.
- **macOS CI (`macos-15`)**: everything, including the SwiftUI module, app workflows, Keychain and bundle assembly.

GUI interaction (clicking through windows) is not automated in 0.1.0.
