# QuotaView 0.4.7 Build 3

This release fixes the Island text issue that led to the withdrawal of 0.4.7 Build 2 and restores custom proxy support to the stable channel.

## Changes

- Fix completion percentages such as **27%** losing the percent sign. Numbers and symbols now receive independent, pixel-aligned space.
- Prevent exact-fit text from being truncated by floating-point rounding, and keep long mixed-language/emoji text within its label bounds.
- Align the proxy protocol selector with the other settings controls and add colored rounded icons to the settings sidebar.
- Preserve the standalone **Island Text Console** in the repository for future manual development checks; it is separate from the shipped app and uses explicit debug data.

## Custom proxy

**Settings → Proxy** supports HTTP and SOCKS5 without username/password authentication. It is off by default and includes server/port fields, Test Connection, Save, and Restore Defaults. It affects QuotaView's quota and account usage queries; local Island activity and current-turn Token reading keep their existing data sources.

Completion timing is unchanged: the default is 20 seconds before shrinking, followed by another 100 seconds before hiding. Both delays remain configurable.

## Install and update

Download `QuotaView-v0.4.7-build.3.zip`, or use QuotaView's update check after this release enters the stable feed. Internal update version **22** supersedes both 0.4.6 Build 2 and the withdrawn 0.4.7 Build 2. The stable rollback release remains [0.4.6 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.6-build.2).

## Verification

- 197 Swift tests: zero failures; both normally skipped opt-in cases also passed separately, including installed-Codex HTTP/SOCKS5 queries and the real 120-second completion countdown.
- Seven text-rendering regression tests covering all percentages, display scales, missing values, fallback fonts, mixed scripts, and long text.
- Owner confirmation of the current Island content display; broader accessibility combinations were not separately accepted.
- Universal Apple silicon and Intel app, Widget, Core framework, and activity helper.
- Developer ID signature, Hardened Runtime, Apple notarization, stapled ticket, and Gatekeeper acceptance.
- Archive size: **13,768,352 bytes**.
- SHA-256: `8fcfc1aea49578d8d19a7377dbd47e992169207675b75a190df667dc551c5c59`.

[PR #50](https://github.com/Duoasa/QuotaView/pull/50) is merged. [PR CI](https://github.com/Duoasa/QuotaView/actions/runs/34603691053) and [main CI](https://github.com/Duoasa/QuotaView/actions/runs/34604031876) passed. Main CI initially failed because an unchanged proxy fixture did not write its port file within its five-second startup window; the same commit passed on rerun without changing assertions.

The public ZIP matches the final archive byte-for-byte and passed signature, stapled-ticket, Gatekeeper, and launch smoke checks. The live appcast and ZIP signatures were verified against the app's bundled public key. The stable feed contains internal versions 22, 19, and 18. Withdrawn Build 2 is retained as a draft outside the public release timeline, with its tag and asset preserved.
