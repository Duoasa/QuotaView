<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView icon" width="160">
</p>

<h1 align="center">QuotaView</h1>

<p align="center">
  A simple, lightweight macOS companion for Codex quota and live task activity.
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.3.6-build.2"><img alt="Latest release" src="https://img.shields.io/github/v/release/Duoasa/QuotaView?display_name=tag"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.3.6-build.2/QuotaView-v0.3.6-build.2.zip"><strong>Download QuotaView v0.3.6 Build 2</strong></a>
  ·
  <a href="#privacy-by-design">Privacy</a>
  ·
  <a href="#build-and-test">Build from source</a>
  ·
  <a href="#license">Open source</a>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="Resources/QuotaView-Product-Hero.png" alt="QuotaView Codex Island live task activity on macOS" width="100%">
</p>

QuotaView is an open-source, lightweight, native macOS companion for the Codex account already signed in on your Mac. **Codex Island** turns live task activity into a glanceable surface beneath the menu bar, while the menu panel and desktop widgets keep period and Spark quota, estimated cost, Credits, token usage, and reset time close at hand. It stays focused without web scraping or reading login credentials from `~/.codex`.

## Why QuotaView

| | |
| --- | --- |
| **Codex Island** | Follow thinking, tool use, approvals, context compaction, subagents, completion, and failures through a live Metal-rendered activity surface. |
| **At a glance** | See period and Spark quota, reset countdowns, Credits, and availability from the menu bar or a native desktop widget. |
| **Usage overview** | Review the latest day, 30-day tokens, and a clearly labeled 30-day local cost estimate. |
| **Token Activity** | Review daily token usage in a compact monochrome chart with week, month, three-month, and six-month ranges. |
| **App updates** | Manually check the Stable channel or opt into a native 24-hour automatic check after installing this version. |
| **Local connection** | Communicates with a locally launched `codex app-server` process through its JSON-RPC interface. |
| **Simple by design** | Focuses on essential quota information with a compact, uncluttered interface. |
| **Lightweight** | Built natively with SwiftUI and AppKit, with no embedded browser runtime. |
| **Made to fit** | Choose what appears in the menu bar and which sections appear in the panel. |

## Quick start

1. Make sure ChatGPT or Codex is installed and signed in.
2. Download `QuotaView-v0.3.6-build.2.zip` from the [v0.3.6 Build 2 release](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.6-build.2).
3. Unzip it and open `QuotaView.app`.

> [!IMPORTANT]
> v0.3.6 Build 2 is signed with a Developer ID certificate, notarized by Apple, and
> stapled for offline Gatekeeper verification. It can be opened normally after
> unzipping, without using the Finder right-click workaround required by older
> unsigned builds.

The universal app supports macOS 14 or later on both Apple Silicon and Intel Macs. The first account request after launching from Finder may take 20–30 seconds; later refreshes are usually much faster.

## What it shows

- Current plan and service availability
- Period usage and remaining percentage
- Period and Spark quota with their own reset countdowns
- Plan quota and additional Credits as separate values
- Available quota reset credits
- Latest-day, 30-day, and lifetime token usage
- A 30-day local cost estimate, explicitly marked as an estimate rather than a bill
- Near-limit, exhausted, offline, and App Server error states

## Native experience

- Codex Island with expanded and compact states, a live Metal fluid sphere,
  status-aware color and motion, and automatic dismissal after completion
- Compact status item with a dynamically sized menu panel
- Automatic refresh every 60 seconds and manual refresh
- Manual Stable update checks and an opt-in 24-hour automatic check
- Configurable menu bar values and optional panel sections
- Frosted and clear glass appearances with light/dark adaptation
- Native Liquid Glass on macOS 26 and a Material fallback on macOS 14–15
- System-aware or fixed light/dark appearance
- English and Simplified Chinese interfaces
- Native Settings window for Menu Bar, Popover, Codex Island, Appearance, Language, and General options
- Native WidgetKit widgets in Small and Medium sizes

## What's new in 0.3.6: A Codex Island that fits your workflow

QuotaView 0.3.6 makes the stable single-task Codex Island visually and
behaviorally customizable while keeping its local connection and privacy
boundary unchanged.

<p align="center">
  <img src="Resources/QuotaView-0.3.6-Codex-Island-Settings.png" alt="QuotaView 0.3.6 Codex Island settings with visibility, Particle Orb and Ripple Glow previews, and compact and hide timing controls" width="100%">
</p>

- Adds a dedicated **Show Codex Island** switch. Hiding the island leaves the
  local Codex connection active, so it can resume with the current state.
- Adds a live animation picker with the existing **Particle Orb** and the new
  **Ripple Glow**. Both previews use the production renderer, and switching
  takes effect immediately.
- Maps Ripple Glow to all nine existing task states while preserving a circular
  silhouette, smooth state interpolation, and the approved faster animation
  rhythm.
- Adds stepped **Compact After Completion** timing from 5–60 seconds and
  **Hide After Compacting** timing from 5–120 seconds, with visible tick marks
  and the current value.
- Keeps Reduce Motion support, falls back to Particle Orb if the new Metal
  renderer is unavailable, and caches the Ripple Glow pipeline to avoid
  repeated shader compilation.
