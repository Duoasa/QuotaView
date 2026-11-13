<p align="center"><img src="docs/media/readme/0.9.1/app-icon.png" alt="QuotaView" width="112"></p>

<h1 align="center">QuotaView</h1>

<p align="center"><strong>Dynamic Island for AI agents.</strong><br>Tasks, approvals, and usage, together at the top of your desktop.</p>

<p align="center"><a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.9.3-build.1"><img src="https://img.shields.io/badge/macOS-v0.9.3_Build_1-blue" alt="0.9.3 Build 1"></a> <img src="https://img.shields.io/badge/macOS-14%2B-111111" alt="macOS 14+"> <a href="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml"><img src="https://github.com/Duoasa/QuotaView/actions/workflows/ci.yml/badge.svg" alt="CI"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT"></a></p>

<p align="center"><a href="https://github.com/Duoasa/QuotaView/releases/download/v0.9.3-build.1/QuotaView-v0.9.3-build.1.zip"><strong>Download for macOS</strong></a> · <a href="#highlights">Highlights</a> · <a href="#supported-agents">Supported agents</a> · <a href="#installation">Install</a> · <a href="#windows">Windows notes</a></p>

<p align="center"><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a></p>

<p><img src="docs/media/readme/0.9.1/en/cover.jpg" alt="QuotaView English product cover"></p>

<p>QuotaView brings your AI agents’ work and usage together at the top of your desktop. See who is working, who needs a decision, and who just finished. Expand the Island for task details, supported requests, or a closer look at your remaining quota.</p>


<a name="highlights"></a>
<h2>Highlights</h2>

<p>A full feature overview of <strong>macOS 0.9.3</strong>. See the <a href="#windows">separate Windows notes</a> for its version and feature scope.</p>

<table class="highlights">
<tr>
<td width="50%" valign="top">
<p><strong>👀 Every agent, at a glance</strong></p>
<ul>
<li>Follow multiple local sessions through thinking, working, waiting, completed, and failed states.</li>
<li>See available task titles, models, Tokens, elapsed time, and active tools on each card.</li>
<li>Expand task details and public completion content, with subagent activity when the source provides parent relationships.</li>
<li>Archive tasks, hover to expand, or pin the Island open to keep current work in view.</li>
</ul>
</td>
<td width="50%" valign="top">
<p><strong>✋ Approvals and answers in place</strong></p>
<ul>
<li>Review commands, working directories, reasons, and permission scopes before deciding.</li>
<li>Allow or deny supported Codex, Claude Code, and DSH permission requests from the Island.</li>
<li>Answer supported Codex questions and Claude Code single-choice questions in place.</li>
<li>Unsupported requests and forms return to the original client for confirmation.</li>
</ul>
</td>
</tr>
<tr>
<td width="50%" valign="top">
<p><strong>📊 Quota, Tokens, and cost</strong></p>
<ul>
<li>Switch between Codex and Claude Code to see available five-hour and weekly limits and reset times.</li>
<li>Explore Token history, estimated model costs, and activity heatmaps.</li>
<li>See available Codex plan and Credits data; enable Claude official limit collection when needed.</li>
<li>Keep usage visible with a floating capsule and Small / Medium desktop widgets.</li>
</ul>
</td>
<td width="50%" valign="top">
<p><strong>🎟️ Reset credits before they expire</strong></p>
<ul>
<li>See available Codex reset credits and a time-ordered list of those expiring within a week.</li>
<li>Scan a compact “Expiring soon + time” row; hover for the full date and time zone.</li>
<li>Protect credits with a usage switch, confirm each reset, and retry interrupted operations safely.</li>
<li>Copy /limit-reset for Claude Code and run it in the original client.</li>
</ul>
</td>
</tr>
<tr>
<td width="50%" valign="top">
<p><strong>🎨 Make it fit your desktop</strong></p>
<ul>
<li>Choose liquid glass or classic solid color, with live previews of state smoke, quantum noise, and liquid waves.</li>
<li>Adjust expanded width, capsule visibility, privacy, and auto-expand; completed cards use a neutral background.</li>
<li>Follow the active window or pointer across displays, or keep the Island on a selected screen.</li>
<li>Use Simplified Chinese, Traditional Chinese, English, Japanese, Korean, or Spanish.</li>
</ul>
</td>
<td width="50%" valign="top">
<p><strong>⚡ Local processing, work on demand</strong></p>
<ul>
<li>Manage 10 agent integration entries with independent switches and connection status.</li>
<li>Process task information locally through local APIs, session records, hooks, or plugins.</li>
<li>Reduce repeated reads, parse Claude transcripts in the background, and load effect renderers on demand.</li>
<li>Developer ID signed and Apple notarized; update checks are on by default, with downloads and installation confirmed by you.</li>
</ul>
</td>
</tr>
</table>

<p><sub>Native liquid glass requires macOS 26+; macOS 14–15 uses translucent material. Quota and metadata depend on the source; missing data stays unknown. Costs are estimates.</sub></p>


<a name="supported-agents"></a>
<h2>Supported agents</h2>

