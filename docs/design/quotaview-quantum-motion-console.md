# Quantum Noise Motion Console

Spec ID: `QV-PROTOTYPE-QUANTUM-MOTION-016`

Status: `Accepted / Verifying` — the owner has authorized production migration
into 0.4.6 Build 2. Local build and smoke checks passed. The owner accepted the production
effect and authorized the Build 2 hot update on GitHub and appcast on 2026-09-06.
Publication is being verified. Earlier sections record console iteration history.

## Requirements

The following visual rules are temporary and apply only to this demo console.
They are not QuotaView-wide or production design requirements.

- R0: The visible effect must fill the island vertically from top to bottom within
  the current horizontal progress extent, clipped by the island corners. This
  applies to every state and transition. Compression must rearrange particles
  within a full-height field, never shrink the whole field into a central band.
- R0b: Quantum noise must read as clear, separated, twinkling points of starlight.
  Retain particle gaps and varied scintillation; avoid blurred blobs, luminous
  rings or merged glowing masses. Motion and brightness changes must preserve
  this texture.
- R0c: Progress is an estimate. Its leading edge must dissolve over a broad,
  irregular region through decreasing star count and brightness, without a sharp
  measuring edge or front highlight. Individual stars remain crisp. Short progress
  retains a visible core; only explicit completion fills the entire island.
- R0d: Grain size, fineness, position jitter and interior occupancy must match
  original 0.4.6. Do not substitute larger cells or extra cross-shaped rays.
  State motion and grading operate on this original grain field.
- R1: Compare the original 0.4.6 Metal effect and a proposed state-aware effect in
  the same native island, using the production layout, typography and completion glow.
- R2: Preserve particle identity across state changes. Integrate velocity over time;
  interpolate shape, brightness and state weights without restarting the clock.
- R3: Thinking explores; working transports one irregular pulse with eased,
  nonlinear speed; compaction restores early local neighbourhood reordering, with natural
  grouped light and stronger contrast over a full-height base star field;
  confirmation holds with a slow pulse; errors use a restrained irregular pulse;
  disconnected/unavailable stop motion; standby has zero progress. Completion is
  an explicit simulated event, with the existing fill, fade and glow lifecycle.
- R4: Manual state, percent, expanded/compact, Reduce Motion, playback, language,
  restart and completion replay controls. All fixture data is visibly DEBUG.
  Manual backward scrubbing is isolated to the demo and must not change production
  monotonic progress. Active progress caps at 95%; only completion reaches 100%.
- R5: Copy production sources into an ignored build workspace, replace only the
  app entry point, and apply the candidate renderer there. Do not start the real
  status store, activity bridge, hooks, update service or shared defaults.

## Non-goals and fallback

No new product module, provider, progress estimator, island geometry or release.
The demo reuses the existing Metal fallback; it must report when Metal is unavailable
so the fallback cannot be mistaken for candidate shader acceptance. Reduce Motion
has a static field. Hidden/minimized previews stop playback. No screenshot or UI QA
automation is embedded in production; external visual inspection is user-authorized.

## Acceptance

Check 0/1/25/50/75/95% and explicit completion, rapidly interrupt transitions,
scrub backward, replay completion, toggle compact and Reduce Motion. Verify motion
and color continuity, distinguishable state rhythm, readable text and unchanged
completion outline/glow. Automated tests verify continuity and terminal semantics;
visual and interaction acceptance belongs to the user.

## Implementation evidence · 2026-09-05

Standalone console implemented, including an interruptible 20-second demonstration,
native side-by-side comparison and all nine manual states. `swift test`: 171 passed;
final focused check: 5 passed. Production baseline Universal Xcode Release build
passed with unchanged version identity and required assets. Demo is an arm64 Debug
app, not the Universal production artifact. The console guide is retained locally at `Prototypes/QuantumNoiseConsole/README.md`;
the independent DEBUG console is excluded from this production release commit.
Visual and interaction acceptance remains pending; no production renderer migration.

Second visual iteration: the user explicitly authorized direct visual inspection.
Observed the running console through a 5.6-second breathing frame sequence and a
20.5-second complete demo sequence, plus compact/Reduce Motion checks. Replaced
the inherited smoke luminance curve for the candidate, increased displacement,
added actual compression and randomized neighbouring particle sampling. Full
tests: **172 passed**, including a GPU-rendered brightness regression. Agent visual
review completed; owner acceptance remains pending. Detailed observations and
measurement limits are recorded in the console guide above.

Owner clarification (2026-09-05): full-height coverage and discrete twinkling
starlight are temporary rules for this console only. The earlier compression band
was rejected. The rules were removed from global AGENTS.md and the production
effect adaptation protocol.

Full-height iteration: all candidate states and transitions use a full-height
field of separated sharp stars. Compression uses local reordering and grouped
scintillation, with no global vertical contraction. The latest refinement reduces
star radii by approximately 23–26%, strengthens chromatic state colors while
preserving compression silver, and uses a single irregular transport pulse whose
speed eases in and out. Full suite: **174 passed**; final silver-palette refinement:
**8 affected candidate tests passed**. GPU checks cover top/bottom coverage across
24 state/transition samples, gaps, progress clipping, single-pulse topology,
nonlinear speed and an invisible cycle wrap. The running console was inspected
through continuous frames, including a complete 20-second sequence and compact /
Reduce Motion. Owner acceptance remains pending; production remains unchanged.

