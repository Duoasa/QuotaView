## Change

Describe the problem, resulting behavior, and relevant scope limits.

## Specification

Link the owning Spec and Requirement IDs and any changed acceptance criteria.
Without spec impact, write `Spec impact: None` and a short reason.
Include specification/delivery states only when this PR changes them.

## Verification

List checks and results using [the verification rules](../docs/workflow/VALIDATION.md).
Explain material gaps and affected visual/interaction scenarios waiting for owner
acceptance. Markdown-only changes need link, consistency, and diff checks, not
Swift tests or builds.

## Additional impact (omit when unrelated)

Describe changed protocol, compatibility, privacy, localization, or debug paths.
Prototype checks do not prove production behavior. Preserve the permanent Island
Text Console; remove temporary production injection before submission.

For release work, state the exact version and authorized channels, following
[the release rules](../docs/workflow/RELEASE.md). Include immutable rollback and
artifact evidence. Implementation approval does not authorize publication;
report only release operations that actually happened.