- Continues to use one stable single-task island. The separate multi-task
  Preview experiment is not included.

## What's new in 0.3.5: Usage overview and app updates

QuotaView 0.3.5 brings the expanded 0.3.4 usage overview into the first stable
version that can check future signed releases from inside the app.

<p align="center">
  <img src="Resources/QuotaView-0.3.5-Overview.png" alt="QuotaView 0.3.5 settings, Codex Island, widgets, quota, cost estimate, and Token Activity overview" width="100%">
</p>

- Adds an independently modeled, neutrally styled Spark weekly quota below the
  primary period quota; it hides cleanly when the account does not provide it.
- Moves the primary reset countdown into the period chart and removes the
  redundant standalone panel setting.
- Adds 30-day tokens and a monochrome 30-day cost estimate using the documented
  local reference rate. The value is explicitly labeled as an estimate, not a
  bill.
- Keeps Token Activity's complete 16-column grid while limiting its longest
  range to the most recent six months of available history.
- Uses consistent latest-day semantics across the summary, activity chart, and
  cost chart instead of describing an older bucket as today.
- Adds Sparkle 2.9.2 manual Stable update checks and a separate native setting
  for an optional 24-hour automatic check. Installing an update always requires
  confirmation.
- Keeps update traffic disabled for Debug, ad-hoc, unpackaged, wrong-bundle-ID,
  or unexpected-signing-team builds.

Because 0.3.5 Build 5 was the first release containing the updater, it required
a manual install. Approved installations can update to 0.3.6 Build 2 through
the Stable channel.

## What's new in 0.3.3: Token Activity

QuotaView 0.3.3 adds a compact daily Token Activity chart directly below the
usage metrics in the menu panel.

<p align="center">
  <img src="Resources/QuotaView-0.3.3-Token-Activity.png" alt="QuotaView 0.3.3 Token Activity chart, Codex Island, and desktop widget" width="100%">
</p>

- Switch between the last week, month, three months, and all available history;
  the last month is selected by default.
- Read every range as a complete 16-column rounded-square grid. Leading
  placeholders keep the grid aligned while real dates fill from the bottom
  right.
- Distinguish usage through a high-contrast, five-step monochrome palette:
  opaque white levels in Dark Mode and opaque grayscale levels in Light Mode.
- Hover a day for 0.5 seconds to see its date and compact K/M/B token usage.
- Keep the top of the menu fixed while the lower edge smoothly expands or
  contracts for the selected range.
- Show or hide the chart from Settings.

The 0.3.2 Preview 1 multi-task Codex Island remains available separately for
community testing. Its experimental multi-task implementation is not included
in the stable 0.3.3 source.

## 0.3.2 Preview 1: Multi-task Codex Island

> [!NOTE]
> 0.3.2 Preview 1 is an early-access release for validating multi-task Codex
> Island behavior. v0.3.6 Build 2 is the recommended stable version and does
> not include this experimental multi-task implementation.

[Download QuotaView 0.3.2 Preview 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.3.2-preview.1)

The core multi-task workflow is now available in one fixed Codex Island:

- Tracks multiple concurrent Codex sessions with independent status,
  lifecycle, completion, and cleanup.
- Adds a three-row task rail, a continuous sliding window for longer task
  lists, task counts, and a compact multi-task summary.
- Selects a primary task through stable priority arbitration while preventing
  ordinary background events from unnecessarily taking over the Island.
- Adds an optional “Follow Current Codex Task” mode that performs bounded,
  read-only Accessibility title matching and falls back automatically when a
  confident match is unavailable.
- Preserves the existing live Metal status surface, native glass transitions,
  compact/expanded states, Reduce Motion behavior, and accessibility actions.

Known preview limitations:

- Event-to-Island response can still feel delayed depending on Hook delivery,
  local scheduling, and the current Codex task state.
- Current-task following is title-based. It can lag or miss when titles are
  unresolved, duplicated, changed quickly, or affected by Codex UI changes.
- Task switching, title marquee behavior, and compact/expanded transition
  rhythm still need experience and performance refinement.
- This build is intended for preview validation. Use v0.3.6 Build 2 when stable
  behavior is more important than multi-task support.

## 0.3.1 Build 2 widget hotfix

- Restores Small and Medium widget data in notarized direct downloads by using
  the team-prefixed shared App Group required by macOS.
- Renames “Weekly Remaining” to “Period Remaining” across the app, widgets,
  tooltips, and accessibility copy to support variable Codex quota periods.
- Adds a release packaging check that prevents an incompatible App Group from
  reaching a notarized direct-distribution build.

## What's new in 0.3.1: Codex Island

v0.3.1 introduces **Codex Island**, QuotaView's biggest update yet: a native,
real-time macOS activity surface for Codex.

<p align="center">
  <img src="Resources/QuotaView-Codex-Island.gif" alt="Animated QuotaView Codex Island status demo" width="100%">
</p>

- Shows thinking, work, tool use, permission requests, context compaction,
  subagents, completion, and failures through a live Metal-rendered fluid
  sphere with state-specific motion and color.
