# Design QA

> 文档编号：`QV-EVIDENCE-MULTITASK-DEMO-QA-001`
>
> 文档类型：SDD Prototype 验收证据
>
> 对应规格：`QV-PRODUCT-ACTIVITY-ISLAND-MULTITASK-001`
>
> 证据状态：`Active`
>
> 对应交付阶段：`Prototype`（当前正在 Demo 调试）
>
> 证据边界：2026-08-02 的产品所有者确认只冻结 Demo 视觉与交互基线，
> 不证明生产实现、生产构建或发布已经完成。

## Comparison Target

- Source visual truth — local product-owner capture of the main island and
  right-side task list, `1750 × 516 px` (capture not committed).
- Reviewed issue captures — expanded divider `1020 × 324 px`, cramped compact
  state `602 × 158 px`, excessive adaptive-status reserve `864 × 164 px`,
  cramped expanded task rail `312 × 284 px`, pagination hierarchy
  `352 × 302 px`, and redundant selection line/status dot `284 × 158 px`.
  These local captures are not committed; only their review conclusions are
  retained below.
- Rejected stacked-card reference: `2476 × 646 px`; retained only as the design
  direction that must not be implemented, without its local filesystem path.
- Implementation: native macOS `CodexActivityMultiTaskDemo`, four-task expanded
  state, dark appearance.
- Native design size: one fixed `496 × 152 pt` multi-task panel with a
  `144 pt` right-side task list. Compact height remains `52 pt`, while width
  follows the rendered status and title; its panel adds `10 pt` reserve on
  every edge.
- Implementation screenshot: unavailable by project policy; QuotaView requires
  the product owner to perform visual and interaction acceptance and prohibits
  Codex from proactively capturing a QA screenshot unless explicitly requested.
- Density normalization: not performed because there is no implementation
  screenshot to normalize against the source images.

## Full-View Comparison Evidence

Blocked. All source images were opened and inspected, but no same-state
implementation screenshot is available for a combined visual comparison.

The rollback target is unambiguous:

- Figure 1 controls the complete single-island layout, including the Metal
  orb, three-line primary content, divider, and right-side task list.
- Figure 2 is explicitly rejected because persistent backing cards consume
  screen space without adding information.

## Focused Region Comparison Evidence

Blocked for the same reason. The foreground task rail, divider-free expanded
layout, compact marquee, fixed count label, and direct task-state updates
require product-owner inspection in the running app.

## Findings

- No visual pass or mismatch severity is asserted without implementation
  screenshot evidence.
- Code and layout checks confirm that both the previous right-side mini-island
  design and the later full-size backing cards are absent; the foreground task
  rail remains, and two to four tasks use the same `496 × 152 pt` panel. The
  three-row rail now uses an ordered sliding window instead of replacing its
  last row with whichever overflow task is selected.
- The expanded divider view has been removed. Compact content now reserves
  separate regions for a complete content-sized status, a `44–128 pt`
  adaptive marquee title, and a `54 pt` total-count label.
- The expanded rail now uses `12 pt` top, bottom, and leading insets plus a
  doubled `24 pt` trailing content inset, `8 pt` section gaps, a dedicated
  bottom overflow-label region, and three `20 pt` rows on a consistent
  `23 pt` step.
- Pagination chrome now appears only above three tasks. Its centered header is
  ordered “任务” then counter with a `6 pt` gap; one-to-three-task lists hide
  both header and footer and center their actual row block vertically.
- The status dot and selection marker now share one marker slot. Unselected
  tasks use a `5 × 5 pt` dot; the primary task replaces its dot with a
  `5 × 12 pt` marker using a `2.5 pt` corner radius. The previous separate
  left-side selection line is absent.
- The task-name leading edge moved from `32 pt` to `24 pt`, assigning all
  released `8 pt` to readable task-name width without changing the `144 pt`
  rail or fixed expanded silhouette.
- During a switch, the selected marker expands into the previous
  full-row native-glass treatment, now fitted to `116 × 20 pt` with a `4 pt`
  leading inset and a `24 pt` trailing inset aligned to the task-content edge.
  The destination dot disappears, and the glass travels vertically above the
  island surface but below a dedicated crisp task-content layer before
  resolving into the destination `5 × 12 pt` marker over `0.8 s`.
- On macOS 26, the transient selection surface now uses Apple's native
  `NSGlassEffectView` with the `clear` style and a `10%` state-color tint.
  macOS 14–15 uses `underWindowBackground` as the clearer material fallback.
- Fonts and typography: Asta Sans weights and sizes are unchanged; post-fix
  optical alignment and truncation remain awaiting visual inspection.