<p>Enable each integration in Settings → Connections. Every entry is managed independently.</p>

<table class="agents">
<tr>
<td align="center" width="20%" valign="top"><img src="Sources/QuotaView/Resources/CodexProviderIcon.png" alt="Codex official icon" width="44"><br><strong>Codex</strong><br><sub></sub></td>
<td align="center" width="20%" valign="top"><img src="Sources/QuotaView/Resources/ProviderIcons.xcassets/ClaudeApplicationIcon.imageset/ClaudeApplicationIcon.png" alt="Claude Code official icon" width="44"><br><strong>Claude Code</strong><br><sub></sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/dsh.svg" alt="DSH official icon" width="44"><br><strong>DSH</strong><br><sub></sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/kimi.svg" alt="Kimi Code official icon" width="44"><br><strong>Kimi Code</strong><br><sub></sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/cursor.svg" alt="Cursor official icon" width="44"><br><strong>Cursor</strong><br><sub>Preview</sub></td>
</tr>
<tr>
<td align="center" width="20%" valign="top"><img src="Sources/QuotaView/Resources/ProviderIcons.xcassets/GeminiCLIProviderMark.imageset/GeminiCLIProviderMark.svg" alt="Gemini CLI official icon" width="44"><br><strong>Gemini CLI</strong><br><sub>Preview</sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/opencode.svg" alt="OpenCode official icon" width="44"><br><strong>OpenCode</strong><br><sub>Preview</sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/copilot.svg" alt="GitHub Copilot CLI official icon" width="44"><br><strong>GitHub Copilot CLI</strong><br><sub>Preview</sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/devin.svg" alt="Devin Desktop official icon" width="44"><br><strong>Devin Desktop</strong><br><sub>Preview</sub></td>
<td align="center" width="20%" valign="top"><img src="docs/media/readme/agents/devin.svg" alt="Devin CLI official icon" width="44"><br><strong>Devin CLI</strong><br><sub>Preview</sub></td>
</tr>
</table>

<p><strong>Approvals and answers:</strong> Supported Codex and Claude Code requests can be handled in the Island. Other entries keep confirmation in their original clients. Cursor currently has no permission reminders.</p>

<p><strong>Devin:</strong> Desktop and CLI appear separately. Desktop covers local Devin Local sessions. Models and current-turn Tokens require compatible local records; start a new turn after updating.</p>

<p><strong>Compatibility:</strong> Preview integrations are still being validated across client environments. OpenCode currently covers 1.x. Available data and interactions differ by client.</p>

<details>
<summary><strong>View integration capabilities</strong></summary>

<table>
<thead><tr><th>Agent</th><th>Task state</th><th>Approvals and replies</th><th>Models and usage</th></tr></thead>
<tbody><tr><td>Codex</td><td>Tasks, tools, and available parent/subagent activity</td><td>Supported approvals and questions in the Island</td><td>Models, Tokens, quota, Credits, history, and estimated cost</td></tr>
<tr><td>Claude Code</td><td>Tasks, tools, and completion content</td><td>Supported approvals and single-choice questions in the Island</td><td>Models, Tokens, history, and estimated cost; optional official limits</td></tr>
<tr><td>DSH</td><td>Native plugin events, session titles, final answers, and available child sessions</td><td>Supported tool approvals in the Island; otherwise confirm in DSH</td><td>Models and Tokens supplied by events</td></tr>
<tr><td>Kimi Code</td><td>Hook task, tool, and state events</td><td>Permission reminders; confirm in the client</td><td>Models supplied by events; no account quota panel</td></tr>
<tr><td>Cursor · Preview</td><td>Local hook task and tool state</td><td>Confirm in the client; no permission reminders</td><td>Models supplied by events; no account quota panel</td></tr>
<tr><td>Gemini CLI · Preview</td><td>Local hook task and tool state</td><td>Permission reminders; confirm in the client</td><td>Models supplied by events; no account quota panel</td></tr>
<tr><td>OpenCode · Preview</td><td>1.x plugin tasks, tools, and child sessions</td><td>Permission reminders; confirm in the client</td><td>Models and titles supplied by events; no account quota panel</td></tr>
<tr><td>GitHub Copilot CLI · Preview</td><td>Local hook task and tool state</td><td>Permission reminders; confirm in the client</td><td>Metadata supplied by events; no account quota panel</td></tr>
<tr><td>Devin Desktop · Preview</td><td>Local Devin Local sessions; independent switch</td><td>Permission reminders; confirm in the client</td><td>Session model and current-turn Tokens from compatible local records</td></tr>
<tr><td>Devin CLI · Preview</td><td>Local CLI sessions; independent switch</td><td>Permission reminders; confirm in the client</td><td>Session model and current-turn Tokens from compatible local records</td></tr>
</tbody></table>
<p><a href="docs/specs/agent-integrations.md">Integration details and compatibility</a></p>
</details>


<a name="in-action"></a>
<h2>In action</h2>

