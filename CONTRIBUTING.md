# Contributing to QuotaView

Thanks for helping improve QuotaView. Bug reports, Codex compatibility reports, focused feature proposals, documentation fixes, and tested code changes are welcome.

## Before you start

- Search existing issues before opening a new one.
- Use the issue forms for bugs and feature requests.
- Open an issue before starting a large behavioral or architectural change.
- Never post authentication tokens, login credentials, or an unredacted `~/.codex` file.

## Development setup

Requirements:

- macOS 14 or later
- Swift 6 or Xcode 16+
- ChatGPT/Codex installed and signed in for live App Server testing

Clone and verify the project:

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
```

Run the app:

```bash
swift run QuotaView
```

Run the read-only account probe:

```bash
swift run QuotaViewProbe
```

## Pull requests

Keep pull requests focused and explain:

- the problem being solved;
- the behavior before and after the change;
- the tests you ran;
- any Codex App Server schema assumptions;
- any user-facing strings or privacy implications.

For user-facing changes, update both `README.md` and `README.zh-CN.md` when the documented behavior changes. Keep English and Simplified Chinese interface strings aligned.

Before opening a pull request:

```bash
swift test
```

Do not add real account responses, credentials, tokens, signing identities, or local machine paths to tests or fixtures.

### Temporary debug-data gate

Temporary UI data must be isolated behind an explicit Debug-only injection,
visibly identified in the interface, and searchable with a stable marker.
Use `DEBUG-ONLY-MOCK` for any future temporary runtime injection.

Before any commit or GitHub push:

1. remove every `DEBUG-ONLY-MOCK` runtime injection;
2. restore the affected component to the live `CodexStatusStore` presentation;
3. remove visible `DEBUG`, `DEBUG MOCK`, and “仅用于调试” labels that describe
   the removed mock;
4. verify the reset entry is again controlled only by the latest valid
   `availableResetCredits` value;
5. run the following check and require no production-source matches:

```bash
rg -n 'DEBUG-ONLY-MOCK|DEBUG MOCK|仅用于调试' Sources
```

Debug fixtures owned by automated tests may remain only when they are passed
explicitly by the test and cannot become an application runtime default.

## Compatibility principles

- Treat Credits and remaining plan quota as separate values.
- Keep the account probe read-only.
- Do not enable quota reset consumption without idempotency, explicit result handling, and protocol compatibility tests.
- Preserve offline, missing executable, cold-start, and App Server error handling.
- Prefer native SwiftUI/AppKit behavior over web-based UI dependencies.

## Reporting a security concern

Do not open a public issue containing secrets or exploit details. Use GitHub's private vulnerability reporting option for this repository when it is available. For non-sensitive privacy or security hardening suggestions, use a regular issue.
