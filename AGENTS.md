# Instructions for coding agents

This repo is documentation-first. Treat every doc as the spec of record.

## Ground rules

1. **Original work only.** Never copy Arc's code, assets, strings, icons, fonts, or branding. Behavior described in these docs comes from public reviews and user reports, not from Arc's source. If a task seems to require copying something from Arc, stop and flag it.
2. **Specs are contracts.** Each file in `docs/features/` has acceptance criteria. A feature is done only when every criterion passes and the checklist at the bottom of its doc is ticked in the doc itself (mark `[x]`).
3. **Design tokens are law.** All visual values come from `docs/DESIGN.md`. Do not invent new colors, radii, or timings; extend the token table instead.
4. **Small PRs.** One feature slice per PR. Reference the spec file in the PR body (e.g. `Implements docs/features/command-bar.md#acceptance-criteria`).
5. **Engine decision is fixed per phase.** The current engine base is recorded in `docs/ARCHITECTURE.md` under "Decision of record". Do not switch engines without updating that section and `docs/PLAN.md` first.
6. **Tests with the feature.** Playwright (or the engine's equivalent) for every user-facing acceptance criterion that can be automated.
7. **Privacy default.** No telemetry without an explicit spec. Sync is end-to-end encrypted by design (see `docs/features/sync.md`).

## Definition of done

- Acceptance criteria in the feature spec pass.
- Tokens from `docs/DESIGN.md` used; no hardcoded visual values.
- Shortcuts listed in the feature spec work and are remappable where specified.
- Docs updated if behavior diverged from spec, with a one-line note why.
