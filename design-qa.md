# QuotaView Interface Design QA

Baseline result: **Passed**

0.1.5 clear-glass material result: **Passed — product-owner review**

0.1.5 readability adaptation: **Awaiting product-owner review**

0.1.5 Figma glass recreation: **Awaiting product-owner review**

0.1.5 Figma light appearance: **Awaiting product-owner review**

0.1.5 Figma UI2 quota-reset page: **Awaiting product-owner review**

0.1.5 button interaction states: **Awaiting product-owner review**

0.1.5 reset-card shadow, credit tickets, and localization:
**Awaiting product-owner review**

0.1.5 Page 3 usage-summary update:
**Awaiting product-owner review**

0.1.5 native Settings-window redesign:
**Awaiting product-owner review**

0.1.5 Build 6 availability-badge hotfix:
**Awaiting product-owner review**

0.2.0 Build 3 UI1/UI2 component refinement:
**Release authorized; full visual matrix not separately recorded**

Per the 0.1.5 workflow, implementation validation covers code, state
transitions, tests, and builds. Final visual and interaction review is
performed by the product owner.

## Apple Guidance Used For Readability

- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
  recommends relying on standard framework components, removing custom
  backgrounds that interfere with the material, and allowing accessibility
  settings to adapt transparency, contrast, and motion.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
  reserves clear glass for visually rich backgrounds and content that can
  remain bold and bright.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
  requires a visible press state for every custom button.
- [ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle)
  preserves the platform's standard button interaction behavior while
  allowing a custom appearance, and `onHover` reports pointer entry and exit.