- Expands immediately for new activity, compacts 20 seconds after completion,
  and hides after two minutes.
- Adds a guided setup flow that detects Hooks support, installs and updates the
  fixed-path QuotaView helper, preserves existing Hooks, and opens Codex's
  official trust review.
- Reports a successful connection only after Codex has been restarted and a
  real prompt event arrives from the trusted Hook.
- Keeps prompts, commands, arguments, tool output, and transcript paths private.
  Only minimal, sanitized lifecycle metadata is forwarded locally.
- Continues to include the native Small and Medium WidgetKit widgets introduced
  in v0.2.1.

## Privacy by design

QuotaView does **not**:

- scrape account web pages;
- read, copy, or store login credentials from `~/.codex`;
- store full account responses or authentication tokens.

QuotaView starts the local `codex app-server` process and requests account data over JSON-RPC. It stores only the latest successful refresh time, availability state, a short error summary, and display preferences in its own macOS preferences domain.

Version 0.3.5 is read-only by default and contains no live account-operation
executor. The quota reset flow remains a local demo. The architecture reserves
separate, explicitly authorized official operations for a future release
without allowing refreshes to trigger side effects.

The main app writes only a bounded, sanitized snapshot to its App Group for the
WidgetKit extension. The snapshot contains no authentication token, cookie,
account identifier, complete server response, or usage history.

Codex Island uses official Codex Hooks and a signed local helper. It forwards
only hashed session identifiers, the final workspace path component, event
type, coarse tool category, session source, and timestamp. It never forwards
prompts, commands, arguments, tool output, or transcript paths, and it never
bypasses the official Hook trust confirmation.

For local diagnostics:

```bash
defaults read com.quotaview.menubar
```

The app target disables App Sandbox because it must launch the locally installed `codex app-server`.

## Requirements

- macOS 14 or later
- ChatGPT/Codex installed and signed in
- Swift 6 or Xcode 16+ only when building from source

QuotaView looks for the Codex executable in this order:

1. `CODEX_EXECUTABLE`
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. The current `PATH`

## Current limitations

- Version 0.3.5 currently supports Codex only; more official providers are
  planned through the static provider registry.
- The quota reset interface is a safety-focused demo and does not call `account/rateLimitResetCredit/consume`.
- The App Server schema can vary with the installed Codex version.

## Build and test

Clone the repository and run the unit tests:

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
```

Run the read-only data probe:

```bash
swift run QuotaViewProbe
```

The probe prints the plan, quota percentages, reset time, Credits balance, and lifetime token usage. It never prints login credentials.

Run the app during development:

```bash
swift run QuotaView
```

Or create the Universal release app and ZIP:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/QuotaView.app
```

The build script prefers a Developer ID Application identity, then an Apple Development identity. Those Team ID-bearing identities keep Hardened Runtime enabled. When neither identity is available, the script falls back to an ad-hoc signature without Hardened Runtime so the embedded framework remains loadable. Only Developer ID Application builds can use the notarization path:

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="<keychain-profile>" \
./scripts/build-app.sh
```

To use Xcode, open `QuotaView.xcodeproj`, select the shared **QuotaView** scheme and **My Mac**, then run or test.

## Data protocol

After initialization, the client requests:

```text
initialize
initialized
account/rateLimits/read
account/usage/read  # only when either token section is enabled
```

| UI value | App Server field |
| --- | --- |
| Availability | `rateLimitReachedType`, `spendControlReached`, `primary.usedPercent` |
| Used quota | `primary.usedPercent` |
| Remaining quota | `100 - primary.usedPercent` |
| Reset time | `primary.resetsAt` |
| Credits | `credits.balance`, `credits.unlimited` |
| Reset credits | `rateLimitResetCredits.availableCount` |
| Tokens | `summary.lifetimeTokens`, `dailyUsageBuckets` |

Credits and remaining plan quota are separate concepts and are never combined in the UI.

## Production source structure

```text
Sources/
├── QuotaView/              # SwiftUI views, settings, and AppKit menu panel
├── QuotaViewActivityHook/  # Signed, privacy-preserving Codex Hook helper
├── QuotaViewCore/          # Domain, providers, refresh, and account-operation boundary
├── QuotaViewFutureContracts/# Unlinked history, chart, display, and notification contracts
├── QuotaViewWidgetContract/# Foundation-only bounded widget snapshot contract
├── QuotaViewWidget/        # Native Small and Medium WidgetKit extension
└── QuotaViewProbe/         # Read-only command-line probe
Resources/
├── Assets.xcassets/        # App, menu bar, and interface artwork
└── Fonts/                  # Bundled Asta Sans font files
Tests/
└── QuotaViewCoreTests/     # Domain, app behavior, process, and contract tests
```

## License

QuotaView is open-source software released under the [MIT License](LICENSE).

## Feedback and contributions

Bug reports, compatibility reports, and focused feature proposals are welcome. Start with the [issue templates](https://github.com/Duoasa/QuotaView/issues/new/choose). Before preparing a code change, read the [SDD specification index](docs/specs/README.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

Please never include authentication tokens, credentials, or an unredacted `~/.codex` file in an issue.