- Spacing and layout rhythm: the rail now resolves to the complete `132 pt`
  surface height with balanced `12 / 14 / 8 / 66 / 8 / 12 / 12 pt` vertical
  zones;
  rendered evidence remains unavailable.
- Colors and visual tokens: text and state colors are unchanged. The transient
  `116 × 20 pt` selection glass uses native clear glass with a `10%`
  state-color tint; its perceived refraction and text legibility require
  product-owner review.
- Image and asset fidelity: the existing Metal orb and material surface remain
  untouched; the task rail introduces no new image assets or substitutions.
- Copy and content: position, “任务”, task names, and “前 N / 后 N” semantics are
  unchanged; only their layout regions changed.
- Interaction: the compact “共 N 项” region now acts as a full-width detail
  hit target, expands the island through the existing presentation transition,
  updates the control-panel mode, shows a pointing-hand cursor, and exposes a
  VoiceOver press action. Visual and interaction evidence awaits owner review.
- Motion semantics: unselected rail tasks in `thinking` or `working` now reuse
  the exact operation-text shimmer component and its `2.6 s` gradient cycle.
  Primary tasks and all other states remain static; Reduce Motion disables it.

## Comparison History

1. The earlier prototype interpreted the cluster as separate small cards to the
   right of the main island. The product owner rejected that structure.
2. A later implementation preserved Figure 1 as the foreground card but added
   Figure 2-style backing cards. The product owner rejected the extra footprint.
3. The implementation was rolled back to Figure 1's fixed single-island
   composition while retaining the multi-task rail.
4. The remaining whole-card switch animation was removed because it no longer
   represents a change between physical cards.
5. The overflow rail was changed from `[first, second, selected]` replacement
   to a contiguous ordered window: selecting task four moves `1–3` to `2–4`.
6. A vertical wheel transition, `0.5 s` selected-row emphasis, edge fade, and
   shared moving selection marker were added to the rail. The column travel is
   synchronized to the marker's `0.8 s` morph.
7. The expanded vertical divider was removed so whitespace alone separates the
   main content and task rail.
8. The compact surface grew from `250 pt` to `320 pt`; status and title were
   separated, overflow titles gained a seamless marquee with bilateral fades,
   and the total count was changed to the complete “共 N 项” form.
9. The compact surface then grew to `390 pt` so every status, including
   “正在压缩上下文”, remains complete in a fixed `118 pt` region without
   reducing the `128 pt` title viewport.
10. Product-owner evidence showed that the fixed longest-status reserve creates
    a large gap for short states such as “已完成”. Status and title widths now
    follow their actual content, while the title remains capped at `128 pt`.
11. Product-owner evidence showed inconsistent expanded-rail spacing and an
    overflow hint nearly touching the lower edge. The panel and rail were
    widened by `16 pt`, and the rail was rebuilt around consistent outer
    insets, section gaps, and row rhythm.
12. The maximum panel remains `496 × 152 pt`, but its internal split now gives
    another `16 pt` to the task rail (`144 pt` total) and removes the same
    amount from the primary-content region.
13. Rail pagination was changed from permanently visible, split-corner labels
    to a centered “任务 + counter” header with a `6 pt` gap. Header and footer
    are now conditional on having more than three tasks.
14. The “任务” label and task counter now share the same `10.5 pt` font size;
    their existing weight and color hierarchy remains intact.
15. The moving selection marker initially morphed line → masked-material
    capsule → line. Product-owner review found the motion too fast, the shape
    too pill-like, and the material too similar to an opacity mask.
16. The morph now lasts `0.8 s`, uses a `6 pt` rounded rectangle, and renders
    through the native macOS 26 `NSGlassEffectView` regular material. The glass
    remains transient, sits behind row content, and transitions between the old
    and new task accent colors.
17. The compact task-count region was promoted from a static label to the
    explicit detail-expansion entry requested in the latest reference capture.
18. Unselected `thinking` and `working` task names now reuse the main operation
    label's Codex shimmer. The effect stops when that row becomes primary or
    when Reduce Motion is enabled.
19. The separate left selection line was removed. Selection now replaces the
    task's `5 × 5 pt` status dot with a `5 × 12 pt` marker in the same slot,
    giving task names another `8 pt` of horizontal space.
20. The full-row glass rectangle was removed. The marker now liquefies into a
    compact `12 × 12 pt` glass object, travels vertically while the target dot
    is hidden, and resolves into the target marker.
21. Product-owner feedback restored the previous full-row glass treatment
    while retaining the unified marker slot: the `5 × 12 pt` marker expands to
    a `122 × 20 pt`, `6 pt`-radius glass rectangle and travels above row content.
