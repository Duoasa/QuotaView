# QuotaView 0.4.7 Build 2 — Custom Proxy

QuotaView 0.4.7 adds a custom proxy for Codex quota and account usage requests. Following the public preview and user feedback confirming proxy connectivity, this release promotes the feature to stable.

## What's new

- **Settings → Proxy**, off by default, with HTTP and SOCKS5 support.
- Separate server address and port fields for proxies without username/password authentication.
- **Test Connection** validates quota access using draft settings; **Save** applies them.
- **Restore Defaults** disables the custom proxy and restores the original connection behavior.
- SOCKS5 compatibility through a temporary local bridge, preserving end-to-end HTTPS and certificate validation.

The proxy applies to QuotaView's own quota and account usage requests. Local Island activity and current-task Token reading retain the existing architecture. Authenticated proxies, PAC, and system proxy configuration are outside this release's scope.

## Completion timing

The completed Island still shrinks after 20 seconds and hides 100 seconds later by default. Both delays are configurable in Island settings. Targeted review and a real-duration test did not reproduce indefinite display after shrinking; no production timing change was made for this release.

## Install and update

Download the Universal ZIP for Apple silicon and Intel (macOS 14 or later), or use **Check for Updates** through the stable update feed. Quit the running QuotaView instance before replacing it manually. Preview users can update to this stable build as well.

The previous stable [0.4.6 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.6-build.2) remains available for rollback. Preview 1 is retained as historical test evidence.

## Verification

- 190 local Swift tests passed with zero failures or skips, including installed-Codex HTTPS proxy tests and the real 120-second completion countdown.
- Universal App, Widget, and Hook binaries for Apple silicon and Intel.
- Developer ID signing, Hardened Runtime, Apple notarization, and a stapled ticket.
- Archive: `QuotaView-v0.4.7-build.2.zip` (13,669,247 bytes).
- SHA-256: `de828160dc89fd7990959944ed3a1695936d0d080d472eb3e8c908c2ba8e6a8e`.

The public ZIP matches the local release byte-for-byte and passes strict signature, stapled-ticket, and Gatekeeper checks. The live appcast and archive signatures were verified against the application's bundled public key.

[Main CI](https://github.com/Duoasa/QuotaView/actions/runs/34494932631) passed with zero failures. Two opt-in tests (installed Codex and the real-duration countdown) were skipped in CI and passed locally.
