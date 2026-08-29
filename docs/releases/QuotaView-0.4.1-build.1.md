# QuotaView 0.4.1 Build 1 — A Progress-Aware Codex Island

[Download QuotaView-v0.4.1-build.1.zip](https://github.com/Duoasa/QuotaView/releases/download/v0.4.1-build.1/QuotaView-v0.4.1-build.1.zip)

QuotaView 0.4.1 adds a dedicated progress-style Codex Island alongside the
existing AI Orb and makes task progress feel consistent whether Codex uses an
explicit multi-step plan or performs one unplanned action.

## Highlights

- **Dedicated Progress Bar style:** Choose between AI Orb and Progress Bar in
  Settings. The progress surface has its own compact geometry and does not
  inherit AI Orb size choices.
- **Approximate task progress:** A smoke front follows sanitized plan status
  counts when a structured plan exists. Active planned work is capped at 95%;
  only a real completion event reaches 100%.
- **Consistent single-step behavior:** Every active task waits at 1% for a
  4-second plan-discovery window. An in-progress plan step contributes a
  conservative 10% of one step to prevent a newly detected multi-step task
  from jumping ahead. If no plan arrives, the Island transitions
  into a slower single-step estimate capped at 50%. A late plan can still take
  over without moving the displayed front backward.
- **Reliable desktop plan detection:** The local Hook recognizes both direct
  plan updates and the `tools.update_plan(...)` calls wrapped by Codex Desktop's
  execution tool.
- **Privacy-preserving by construction:** The helper immediately reduces a plan
  to completed, in-progress, and pending counts. Step text, explanations, raw
  scripts, prompts, arguments, and tool output are never forwarded.
- **More readable state smoke:** Working uses a low-saturation bright cyan,
  context compaction uses a cool gray-white, and the opacity curve follows the
  visible smoke width so the leading text remains readable while the smoke
  front stays distinct.
- **Refined completion feedback:** Completion fills the Island, darkens, fades
  back to the native surface, and separates a clean 1 pt green highlight
  outline from a four-sided breathing glow beneath the Island. Extra transparent
  render space lets the glow decay without a rectangular cutoff.
- **Reliable idle convergence:** Missing terminal Hook events settle safely
  after inactivity, while delayed tool-finished events cannot reopen a turn
  that already completed.
- **Stable bilingual layout:** Expanded Progress Bar text uses a compact
  left-title/detail and right-aligned-state layout. Expanded and compact sizes
  are fixed against the widest supported English and Simplified Chinese copy,
  preventing geometry jumps.
- **Three AI Orb sizes:** The expanded AI Orb supports 100%, 85%, and 75%
  proportional sizes without changing the Progress Bar or compact Island.

The universal build supports Apple Silicon and Intel Macs running macOS 14 or
later. It is signed with the QuotaView Developer ID, notarized by Apple, and
stapled for offline Gatekeeper verification.

Signed installations on the Stable channel can receive this release through
QuotaView's in-app updater.
