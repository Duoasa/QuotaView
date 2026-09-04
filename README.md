<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView icon" width="160">
</p>

<h1 align="center">QuotaView · Codex Island for macOS</h1>

<p align="center">
  Keep Codex visible while you work.
</p>

<p align="center">
  Live status, progress, approvals, turn tokens, completion receipts, and quota—inside one native Island.
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.4.5-build.1"><img alt="Latest release" src="https://img.shields.io/github/v/release/Duoasa/QuotaView?display_name=tag"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.4.5-build.1/QuotaView-v0.4.5-build.1.zip"><strong>Download QuotaView v0.4.5 Build 1</strong></a>
  ·
  <a href="#get-started">Get started</a>
  ·
  <a href="#privacy-by-design">Privacy</a>
  ·
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="Resources/QuotaView-Product-Hero.png" alt="QuotaView Codex Island showing live task progress and quota on macOS" width="100%">
</p>

Codex can keep working after its window leaves the foreground, but its state should not disappear with it. QuotaView turns the active task into a native, click-through **Codex Island** beneath the menu bar. It shows what Codex is doing, how far a planned task has progressed, when approval is waiting, how many tokens the turn has used, and what remains when the task finishes.

QuotaView is open source, lightweight, and local-first. Current Codex releases work on first launch with no Hook setup. Quota and usage stay one click away in the menu panel and native widgets.

## The Codex Island

The Island is the primary QuotaView experience—not an add-on to a quota dashboard.

| Moment | What the Island shows |
| --- | --- |
| **Thinking and working** | Task title, current operation, live state, turn token usage, and a progress-aware Quantum Noise surface. |
| **Planned work** | Completed, active, and pending plan steps become conservative progress. Only a real task completion reaches 100%. |
| **Approval required** | The waiting state appears immediately. After 10 seconds, a yellow outline and halo make the blocked task harder to miss. |
| **Task completed** | The expanded Island becomes a completion receipt with turn tokens on the left and current remaining quota on the right. |
| **Compact completion** | “Completed” stays visible beside a small, risk-colored remaining-quota ring before the Island hides. |
| **Hover** | The whole Island becomes 80% transparent and remains click-through, keeping the content behind it readable. |

The Island understands thinking, work, tool calls, approvals, context compaction, completion, interruption, and failure. It can follow the screen where Codex is visible, respects Reduce Motion, adapts to light and dark appearance, and lets you tune its completion timing.

<p align="center">
  <img src="Resources/QuotaView-0.4.5-Activity-Bridge.png" alt="QuotaView 0.4.5 Codex Island showing live task state and turn token usage" width="100%">
</p>

## Ready when Codex starts

QuotaView 0.4.5 adds a read-only local activity bridge for current Codex releases:

- **No first-run Hook setup.** Open QuotaView and start a Codex task; the Island discovers active local work automatically.
- **Fast state updates.** The bridge follows appended local task events, including lifecycle, plan counts, coarse tool categories, and token totals.
- **Safe compatibility fallback.** A shared local App Server connection and the signed Activity Hook remain fallback paths for older environments.
- **No control over Codex.** The bridge observes existing activity; it does not launch, modify, or write to Codex data.

## Quota and usage, one click away

The Island leads the experience, while the rest of QuotaView provides the context around the task:

| Surface | What it is for |
| --- | --- |
| **Menu bar** | Keep a chosen quota value or reset countdown visible without opening a window. |
| **Menu panel** | Review every available Codex quota window, Spark quota, reset times, Credits, latest-day and 30-day tokens, and lifetime usage. |
| **Token Activity** | Scan daily token usage in a compact monochrome grid across week, month, three-month, and six-month ranges. |
| **Cost estimate** | See a clearly labeled local 30-day estimate. It is an estimate, not a bill. |
| **Widgets** | Place native Small or Medium WidgetKit views on the desktop for quota and reset information. |
| **Updates** | Check the Stable channel manually or opt into a native check every 24 hours. Installing an update always requires confirmation. |

## Get started

1. Make sure ChatGPT or Codex is installed and signed in.
2. Download `QuotaView-v0.4.5-build.1.zip` from the [v0.4.5 Build 1 release](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.5-build.1).
3. Unzip it and open `QuotaView.app`.
4. Start a Codex task. Current Codex releases connect automatically; no Hook installation or restart is required.

> [!IMPORTANT]
> v0.4.5 Build 1 is signed with a Developer ID certificate, notarized by Apple,
> and stapled for offline Gatekeeper verification. It opens normally after
> unzipping, without the Finder right-click workaround used by older unsigned
> builds.

The Universal app supports macOS 14 or later on Apple Silicon and Intel Macs. The first account request after launching from Finder may take 20–30 seconds; later refreshes are usually much faster.

## Privacy by design

QuotaView does **not**:

- scrape Codex or ChatGPT account pages;
- read, copy, or store login credentials from `~/.codex`;
- ingest prompts, reasoning, messages, commands, arguments, tool output, diffs, or completion text into its model or diagnostics;
- store authentication tokens, cookies, complete account responses, or raw task transcripts.

For current Codex releases, the activity bridge reads only bounded local task records under `~/.codex/sessions`. It projects hashed session and turn identifiers, the final workspace path component, lifecycle state, plan-status counts, coarse tool category, timestamps, and token numbers. The signed Hook fallback follows the same sanitized boundary.

Quota information is requested from the locally installed `codex app-server` over JSON-RPC. QuotaView stores only display preferences, compact availability/error state, and the latest successful refresh time in its own preferences domain. A bounded, sanitized snapshot is written to the app's App Group for WidgetKit; it contains no credential, account identifier, complete response, or usage history.

QuotaView is read-only by default. The quota-reset interface is a local safety demo and never calls `account/rateLimitResetCredit/consume`.

The main app target disables App Sandbox because it needs to communicate with the locally installed Codex service.

## Requirements and current scope

- macOS 14 or later
- ChatGPT/Codex installed and signed in
- Swift 6 or Xcode 16+ only when building from source
- Current stable support is focused on Codex
- The stable Island follows one primary task; the separate [0.3.2 Preview 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1) contains the experimental multi-task experience
- Cost values are local estimates, not billing records
- Codex protocol details can change between installed versions; QuotaView keeps compatibility fallbacks for that reason

QuotaView looks for the Codex executable in this order:

1. `CODEX_EXECUTABLE`
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. The current `PATH`

## Build from source

Clone the repository and run the test suite:

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
```

Run the read-only quota probe:

```bash
swift run QuotaViewProbe
```

Run the app during development:

```bash
swift run QuotaView
```

Or build the Universal app and ZIP:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/QuotaView.app
```

The build script prefers a Developer ID Application identity, then an Apple Development identity. If neither is available, it falls back to an ad-hoc signature suitable for local testing. Only a Developer ID Application build can use the notarization path:

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

To use Xcode, open `QuotaView.xcodeproj`, select the shared **QuotaView** scheme and **My Mac**, then run or test.

## Data sources

Quota and usage data are requested after initialization:

```text
initialize
initialized
account/rateLimits/read
account/usage/read  # requested only when a token section is enabled
```

| QuotaView value | Codex App Server field |
| --- | --- |
| Availability | `rateLimitReachedType`, `spendControlReached`, `primary.usedPercent` |
| Used quota | `primary.usedPercent` |
| Remaining quota | `100 - primary.usedPercent` |
| Reset time | `primary.resetsAt` |
| Credits | `credits.balance`, `credits.unlimited` |
| Reset credits | `rateLimitResetCredits.availableCount` |
| Tokens | `summary.lifetimeTokens`, `dailyUsageBuckets` |

Credits and remaining plan quota are separate concepts and are never combined in the UI.

## Project structure

```text
Sources/
├── QuotaView/                    # SwiftUI UI, settings, and AppKit surfaces
├── QuotaViewActivityHook/        # Signed compatibility Hook helper
├── QuotaViewActivityHookSupport/ # Shared sanitized Hook protocol support
├── QuotaViewCore/                # Domain, providers, activity bridge, and refresh
├── QuotaViewFutureContracts/     # Unlinked future-facing contracts
├── QuotaViewWidgetContract/      # Bounded WidgetKit snapshot contract
├── QuotaViewWidget/              # Native Small and Medium widgets
└── QuotaViewProbe/               # Read-only command-line quota probe
Tests/
└── QuotaViewCoreTests/           # Domain, bridge, lifecycle, and app tests
```

## Releases and project status

- **Recommended stable:** [QuotaView v0.4.5 Build 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.4.5-build.1)
- **Experimental multi-task preview:** [QuotaView v0.3.2 Preview 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1)
- **Release history and verification:** [VERSION_HISTORY.md](VERSION_HISTORY.md)
- **Current engineering handoff:** [HANDOFF.md](HANDOFF.md)
- **Design and behavior specifications:** [docs/specs/README.md](docs/specs/README.md)

## Open source and contributing

QuotaView is available under the [MIT License](LICENSE).

Bug reports, Codex compatibility reports, and focused feature proposals are welcome. Start with the [issue templates](https://github.com/Duoasa/QuotaView/issues/new/choose), then read the [specification index](docs/specs/README.md) and [CONTRIBUTING.md](CONTRIBUTING.md) before preparing a code change.

Never include authentication tokens, credentials, raw task transcripts, or an unredacted `~/.codex` file in an issue.

## Community

Join the QuotaView QQ feedback group to report bugs, discuss compatibility, or share ideas.

**QQ group: 1108649282**

<p align="center">
  <img src="Resources/QuotaView-QQ-Feedback-Community.jpg" alt="QuotaView QQ feedback group QR code, group number 1108649282" width="320">
</p>