2026-09-06 estimated-progress refinement: the candidate front now tapers across
up to 18% of the island width, shortened proportionally for low progress. Stable
per-star thresholds and a gently uneven edge reduce count and brightness without
blurring particle geometry. Removed the front brightness boost. Full suite:
**175 passed**, including GPU coverage for 0/1/25/50/95%, expanded/compact dimensions,
top/middle/bottom and explicit completion. Actual 50% compression and a moving 75%
execution pulse were inspected; owner acceptance remains pending.

Later brightness refinement: lifted dim/mid-range stars, increased chromatic
saturation, retained neutral compression silver and compensated red exposure.
Particle size, field geometry, motion and front dissolve remain unchanged.
All 9 affected tests passed, with palette assertions evaluated after display RGB
clamping. Inspected all active palettes and before/after compression at 65%.
Owner acceptance remains pending.

Latest grain refinement (2026-09-06): restored the original 2.35 px cell geometry,
radius distribution, jitter and 88% interior occupancy. Removed custom cross rays
and the wider candidate grid. Preserved motion, color grading and soft progress
front; suppressed faint bloom in the grading curve to avoid a veil between fine
stars. A GPU comparison checks 87,040 interior pixels against the actual original
renderer under matching original sparkle. The original base sparkle distribution
also replaces the candidate's always-bright floor. Confirmation now uses a dedicated
gold palette with pale-gold peaks, avoiding the orange/red shift of the general
saturation curve. All 10 candidate tests passed, including golden hue and particle
gap checks. Actual golden breathing frames were inspected; owner acceptance remains pending.

Final visible-color correction: waiting reuses the original complete density-to-RGB
transfer extracted from production, instead of a manually selected yellow.
Breathing scales the resulting starlight uniformly to retain warm gold in dim
phases. RGB regression compares against the production formula.

Compression clarification: the owner rejected rigid blocks. Organic star clusters
now gather, tighten, disperse and re-form at new positions in staggered cycles.
Continuously deforming contours and light local advection act on the original
fine stars; the base field retains full height. Reseeding happens at zero envelope
strength to avoid jumps. All 11 related checks passed, including gathering,
dispersal, relocation and loop continuity. Actual continuous frames were inspected.
Production remains unchanged; owner acceptance remains pending.

Cluster prominence refinement: larger mature clusters and stronger core-to-base
contrast make gathering easier to see. Neighbours share a curved spatial spine,
tangent orientation and a gentle brightness hierarchy, with 0.48-second sequential
onsets. Each generation reshapes the arrangement. The full-height base and discrete
grain remain intact. All 11 related tests passed; actual cycle frames were reviewed,
with owner acceptance pending.

Current compaction-only direction supersedes the curved-spine variant above:
restore the early full-height prototype's independently phased neighbourhood
reordering, retaining current original grain parameters. Smooth neighbourhood
influence avoids rectangular boundaries; local light/dark contrast reveals the
clusters. No curved arrangement, brightness hierarchy or fixed relay in compaction.
Other states retain current rendering, including completion's previous settle field.
11 related tests passed. A separate before/after GPU comparison across five other
states and 34,170 samples found a maximum density difference of 1.19e-7.
Actual compaction frames were inspected; owner acceptance remains pending.

All-state low-progress frontier correction: the uncertainty principle applies from
the first visible progress through the entire active lifecycle. Preserve a minimum
48 drawable-pixel dissolve extent at 1%, using sparse fading stars rather than a
precise percentage cutoff. Zero stays empty and fades in continuously; explicit
completion remains authoritative. This shared frontier update does not redesign
other states' motion. All 12 related tests passed, including 30 low-progress
state/size/phase samples. Actual 1% thinking and compaction frames were inspected;
owner acceptance remains pending.

## Production integration authorization — 0.4.6 Build 2

On 2026-09-06 the owner explicitly requested integrating the current quantum-noise
candidate into 0.4.6 Build 2, smoke testing and launching the resulting app.
Implementation is authorized; production visual acceptance and public release are
separate and pending. Reuse the current grain, state-aware motion, warm-gold
transfer and low-progress uncertainty frontier. Retain real state/progress sources,
original lifecycle, completion timing, Reduce Motion, Metal fallback and all other
effect styles. No demo data, manual progress injection or console entry point enters
the production target. Validate production tests, Universal Release, version/resources,
signature and launch. Public release/appcast changes are outside this request.

Production verification (2026-09-06): 177 tests passed (166 existing plus 11 migrated
motion/Metal regressions). Universal Release includes matching 0.4.6 / internal 19 /
display Build 2 app and widget, dual-architecture app/widget/helper, and required
icon/assets. Developer ID-signed local candidate and extracted ZIP pass strict deep
signature verification. The exact Build 2 process was launched and the native island
reported real Codex task activity. No production screenshot or automated visual
acceptance was performed. No demo injection entered Sources. Public release,
notarization and appcast are outside this local candidate delivery.

## Final production acceptance · 2026-09-06

Thinking now reuses the accepted natural gathering and dispersal motion while
retaining its original blue-violet palette. Compression retains its silver palette.
The owner observed real Codex context compaction and subsequent thinking tasks,
accepted the current version, and authorized 0.4.6 Build 2 as the Build 1 hot update.
The final source passes all 177 tests and a Universal Release build. No runtime
mock, manual progress injection or console entry point is included in production.
The full appearance, language and accessibility matrix remains a separate check;
the owner's acceptance here covers the demonstrated activity effect.
