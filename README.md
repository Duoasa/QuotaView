<img src="Resources/QuotaView-ICON.png" alt="QuotaView icon" width="200">

[**English**](README.md) | [简体中文](README.zh-CN.md)

# QuotaView

QuotaView is a native macOS menu bar app that puts AI service quotas, usage, balances, and reset times in one place. Version 0.1.5 starts with the locally signed-in Codex account, with support for more AI providers planned.

QuotaView does not scrape web pages or read, copy, or store login credentials from `~/.codex`. It starts the local `codex app-server` process and reads account data through its official JSON-RPC interface.

## Preview

![QuotaView app preview](Resources/QuotaView-Preview.jpg)

## Download

Download `QuotaView-v0.1.5.zip` from [GitHub Releases](https://github.com/Duoasa/QuotaView/releases), unzip it, and open `QuotaView.app`.

The current v0.1.5 download is Build 6, a hotfix that corrects the availability badge shape and removes color bleeding around its background.

The universal app supports macOS 14 or later on both Apple Silicon and Intel Macs. The v0.1.5 download is signed with an Apple Development certificate but is not notarized. If macOS blocks the first launch, right-click `QuotaView.app` in Finder and choose **Open**.

## Features

- Shows whether the current AI service is available, near its limit, or exhausted.
- Displays the live subscription, weekly used quota, and remaining percentage.
- Shows the countdown to the next quota reset.
- Separates plan quota from additional Credits balance.
- Presents available quota reset credits as a dedicated action.
- Includes a quota reset detail view, risk acknowledgement, and final confirmation.
- Keeps quota reset in demo mode without calling the real consume endpoint.
- Uses a compact native status item and a dynamically sized custom menu panel.
- Offers frosted and clear glass appearances with light/dark adaptation;
  macOS 26 uses native Liquid Glass and macOS 14–15 retain a Material fallback.
- Uses QuotaView's blue-violet visual identity throughout the interface.
- Lets you choose which values appear in the menu bar and which of the six
  content sections appear in the panel.
- Includes a redesigned native Settings window with Menu Bar, Popover,
  Appearance, Language, and General sections.
- Uses the current macOS accent color for native settings controls.
- Supports system-aware or fixed light/dark appearance.
- Supports system-aware or fixed Simplified Chinese and English interfaces.
- Displays recent daily and lifetime token usage.
- Refreshes automatically every 60 seconds and supports manual refresh.
- Locates Codex from ChatGPT, Homebrew, a custom path, or the current `PATH`.
- Handles offline, missing installation, and App Server error states.

The first account request after launching from Finder may take 20–30 seconds. QuotaView allows a 45-second cold-start response window; later refreshes are usually much faster.

## Privacy

QuotaView stores only the latest successful refresh time, availability state, a short error summary, and your display preferences in its own macOS preferences domain. It does not store tokens or full account responses.

For diagnostics:

```bash
defaults read com.quotaview.menubar
```

## Requirements

- macOS 14 or later
- Swift 6 or Xcode 16+
- ChatGPT/Codex installed and signed in

QuotaView looks for the Codex executable in this order:

1. `CODEX_EXECUTABLE`
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. The current `PATH`

## Verify

Run the unit tests:

```bash
swift test
```

Run the read-only data probe:

```bash
swift run QuotaViewProbe
```

The probe prints the plan, quota percentages, reset time, Credits balance, and lifetime token usage. It never prints login credentials.

## Build the App

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/QuotaView.app
```

The build script creates a Universal Xcode Release build with the complete asset catalog:

```text
dist/QuotaView.app
dist/QuotaView-v0.1.5.zip
```

Without additional options, the script prefers an installed Developer ID Application identity, then an Apple Development identity, and falls back to an ad-hoc signature with Hardened Runtime. To choose an identity explicitly:

```bash
CODESIGN_IDENTITY="Apple Development: Name (ID)" ./scripts/build-app.sh
```

For public distribution, use a Developer ID Application identity and an existing `notarytool` keychain profile:

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="QuotaView-notary" \
./scripts/build-app.sh
```

The versioned ZIP preserves the signed macOS app bundle for GitHub Releases. Apple Development signatures are for development and testing; public distribution should use Developer ID signing and notarization.

## Run During Development

```bash
swift run QuotaView
```

QuotaView appears only in the macOS menu bar and does not show a Dock icon.

## Xcode

Open the native Xcode project, select the shared `QuotaView` scheme and **My Mac**, then run or test:

```bash
open QuotaView.xcodeproj
```

The project contains three targets:

- `QuotaView`: the menu bar app
- `QuotaViewCore`: reusable account models and App Server communication
- `QuotaViewTests`: core model and process communication tests

The app target disables App Sandbox because it must launch the locally installed `codex app-server`. Select an Apple Developer Team in **Signing & Capabilities** before a signed production distribution.

## Data Protocol

After initialization, the client requests:

```text
initialize
initialized
account/rateLimits/read
account/usage/read
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

Version 0.1.5 implements the quota reset interaction and safety confirmations but does not send `account/rateLimitResetCredit/consume`. A future implementation should add idempotency keys, explicit result handling, and protocol compatibility tests before enabling real quota resets.

## Project Structure

```text
Sources/
├── QuotaView/              # SwiftUI views, settings, and AppKit menu panel
├── QuotaViewCore/          # Provider client, executable locator, and models
└── QuotaViewProbe/         # Read-only command-line probe
Resources/
├── Assets.xcassets/        # App, menu bar, and interface artwork
└── Fonts/                  # Bundled Asta Sans font files
Tests/
└── QuotaViewCoreTests/     # Model mapping and process communication tests
```

## Roadmap

1. Add active task status and real-time notifications.
2. Add launch-at-login with `ServiceManagement`.
3. Add historical trends and quota alerts.
4. Add a WidgetKit extension backed by an App Group.
5. Add more AI providers.
6. Add Developer ID signing, notarization, and automatic updates.

The App Server schema depends on the installed Codex version. Release CI should run `codex app-server generate-json-schema` and include protocol compatibility tests.
