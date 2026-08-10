# Contributing to QuotaView

Thanks for helping improve QuotaView. Bug reports, Codex compatibility reports, focused feature proposals, documentation fixes, and tested code changes are welcome.

## Before you start

- Search existing issues before opening a new one.
- Use the issue forms for bugs and feature requests.
- Open an issue before starting a large behavioral or architectural change.
- Read the [SDD specification index](docs/specs/README.md) and the specification
  that owns the affected behavior.
- Never post authentication tokens, login credentials, or an unredacted `~/.codex` file.

## Specification-driven development

QuotaView uses Specification-Driven Development (SDD). Product behavior,
architecture, implementation evidence, release history, and current work have
separate documents and must not be treated as interchangeable.

Before implementation:

1. identify the owning Spec ID and Requirement ID in
   [`docs/specs/README.md`](docs/specs/README.md);
2. update the specification first when behavior, scope, privacy, accessibility,
   fallback behavior, or acceptance criteria change;
3. keep exploratory work in `Prototypes/` until production implementation is
   explicitly authorized;
4. do not treat an accepted Demo as production implementation or a completed
   implementation as authorization to publish.

The standard lifecycle and exit criteria are documented in
[`docs/specs/DEVELOPMENT_PROCESS.md`](docs/specs/DEVELOPMENT_PROCESS.md).
Small fixes may reuse an existing Requirement ID. When a change has no spec
impact, the pull request must state `Spec impact: None` and explain why.

The current stable production baseline is `0.3.3 (Build 3)`. The released
`0.3.2 Preview 1` multi-task Codex Island remains a separate public pre-release
and an archived local reference; its production implementation is intentionally
not part of the 0.3.3 stable source. Any renewed multi-task work requires a new
iteration, version, build, and explicit product decision.

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

- the Spec ID and Requirement ID, or why the change has no spec impact;
- the current specification and delivery states;
- the problem being solved;
- the behavior before and after the change;
- the tests you ran;
- the product-owner acceptance status when visual or interaction behavior changes;
- any Codex App Server schema assumptions;
- any user-facing strings or privacy implications.

For user-facing changes, update both `README.md` and `README.zh-CN.md` when the documented behavior changes. Keep English and Simplified Chinese interface strings aligned.

Before opening a pull request that changes source, resources, configuration, or
build scripts:

```bash
swift test
```

A Markdown-only change may skip `swift test` when it does not touch production
behavior, but the pull request must say that it is docs-only and still run link,
consistency, and `git diff --check` validation.

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

### Release-signing gate

The app embeds `QuotaViewCore.framework`. A Team ID-bearing Apple signing
identity may enable Hardened Runtime when the app and framework are signed
with the same identity. The ad-hoc fallback must not enable Hardened Runtime
because it has no Team ID and macOS Library Validation would reject the
embedded framework at launch.

For release changes, verify both the extracted archive signature and an actual
launch of the freshly extracted app. `codesign --verify --deep --strict` checks
bundle integrity but does not prove that `dyld` can load embedded frameworks.

## Compatibility principles

- Treat Credits and remaining plan quota as separate values.
- Keep the account probe read-only.
- Do not enable quota reset consumption without idempotency, explicit result handling, and protocol compatibility tests.
- Preserve offline, missing executable, cold-start, and App Server error handling.
- Prefer native SwiftUI/AppKit behavior over web-based UI dependencies.

## Reporting a security concern

Do not open a public issue containing secrets or exploit details. Use GitHub's private vulnerability reporting option for this repository when it is available. For non-sensitive privacy or security hardening suggestions, use a regular issue.