<p><strong>Compact state: task status and the floating usage capsule</strong></p>
<p><img src="docs/media/readme/0.9.1/en/01-compact.jpg" alt="Compact state: task status and the floating usage capsule"></p>

<p><strong>Expanded state: tasks and details across agents</strong></p>
<p><img src="docs/media/readme/0.9.1/en/02-expanded.jpg" alt="Expanded state: tasks and details across agents"></p>

<p><strong>Approvals: review the request before deciding</strong></p>
<p><img src="docs/media/readme/0.9.1/en/03-approval.jpg" alt="Approvals: review the request before deciding"></p>

<p><strong>Usage: quota, Tokens, estimated cost, and activity</strong></p>
<p><img src="docs/media/readme/0.9.1/en/04-usage.jpg" alt="Usage: quota, Tokens, estimated cost, and activity"></p>

<p><strong>Reset credits: availability, protection, and expiry</strong></p>
<p><img src="docs/media/readme/0.9.1/en/05-reset.jpg" alt="Reset credits: availability, protection, and expiry"></p>


<a name="installation"></a>
<h2>Installation and updates</h2>

<p><strong>macOS 14+</strong> · Universal Apple silicon + Intel · Developer ID signed · Apple notarized</p>

<ol><li>Download <a href="https://github.com/Duoasa/QuotaView/releases/download/v0.9.3-build.1/QuotaView-v0.9.3-build.1.zip">QuotaView 0.9.3 Build 1</a>, unzip it, and open <code>QuotaView.app</code>.</li><li>Open Settings → Connections and enable the agents installed and configured on your Mac.</li><li>Codex can discover local tasks automatically. After installing hooks or plugins, start a new session or restart the client as prompted.</li></ol>

<p><strong>Automatic update checks are on by default.</strong> Existing preferences are respected, and checks can be disabled in Settings. Downloads and installation still require confirmation.</p>

<details>
<summary><strong>New in 0.9.3</strong></summary>
<ul>
<li>Reset cards dissolve into particles, with smoother replacement animations and clearer empty states.</li>
<li>A red glass quit button stays at the bottom right of Settings, with improved spacing and minimum window height.</li>
<li>Brush icons clarify card cleanup: remove a card from the Island while keeping its original task and chat.</li>
<li>Supported-agent icons use consistent rounded backgrounds.</li>
</ul>
<p><a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.9.3-build.1">Full release notes</a> · <a href="VERSION_HISTORY.md">Version history</a></p>
</details>


<a name="windows"></a>
<h2>Windows · Separate edition</h2>

<p>The current Windows release is <strong>0.8.3-win.13</strong>, with its own release and update channel. The product images and agent list above describe macOS 0.9.3.</p>

<ul>
<li>Includes a solid-color Island, task status, approvals and answers for compatible clients, usage statistics, AI orb, and quantum noise.</li>
<li>Features are adapted to Windows. Native macOS liquid glass and desktop widgets are not included; see the Windows documentation for its agent scope.</li>
<li>Requires Windows x64 and WebView2 Evergreen Runtime. Extract the whole archive and run <code>QuotaView.Native.exe</code>; keep the full application folder.</li>
</ul>

<p><a href="https://github.com/Duoasa/QuotaView/releases/download/v0.8.3-win.13/QuotaView-Windows-0.8.3-win.13-x64.zip"><strong>Download for Windows</strong></a> · <a href="https://github.com/Duoasa/QuotaView/releases/tag/v0.8.3-win.13">Windows release notes</a> · <a href="Windows/README.md">Installation and connections</a></p>


<a name="privacy"></a>
<h2>Privacy and local processing</h2>

<p>Task information is processed locally. QuotaView does not send task content to a QuotaView service or collect login credentials. Integration setup backs up client configuration and manages only its own entries. Live quota queries and resets use the relevant provider service.</p>

<p>Codex resets retain only a local operation record for safe retries. Please omit credentials and raw session logs from bug reports.</p>


<a name="build"></a>
<h2>Build from source</h2>

<pre><code>git clone https://github.com/Duoasa/QuotaView.git
cd QuotaView
swift test
swift run QuotaView</code></pre>

<p>Requires Swift 6 or a compatible Xcode toolchain; DSH plugin tests also require Node.js. For the complete app and widgets, open <code>QuotaView.xcodeproj</code>, select the <strong>QuotaView</strong> scheme and <strong>My Mac</strong>, then run.</p>

<p><a href="docs/workflow/RELEASE.md">Release workflow</a> · <a href="Windows/README.md">Windows build instructions</a></p>


<a name="feedback"></a>
<h2>Project and feedback</h2>

<p><a href="https://github.com/Duoasa/QuotaView/issues/new/choose">Report an issue</a> · <a href="CONTRIBUTING.md">Contributing</a> · <a href="docs/specs/README.md">Design and behavior specs</a> · <a href="LICENSE">MIT License</a></p>

<p>QQ feedback group: <strong>1108649282</strong></p>

<p align="center"><img src="docs/media/readme/shared/feedback-qr.jpg" alt="QuotaView QQ feedback group QR code" width="240"></p>
