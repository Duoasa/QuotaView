# QuotaView 0.4.5 Build 1 — Native Codex Activity Bridge

[Download QuotaView-v0.4.5-build.1.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.4.5-build.1/QuotaView-v0.4.5-build.1.zip)

QuotaView 0.4.5 makes live Codex activity available on first launch for current
Codex releases and gives Codex Island more useful running, waiting, and
completion states.

## Highlights

- **No Hook setup for current Codex:** A new read-only local activity bridge
  discovers active tasks automatically. The signed Hook remains available only
  as a compatibility fallback for older environments.
- **Private by construction:** QuotaView extracts only sanitized identifiers,
  task state, plan counts, coarse tool categories, workspace name, timestamps,
  and token numbers. Prompts, reasoning, messages, commands, arguments, tool
  output, diffs, and completion text are ignored.
- **Live turn tokens:** The expanded Island shows the current turn's token use
  while work is running. A successful completion shows the turn total and the
  latest remaining quota; the compact state keeps a small quota ring.
- **Clearer state feedback:** Quantum Noise is the default and only Island
  style. Hover leaves the Island 20% visible, long confirmation waits gain a
  yellow outline and halo, and completion uses a violet-blue-cyan outline and
  glow.

The universal build supports Apple Silicon and Intel Macs running macOS 14 or
later. It is signed with the QuotaView Developer ID, notarized by Apple, and
stapled for offline Gatekeeper verification.

Signed installations on the Stable channel can receive this release through
QuotaView's in-app updater.
