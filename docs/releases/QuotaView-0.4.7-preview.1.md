# QuotaView 0.4.7 Preview 1 — Custom Proxy

This preview adds an app-scoped proxy for QuotaView's Codex quota and account usage requests. It is intended for users whose network access requires a separately configured proxy, including a proxy exposed from Docker.

**Manual download only.** This is a GitHub pre-release and is not included in the appcast. **0.4.6 Build 2 remains the recommended stable release.** Promotion to the update feed will be considered only after real-world feedback.

## What's included

- A new **Settings → Proxy** page, off by default.
- HTTP and SOCKS5 proxies without username/password authentication.
- Separate protocol, server address, and port fields; Save applies changes.
- **Test Connection** queries Codex quota using the draft settings without saving them. It reports success only after receiving valid quota data.
- **Restore Defaults** turns off the custom proxy and restores the original connection behavior.
- SOCKS5 compatibility through a temporary local bridge. HTTPS remains end-to-end encrypted.

The setting applies to QuotaView's own quota-query process. Local Island activity and current-task Token reading retain the 0.4.6 architecture. This preview does not configure the system proxy or other Codex instances.

## How to test

1. Quit the running QuotaView instance, extract the preview ZIP, and open QuotaView. Do not run the stable app and preview simultaneously.
2. Open **Settings → Proxy**, enable **Custom proxy**, and choose **HTTP** or **SOCKS5**.
3. Enter the server address (for example, `127.0.0.1`) and your proxy's actual port. Enter only an IP or hostname in the address field, without `http://` or `socks5://`.
4. Click **Test Connection**, then **Save**. Check that account quota refreshes successfully.
5. Stop the proxy temporarily and confirm that failure is reported. Restart it and retry. Finally, test **Restore Defaults**.

Please report your macOS and Codex versions, proxy type and software, whether it runs in Docker, the connection-test result, and whether quota refresh recovers after a disconnect. Do not include credentials, account tokens, or private conversation content. Feedback can be added to [issue #49](https://github.com/Duoasa/QuotaView/issues/49).

## Validation and limits

- 186 local Swift tests passed, including HTTP/SOCKS5 simulated-network success, refusal, timeout, disconnect, recovery, and cancellation cases.
- Installed Codex CLI 0.153.4 completed HTTPS quota queries through both simulated proxy protocols using an isolated test account and temporary test certificate authority.
- GitHub CI passed with zero failures; the installed-Codex test is opt-in and was verified locally instead.
- Universal macOS build for Apple silicon and Intel; macOS 14 or later.
- Real-world proxy compatibility, visual behavior, and accessibility still need user feedback. Authenticated proxies and PAC configuration are outside this preview's scope.

To return to stable, restore the proxy defaults, quit the preview, and reinstall [0.4.6 Build 2](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.6-build.2). Both versions use the same local preferences. The stable update feed will not offer this preview.
