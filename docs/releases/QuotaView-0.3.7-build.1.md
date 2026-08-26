# QuotaView 0.3.7 Build 1 — Multiple Quota Windows and a Screen-Aware Codex Island

[Download QuotaView-v0.3.7-build.1.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.3.7-build.1/QuotaView-v0.3.7-build.1.zip)

QuotaView 0.3.7 makes every valid Codex core quota window visible and gives
multi-display users a simple way to keep the Codex Island on the screen where
Codex is located.

## Highlights

- **Complete core quota visibility:** Primary and secondary Codex windows are
  modeled independently and shown from the shortest duration to the longest,
  so 5-hour and weekly limits can appear together.
- **Duration-based labels:** Quota titles come from the duration returned by
  Codex rather than the subscription name. Missing or invalid secondary data
  hides cleanly instead of producing a false zero.
- **Independent Spark quota:** Spark remains a separate neutral window after
  the core limits, with its own usage and reset countdown and no repeated plan
  label.
- **One screen-placement switch:** Enable **Lock to Codex Screen** to place the
  Codex Island on the display containing the largest visible Codex window.
  Leave it off to keep following the active menu-bar hotspot.
- **Safe multi-display fallback:** If Codex is unavailable, hidden, minimized,
  or cannot be located, the Island returns to the hotspot automatically.
- **Local and permission-free:** Screen selection reads only the Codex process
  identifier and window/display geometry. It does not read window titles,
  contents, or pixels and requests no Accessibility or Screen Recording access.
- **Stable single-task scope:** Particle Orb, Ripple Glow, custom compact/hide
  timing, Reduce Motion, and the stable single-task lifecycle remain intact.

The universal build supports Apple Silicon and Intel Macs running macOS 14 or
later. It is signed with the QuotaView Developer ID, notarized by Apple, and
stapled for offline Gatekeeper verification.

Signed installations on the Stable channel can receive this release through
QuotaView's in-app updater.
