# QuotaView 0.7.7 Build 1 — Agent Handoff

Updated: 2026-10-07, Asia/Shanghai.

## Development baseline

- **Release baseline:** `0.7.7 Build 1`; internal build `57`.
- **Current local development:** `0.7.7 Build 2`; internal build `58` (not published).
- **Tag:** `v0.7.7-build.1`.
- **Commit:** `3866177cfa19db734d657ef505a4dc72c3338fba`.
- **Local branch:** `codex/0.7.7-build1-development`.
- **Working directory:** `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget`.
- **Running app:** `/Users/sukduoasa/.codex/worktrees/quotaview-073/widget/.build/DevelopmentRuntime/QuotaView.app`; PID `49617`, started 2026-10-07 17:25 Asia/Shanghai. The prior dev process exited.

Continue from this release plus local changes: the existing settings/card UI polish and the selectively integrated Claude Code adapter. Do not replace them with the release snapshot or audit main. The owner authorized Build +1 after the layout fixes; the release baseline remains Build 1.

Settings now keep page titles/descriptions in the lower options section. The black header contains centered visuals; Island uses a taller production card with isolated sample data; Usage shows a simplified diagram of the actual card layout. Visible Demo labels are removed. The default window is 872 × 760 pt. Privacy/effects and optional usage modules follow settings. Real task/account stores are never seeded by the demos. Keep the running bundle outside Xcode Products: changing build output directories removed the earlier live bundle and broke image loading.

## Critical context

A subsequent 35-item audit implementation passed automated checks but produced many bugs during the owner's testing. The owner rejected that development build and requested both runtime and local source rollback.

Remote `main` still contains that later implementation (`dc49a3e`); the rollback was local. **Do not pull or merge remote `main`, reapply the audit changes, or launch the old audit Debug bundle by default.** A recovery branch and stash are documented at the top of [HANDOFF.md](HANDOFF.md).

## Start here

Read [AGENTS.md](AGENTS.md), the current section of [HANDOFF.md](HANDOFF.md), and [VERSION_HISTORY.md](VERSION_HISTORY.md). Consult [the specification index](docs/specs/README.md) for the specific change requested.

Claude integration: `ClaudeCodeRuntime.swift`, `ClaudeCodeBridge.swift`, `ClaudeCodeInstaller.swift`, `ClaudeCodeApproval.swift`, helper `ClaudeCodeHookMode.swift`, and Core transcript/usage/pricing readers. See [the Claude spec](docs/specs/claude-code-support.md). Its contributed increments were ported onto the release structure; audit refactors were excluded.

## Working rules

- Preserve local changes and user files. Keep the untracked `HANDOFF-NEXT-SESSION-2026-09-27.md` and `Prototypes/MultitaskIslandConsole/`.
- Keep development local; commit, push, or merge only when the owner requests it.
- Use minimal development compilation when running new changes is requested. Packaging, release signing, notarization, and appcast updates require explicit release authorization.
- Keep checks focused on necessary smoke tests and benchmarks. The owner performs visual and interaction acceptance.
- Preserve native approval ownership. macOS system permission dialogs are handled in macOS. Quota reset remains demonstration-only.

Next: continue locally from the merged source and collect owner acceptance of real interactions. The owner requested a new development build: unsigned Debug arm64 compilation succeeded and the merged app is running. No tests, release packaging, signing, or push were performed. Build log and runtime evidence: `.build/settings-proportion-20261007/development-build.log` and `development-runtime.json`.
