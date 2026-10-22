# Feature: Tab lifecycle (auto-archive done right)

Priority basis: ranked #6 by users; Arc's boldest default, but capped at 30 days with no exceptions UI (`docs/RESEARCH.md` section 4).

## Goal

Today tabs clean themselves up. Nothing you might still want vanishes silently; everything archived is findable in seconds.

## Spec

- Default: today tabs not touched for 12 hours move to the Archive. Configurable globally: 12h / 24h / 7d / 30d / never.
- **Exceptions, first-class:** per-site ("never archive github.com") and per-folder rules, editable from tab context menu and a single rules page.
- **Morning digest:** once per day on first launch, a small card lists what will archive today with keep/dismiss actions. Never a modal; dismissible forever.
- Archive is a searchable, grouped-by-day list (`Cmd+Shift+A`), items restore to their original space/folder position.
- Pinned tabs and favorites never archive.

## Acceptance criteria

- [ ] Tabs idle past threshold archive automatically; pinned/favorites untouched
- [ ] Per-site exception survives restart and wins over global policy
- [ ] Digest appears at most once/day, lists correct candidates, keep/dismiss work
- [ ] Archive search matches URL, title, and custom tab name; restore returns tab to original location
- [ ] "Never" disables archiving globally with zero digest prompts

## Implementation notes

- `core/lifecycle` runs the scheduler; timestamps from the TabItem model (`lastActiveAt`).
- Archive is plain JSON on disk, synced later (sync.md); never a proprietary store.

## Out of scope

Archive analytics/stats (maybe later; not v1).
