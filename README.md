<p align="center">
  <img src="Resources/QuotaView-ICON.png" alt="QuotaView icon" width="160">
</p>

<h1 align="center">QuotaView · Agent Island for macOS</h1>

<p align="center">
  Keep your coding agents and usage in view.
</p>

<p align="center">
  Live status, progress, approvals, turn tokens, completion receipts, and quota—inside one native Island.
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.7.9-build.1"><img alt="Latest release" src="https://img.shields.io/github/v/release/Duoasa/QuotaView?display_name=tag"></a>
  <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.7.9-build.1/QuotaView-v0.7.9-build.1.zip"><strong>Download QuotaView v0.7.9 Build 1</strong></a>
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
  <img src="Resources/QuotaView-0.7.9-Cover.jpg" alt="QuotaView Codex Island showing live task progress and quota on macOS" width="100%">
</p>

QuotaView brings local coding tasks into a native macOS Island. Follow **Codex, Claude Code, DSH, and Kimi Code**, with task status, supported confirmations, completion states, and available usage information in one place.

## What's new in 0.7.9

- **More agents.** Manage Codex, Claude Code, DSH, and Kimi Code in one connection list. Compatible DSH-based clients can use their own data directories.
- **More personal choices.** Adjust the expanded width, privacy mode, automatic popup behavior, and optional usage modules. Three task effects offer live previews that pause when hidden.
- **A tidier everyday view.** Refined settings, provider icons, task transitions, and hover details. Narrower cost and Token activity charts scroll horizontally and open on recent data.

## Agent support

| Agent | Tasks and confirmations | Usage |
| --- | --- | --- |
| **Codex** | Automatic local task discovery, optional activity Hook, and supported in-Island confirmations. | Available account quota, reset times, Credits, Tokens, and estimated cost. |
| **Claude Code** | Opt-in Hooks for task status and supported permission requests. | Local Token history and estimated cost; official quota windows when status-line collection is enabled. |
| **DSH** | Native session plugin for lifecycle, tools, compaction, and permission reminders. Compatible custom clients appear under DSH. | Task Token counts when supplied by events; no account quota or historical cost dashboard. |
| **Kimi Code** | Hooks for lifecycle, tools, compaction, and permission reminders. | No account quota or historical cost dashboard. |

DSH and Kimi Code permissions are confirmed in the original client. Available fields depend on the agent and version; unavailable values keep their placeholders. DSH and Kimi integrations are opt-in. See the [integration contract](docs/specs/agent-integrations.md) for compatibility boundaries.

## Make it fit your workflow

- Follow concurrent tasks and supported subagents beneath the menu bar.
- Set task-list and usage-page width from **560–680 pt**, with safe limits for the physical MacBook notch.
- Choose **State Smoke, Quantum Noise, or Liquid Wave**, with live settings previews and Reduce Motion support.
- Control privacy, automatic expansion, and how long task notifications stay open.
- Show or hide cost estimates and Token activity; explore daily, weekly, and cumulative views.
- Use the menu bar and native desktop widgets for quick quota checks.

<p align="center">
  <img src="Resources/QuotaView-0.7.5-Usage.png" alt="QuotaView quota, Token activity, and estimated cost dashboard" width="100%">
</p>

## Get started

1. Download [QuotaView 0.7.9 Build 1](https://github.com/Duoasa/QuotaView/releases/tag/v0.7.9-build.1), unzip it, and open `QuotaView.app`.
2. Open **Settings → Connections** and enable the agents you use.
3. Codex tasks are discovered locally. After configuring Hooks or a DSH plugin, start a new session or restart the relevant client as indicated in settings.

Requires **macOS 14 or later**. The Universal app supports Apple silicon and Intel Macs. Agent clients must be installed and configured separately.

Updates use the Stable channel. Automatic checks are optional; installing an update requires confirmation.

## Privacy by design

Task information is processed locally. QuotaView does not send task content to a QuotaView service or collect login credentials. Connections use local APIs, bounded session records, Hooks, or native plugins.

Enabling an integration may modify the client's configuration. QuotaView backs up the configuration and manages only its own marked entries. DSH custom clients keep their own data directories and identities.

Cost values are estimates, not bills. The quota-reset view remains a local demonstration and does not consume real reset credits. Do not include credentials or raw session records in bug reports.

## Build from source

```bash
git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
swift run QuotaView
```

Use Swift 6 or a compatible Xcode toolchain. For the full app and widget, open `QuotaView.xcodeproj`, select **QuotaView** and **My Mac**, then run.

Distribution packaging uses `scripts/build-app.sh`. Developer ID signing and notarization require your own signing identity, notary profile, and a recoverable encrypted backup of the Sparkle update key. See the [release workflow](docs/workflow/RELEASE.md).

## Project and feedback

- [Current release](https://github.com/Duoasa/QuotaView/releases/tag/v0.7.9-build.1) · [Previous stable 0.7.7](https://github.com/Duoasa/QuotaView/releases/tag/v0.7.7-build.1)
- [Version history and release evidence](VERSION_HISTORY.md) · [Development handoff](HANDOFF.md)
- [Design and behavior specifications](docs/specs/README.md) · [Contributing](CONTRIBUTING.md)
- [Report an issue](https://github.com/Duoasa/QuotaView/issues/new/choose), or use **Settings → Bug Feedback**.

Open source under the [MIT license](LICENSE).

**QQ feedback group: 1108649282**

<p align="center">
  <img src="Resources/QuotaView-QQ-Feedback-Community.jpg" alt="QuotaView QQ feedback group QR code" width="280">
</p>