- [Color](https://developer.apple.com/design/human-interface-guidelines/color)
  recommends system semantic colors for automatic light, dark, vibrancy, and
  increased-contrast variants, with color reserved for meaningful status and
  primary actions.
- [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)
  recommends primary, secondary, and tertiary system label colors rather than
  hard-coded light/dark values.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
  sets a 4.5:1 minimum contrast target for text up to 17 pt and 3:1 for 18 pt
  or bold text.

## Reference Coverage

The selected concept and three implemented states were compared locally:

- Overview
- Quota-reset detail
- Final confirmation
- Global Settings

The implementation screenshots used a 370 × 510 pt Retina viewport. Dynamic quota values differ from the concept by design because the app reads live account data.

## Overall Result

- The information hierarchy matches the selected direction.
- Regular metrics remain in a compact list.
- Reset credits are presented as a dedicated bottom action.
- The detail view emphasizes available reset credits, current quota, formal
  risk guidance, and the primary action.
- The final step uses an in-panel modal confirmation card with destructive
  styling and an appearance-adaptive material surface.
- The QuotaView header, status badge, and quit action remain consistent across states.

## Visual Checks

- System SwiftUI typography is clear and free of visible clipping.
- The complete overview follows the 258 × 431 pt UI frame and contracts
  vertically when configured items are hidden; quota-reset spacing follows
  the 258 × 473 pt UI2 frame.
- Controls have clear click targets.
- The menu keeps one outer glass shell with two persisted appearances:
  frosted uses the regular system glass material, while clear uses one system
  clear-glass backdrop plus the non-sampling surface treatments exported from
  Figma node `1:712`.
- Clear mode still has one `NSGlassEffectView` optical/refraction surface.
  A dedicated full-size bottom sampling view first produces a live neutral
  backdrop through `NSVisualEffectView` before drawing the Figma fill,
  shadows, text, icons, and controls. Foreground content is not part of the
  material input. No additional Core Image Gaussian blur is applied. The
  system material has no public blur-radius scalar, so its contribution is
  blended at 60% opacity below the Liquid Glass stage.
- Clear glass has no blue-violet tint or accent-colored shadow; the product
  accent remains limited to content, status, and action elements.
- The current surface uses a 20% neutral black fill, 30 pt inner shadows at
  (6, 3) and (-3.75, -3), and a 15 pt shadow at (0, 18). The latest design's
  subtle 8% white 0.5 pt boundary is now rendered over dark glass; light glass
  uses the corresponding 8% black boundary.
- In light appearance, Figma node `10:122` replaces that dark neutral
  treatment with a 26% white fill, 12% white inner highlights, and a subtle
  8% black 0.5 pt boundary. Primary and secondary text resolve to `#3A3A3A`
  and `#575757`; the ready-state label uses `#149734`.
- Both appearances use the latest Figma-exported vector assets for power,
  sync, Open Codex, and settings. UI2 adds dedicated dark/light back-button
  and reset-credit-strip assets.
- Figma node `1:712` is already the production 258 × 431 pt menu size, so its
  21 pt corner radius and all layout values map directly to AppKit points.
- The panel-level rectangular shadow is disabled so its square frame cannot
  appear outside the rounded glass surface. The Figma drop shadow instead
  renders inside transparent panel insets and follows the rounded glass path.
- Readability styling keeps system primary, secondary, and tertiary label
  colors so macOS vibrancy, light/dark appearance, and Increase Contrast can
  adapt them. It does not add fixed black/white text colors or custom halos.
- The status panel uses one explicit typography scale in both frosted and
  clear modes. Titles, metrics, supporting copy, status badges, and toolbar
  labels are larger than the previous caption-heavy scale; essential small
  labels use medium or semibold weights.
- Dark and light Figma menus use their specified 12% white and 12% black
  separators.
- The overview reset card uses a 12% white border in both appearances. The
  reset-detail primary button uses a red 16% border in both appearances.
- The overview reset card renders its Figma drop shadow from an explicit
  rounded Core Animation shadow path at radius 20 and y 4. Dark appearance
  uses black 20%; light appearance uses black 12%.
- The reset-detail primary button is 234 × 32 pt with an 8 pt continuous
  radius, red 12% fill, red 16% y-4/radius-20 outer shadow, and red 12%
  (-2,-2)/radius-10 inner shadow.
- All 12 interactive controls keep their Figma materials, exported icons,
  fills, borders, shadows, dimensions, corner radii, and layout in both glass
  modes. A shared SwiftUI `ButtonStyle` adds only state feedback.
- Pointer entry and exit are driven by `onHover`; the pressed state comes
  from `ButtonStyle.Configuration.isPressed`. Light and dark appearances use
  separate state overlays. Disabled controls render at 55% opacity.
- Compact 24 pt controls scale to 1.04 on hover and 0.94 while pressed.
  Card and text actions don't enlarge on hover and scale to 0.985 on press.
  Reduce Motion disables scale and transition animation while preserving
  the static hover and pressed overlays.
- Functional icons use the exact exported Figma SVG assets.
- UI2 light 24 pt function buttons use a 20% white fill and a 4% black
  (-2,-2)/radius-5 inner shadow. UI1 dark function-button assets are unchanged.
- The reset-detail ticket row repeats one exact ticket crop for
  `availableResetCredits`; zero credits shows no tickets, and counts wider
  than the original six-ticket strip scale uniformly into its design width.
- Both Figma pages receive `AppCopy` from the preferences-observing parent.
  Visible copy, help text, accessibility labels, time formatting, and reset
  countdown units update immediately with the Settings language.
- Colored foregrounds remain limited to status, usage visualization, and
  primary/reset actions; ordinary metric icons are monochrome.
- The Page 3 summary now places the live Codex subscription at the upper left
  and the weekly remaining value at the upper right. The subscription value is
  sourced from `CodexSnapshot.planType`, which is populated by
  `account/rateLimits/read`; it is no longer hard-coded to PLUS.
- The 12 pt quota bar is split into used and remaining segments with a 1 pt
  gap. The used segment keeps the Figma white treatment; the remaining segment
  uses green at 50–100%, yellow at 20–49%, and red below 20%, always at 32%
  opacity so urgency changes don't alter visual density.
- The summary status capsule now describes data acquisition only. A valid
  snapshot with no latest fetch error is green and Available; missing or
  failed status data is red and Unavailable. The unavailable summary replaces
  subscription and percentage values with em dashes instead of presenting a
  false zero-quota state.
- The UI1/UI2 status label has a fixed 18 pt height and 6 pt continuous
  radius. Its state surface uses 20% semantic color, a 3.75 pt clipped
  background blur, and a 12% black inner shadow. It has no outer glow or
  shadow.
- The rounded Figma drop shadow is the only custom outer shadow; the native
  rectangular `NSPanel` shadow remains disabled.
- Functional mappings and tooltips remain unchanged in both material modes.
- Copy clearly separates data refresh from quota reset.
- The Settings window uses a toolbar-free, full-size-content `NSWindow`.
  Its real close, minimize, and zoom buttons are hosted by an AppKit view in
  the upper-left of the floating sidebar, keeping their native window actions
  and hit targets while matching the reference hierarchy.
- A dynamic, opaque `windowBackgroundColor` surface now fills both the real
  settings content and its SwiftUI root. The transparent `NSWindow` host clips
  that complete surface to a 36 pt continuous outer radius, so the desktop can
  no longer leak through the gap between the floating sidebar and detail area.
- The 200 pt sidebar has a 20 pt continuous corner radius. macOS 26 renders
  it with Apple's native `Glass.regular` and `ConcentricRectangle`, resolving
  the radius from the 36 pt window container and 16 pt inset. macOS 14–15 use
  the equivalent 20 pt `.regularMaterial` fallback. Navigation remains a
  system sidebar List with native
  hover, selection, focus, and accessibility behavior.
- The sidebar contains Menu Bar, Popover, Appearance, Language, and General.
  General centers the production app icon, app identity, actual marketing and
  build versions, and an update-check placeholder that accurately reports the
  updater is not connected yet.
- Every grouped settings row uses a left title/description column, flexible
  spacing, and a right control at its native fixed size. Visible switch and
  picker edges share the same 18 pt trailing inset, cards expand to the
  available detail width, and switches use the small macOS control size.
- Each settings detail header now contains only a 22 pt semibold page title
  and a callout-sized secondary description; the repeated QuotaView heading
  has been removed.
- General uses the packaged macOS application icon instead of the white-canvas
  Figma export, so no white square can appear around the icon.
- Settings no longer renders `QuotaViewAmbientBackground`, brand gradients,
  brand glows, or fixed `CodexTheme.accent` tinting. Selection, switches,
  keyboard focus, and segmented controls resolve through
  `NSColor.controlAccentColor` so they follow the user's macOS accent color.
- All existing preference bindings remain connected and update immediately.
  The content remains scrollable at the 780 × 560 pt minimum window size.

## Interaction Checks

- The menu bar item opens the overview.
- The quota reset action opens the detail view.
- The reset action is enabled only when live snapshot data reports at least
  one reset credit; it opens the final confirmation without changing data.
- The final confirmation opens after the primary action.
- While the final confirmation is visible, the status panel becomes the key
  window and outside-click monitors are suspended so Confirm, Cancel, and
  Escape remain interactive.
- Cancel does not change the real reset count.
- Back returns to the overview.
- Settings can be opened from both overview and quota-reset detail footers.
- A menu bar label always retains at least one visible component.
- Menu bar and popover visibility preferences update immediately and persist.
- System-following appearance disables the custom light/dark selector.
- Frosted and clear glass choices update immediately and persist.
- System-following language disables the custom language selector.
- Simplified Chinese and English update without restarting the app.
- The current implementation never sends `account/rateLimitResetCredit/consume`.

## Comparison History

The first comparison found duplicated demo-mode messaging near the bottom of the detail view. The duplicate copy was removed and consolidated into a single footer line.

The second comparison found no remaining P0, P1, or P2 visual issues.

The Settings runtime check found that a window created by an `LSUIElement` app
could open behind the active application. The settings action now explicitly
activates QuotaView after opening the native Settings scene.

The first 0.1.5 clear-glass pass replaced the `MenuBarExtra` window with an
`NSStatusItem` and a borderless, nonactivating `NSPanel`.

The Figma recreation reads the source properties directly from frame
`1:712`. Its GLASS effect is frost radius 18, refraction 0.88, depth 88,
light angle 320°, light intensity 0.40, dispersion 0.80, and splay 0.12. The
same frame has a 20% black fill, an 8% white 0.5 pt inside stroke, 12% black
inner shadows at (6, 3) and (-3.75, -3) with radius 30, and a 20% black drop
shadow at (0, 18) with radius 15.

QuotaView keeps one `NSGlassEffectView` with `.clear` as the real-time
WindowServer backdrop/refraction layer. Figma's fill, stroke, inner shadow,
drop shadow, and corner geometry are reproduced in the content composition
above it at the frame's production 258 × 431 pt dimensions.
AppKit does not expose Figma's individual refraction/depth/dispersion controls;
the native clear-glass compositor supplies that optical phase without screen
capture permissions or private APIs. A public `CIGaussianBlur` background
filter is no longer applied. A dedicated bottom sampling view uses an active
`NSVisualEffectView` at 60% opacity to obtain the neutral system material
backdrop, while foreground content remains outside that material subtree.
Frosted mode keeps the regular system glass. On macOS 14–15, clear uses the
HUD material plus the same 60% system-material sampling layer, while frosted
uses the popover material; both remain clipped with a rounded mask.

The Page 3 overview uses the Asta Sans weights, sizes, line heights, tracking,
and fixed white/75%-white hierarchy exported by node `1:712`. The same
overview hierarchy is rendered in clear and frosted modes.

The UI2 light overview is sourced from node `25:1471`. It preserves the
same 258 × 431 pt geometry and interaction mapping while changing only the
appearance tokens, local borders, status treatment, and function-icon assets.
AppKit's application appearance is the single light/dark authority; SwiftUI
content and the clear-glass chrome both update from that effective appearance.

The quota-reset screen is sourced from UI1 node `10:181` and UI2 node
`25:1524`. Both use a fixed 258 × 473 pt layout. The available reset-credit
count, current remaining quota, post-reset remaining count, and update time
come from `CodexSnapshot`. Back, sync, Open Codex, settings, and reset
confirmation actions are wired to the existing application flow.

UI2's repeated placeholder warnings were replaced with formal production
copy: the action consumes one reset credit, resets an eligible Codex usage
cycle immediately, and cannot be undone. The final confirmation additionally
states that the current demo build does not call the live endpoint.

The borderless `NSPanel` has its rectangular window shadow disabled so it
cannot leave straight edges around the rounded surface. Switching material
modes reuses the existing `NSHostingView` without reconstructing SwiftUI
content. Code review confirmed that the temporary screenshot-only auto-open
path remains absent.

Settings closes the menu panel before changing its material, and reopening the
panel with `orderFrontRegardless()` left it non-key. macOS rendered `.clear`
glass in its thicker inactive presentation. Clicking through reset details
made the panel key, which explained why that route appeared to activate the
correct glass until the panel was closed again. Clear-mode selection now
records an explicit redraw request. On every clear-mode presentation, the
controller orders the panel front at zero opacity, makes it key, recreates the
clear surface, completes layout/display, and only then starts the normal
fade-in. Frosted mode retains its existing reusable surface behavior.

The final confirmation now renders inside the 258 × 473 pt glass content
instead of using SwiftUI's window-sized `.alert` scrim. Its dimming layer is
clipped to the same 21 pt continuous corner as the glass body, so clear mode
does not cover the transparent drop-shadow insets and frosted mode does not
show rectangular corners. The controller keeps the panel key and temporarily
suspends local/global outside-click dismissal while the confirmation is
active. Cancel, confirmation, or Escape restores the normal event policy.

The overview is 258 × 431 pt when every configured item is visible and now
contracts to the exact visible-content height. The quota-reset detail route
remains fixed at 258 × 473 pt. Panel positioning uses the status-item click
event's screen so the menu opens on the intended display in multi-monitor
setups.

All six Popover preferences now drive production visibility. Usage summary
and the four metrics are typed as `info`; Quota Reset is typed as
`interactive`. An info item draws its bottom separator only when another info
item follows it. The reset entry appears only when its preference is enabled,
the latest status fetch is valid, and `availableResetCredits` is greater than
zero.

The temporary three-credit UI fixture has been removed. The reset entry,
ticket count, button state, and derived remaining count now read only the
latest valid live `availableResetCredits` value. The general temporary-data
gate remains documented in `CONTRIBUTING.md` and `AGENTS.md`.

The latest Page 3 implementation was checked against the design-context and
metadata values for nodes `1:712`, `25:1471`, `10:181`, and `25:1524`;
automated screenshot or interaction QA was not performed, per the repository
rule. Visual and interaction acceptance is waiting for the product owner.

## Follow-ups

- Add explicit result states before enabling the real reset endpoint.
- Verify keyboard focus order and VoiceOver behavior before production distribution.
