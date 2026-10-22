# Master plan

## Vision

A calm, personal browser that keeps everything people loved about Arc - sidebar, spaces, folders, lifecycle rules, command bar - and surpasses it where Arc fell short: no duplicate tabs, a real home for occasional bookmarks, per-site lifecycle exceptions, Linux support, and sync the user owns.

**Product promise:** the browser that pays attention. It notices duplicates, anticipates where a link belongs, keeps your spaces clean, and gets out of the way.

## Non-goals (v1)

- No AI chat/agent layer. Arc's successor Dia went AI-centric; our differentiation is ergonomics and calm. AI features can be revisited after v1 only if they serve the organization model.
- No mobile app in v1. Desktop first (macOS, Windows, Linux).
- No extension store of our own. Use the engine's existing extension mechanism.

## Strategy bets (what "surpasses Arc" means)

1. **Zero duplicate tabs.** Opening a URL that is already open focuses the existing tab and flashes its location (space + folder). Opt-out per site.
2. **A real home for everything.** Beyond pins and today tabs: a lightweight "Shelf" for occasional bookmarks and bookmarklets, searchable, never in the way.
3. **Lifecycle rules as a first-class system.** Auto-archive with per-site and per-folder exceptions, configurable thresholds, and an "about to archive" morning digest instead of silent disappearance.
4. **Owned sync.** End-to-end encrypted sync with a self-hostable relay. No account lock-in; export everything as JSON/Markdown at any time.
5. **Attention-aware media.** Auto-PiP on tab switch away from active calls/video, per-site rules, mini-player with global shortcut.
6. **Everywhere Arc wasn't.** Linux as a first-class target; Windows and macOS at parity.

## Phases and gates

| Phase | Goal | Exit gate |
| --- | --- | --- |
| 0. Foundation | Repo, engine checkout, build pipeline, CI producing a runnable branded shell | Clean build on macOS + Linux + Windows from CI |
| 1. Core loop | Sidebar (pins, today tabs, folders, rename), spaces, command bar v1 | Daily-driveable for one user for a week |
| 2. Order | Tab lifecycle rules, duplicate-tab interception, Shelf, Peek | A 30-tab chaos session self-organizes without manual cleanup |
| 3. Flow | Split view, link routing (ATC), media/PiP rules, hover previews | Full Arc parity on the ranked feature list |
| 4. Surpass + ship | Sync, theming engine, polish, onboarding, import from Arc export | Public beta |

Gate reviews are human decisions; the coding agent prepares a short status doc per gate (`docs/gates/phase-N.md` created at that time).

## Success metrics

- **Daily-driver test:** the founder uses it as the only browser for 2 consecutive weeks by end of Phase 3.
- **Tab half-life:** median open-unpinned tab count stays under 12 during a work week without manual cleanup.
- **Duplicate rate:** duplicate-URL opens drop to ~0 with interception on.
- **Parity checklist:** every item in `docs/RESEARCH.md` section 2 ranking works (folders, rename, PiP, sidebar, calm design, lifecycle, command bar, spaces).

## Risks

| Risk | Mitigation |
| --- | --- |
| Engine maintenance burden (the thing that killed Arc) | Fork an actively maintained upstream (see ARCHITECTURE.md); never fork raw Chromium |
| Scope creep into an OS | Non-goals list; each phase has a hard exit gate |
| One-maintainer burnout | Small PR discipline (AGENTS.md), upstream inheritance, feature flags off by default |
| Trademark/branding drift toward Arc | Codename + original design tokens; legal note in README |

## Timeline posture

Arc dies 2026-12-22. Realistic posture: have Phase 1 done around then so Arc refugees (including the founder) land somewhere warm. Phases are quality-gated, not date-gated.