22. The glass was widened to `136 × 20 pt` with symmetric `4 pt` rail insets
    after product-owner review found incomplete option coverage. Its material
    changed from native `regular` to `clear`, and tint dropped from `22%` to
    `10%`, so underlying task content remains legible.
23. Runtime inspection confirmed macOS `26.5.2` uses native
    `NSGlassEffectView`, not the `NSVisualEffectView` fallback. The remaining
    blur came from placing task glyphs behind the glass with an empty
    `contentView`, so the glyphs were treated as refracted background content.
24. Task names and status dots now form a crisp foreground layer above the
    moving glass. The glass remains above the island surface and still fully
    covers each option, but no longer samples the task glyphs as its backdrop.
25. The expanded island's task-content trailing inset doubled from `12 pt` to
    `24 pt`. The leading, top, and bottom insets remain `12 pt`; the glass
    geometry remains unchanged.
26. Product-owner review found the unchanged glass overextended beyond the new
    content edge. Its trailing inset now matches the `24 pt` task-content inset,
    reducing the glass from `136 pt` to `116 pt` while preserving full option
    coverage.
27. On `2026-08-02`, the product owner accepted the running native Demo as the
    frozen visual and interaction baseline for later development.

## Implementation Checklist

- [x] Keep the foreground main island and allocate `144 pt` to its task list.
- [x] Remove all backing cards and stack-dependent window growth.
- [x] Keep the multi-task maximum state fixed at `496 × 152 pt`.
- [x] Rebalance the fixed panel without changing its outer dimensions.
- [x] Remove whole-card translation, rotation, opacity, and perspective changes.
- [x] Directly synchronize task content, task-list selection, and Metal state.
- [x] Keep task order stable and scroll the visible three-row window as a unit.
- [x] Place the final task on the bottom row when it becomes primary.
- [x] Add wheel-style rail motion and disable it under Reduce Motion.
- [x] Give the rail `12 pt` leading/top/bottom and `24 pt` trailing padding.
- [x] Normalize the three task rows to `20 pt` height and `23 pt` step.
- [x] Center the “任务 + counter” header and preserve its `6 pt` gap.
- [x] Use the same `10.5 pt` font size for both header labels.
- [x] Replace the selected task's status dot with a `5 × 12 pt` marker.
- [x] Remove the separate left selection line and give its `8 pt` to task names.
- [x] Expand the marker into a `116 × 20 pt` content-fitted glass rectangle.
- [x] Keep the glass above the island surface and below crisp task content.
- [x] Exclude task names and dots from the glass backdrop sampling layer.
- [x] Use native `clear` glass with a restrained `10%` state tint.
- [x] Hide the destination dot while the glass travels to its marker slot.
- [x] Synchronize the `0.8 s` glass travel with the ordered task-wheel movement.
- [x] Use native `NSGlassEffectView` clear material on macOS 26.
- [x] Bypass the morph under Reduce Motion.
- [x] Hide pagination chrome for one to three tasks and center the row block.
- [x] Keep the expanded vertical divider removed after widening the rail.
- [x] Size the status region to its current text while keeping every state complete.
- [x] Adapt the title viewport between `44 pt` and `128 pt`.
- [x] Scroll only overflowing titles with left/right edge fades.
- [x] Fall back to static tail truncation under Reduce Motion.
- [x] Expand compact multi-task detail when the right-side total is clicked.
- [x] Keep the control-panel presentation mode synchronized with that click.
- [x] Expose the compact detail entry as a VoiceOver button action.
- [x] Reuse the operation-text shimmer for unselected thinking/working tasks.
- [x] Disable background-task shimmer for primary rows and Reduce Motion.
- [x] Keep the Demo attached above and moving with the control window.
- [x] Product owner froze the current silhouette, task-rail density, glass,
  spacing, and switching feedback as the later-development baseline.

## Follow-up Polish

- Product-direction changes remain deferred: do not change the frozen fixed
  island, task rail, dimensions, privacy boundary, or interaction direction
  without a new explicit product-owner instruction.
- Demo debugging may continue when it fixes an implementation defect, aligns
  the Prototype with the accepted specification, or adds Prototype-only test
  evidence without changing those frozen directions.

Formal screenshot-comparison evidence remains unavailable under the project
policy. That limitation blocks only an automated screenshot-comparison claim;
it does not invalidate the product owner's accepted live-Demo baseline and does
not block continued Prototype debugging.

final result: accepted Demo baseline; automated screenshot comparison unavailable;
production verification not started
