# Feature: Command bar

Priority basis: ranked #7 (shortcuts/command bar) by users; the "Spotlight for the browser" in reviews.

## Goal

One bar for everything: `Cmd/Ctrl+T` opens it. It searches your open tabs first, then bookmarks/shelf/archive, then the web. Hit `Tab` to switch from search mode to command mode and run any browser action by name.

## Spec

- Ranking: open tabs > shelf/pins > archive/history > web suggestions. Show section labels.
- A result for an already-open URL switches to that tab (never duplicates; see `duplicate-interception.md`).
- Command mode (`Tab`): fuzzy-matches every action (e.g. "split", "new space", "archive all today tabs"), shows the action's shortcut alongside.
- Every result actionable by keyboard only; full navigation without touching the mouse.
- Latency budget: first results under 100ms on 5k tab items (Arc's bar was called laggy - this is a bar to beat).

## Acceptance criteria

- [ ] `Cmd/Ctrl+T` opens bar centered over the page with `glass.bg` surface, `radius.card`
- [ ] Open-tab results ranked above web suggestions, with space + folder breadcrumb
- [ ] Selecting an open-tab result focuses it (including across spaces)
- [ ] `Tab` switches to command mode; at least 30 core commands registered
- [ ] Every command has a remappable shortcut shown in the bar
- [ ] 100ms first-result budget measured in an automated perf test

## Implementation notes

- Index lives in memory over the `core/` model; web suggestions via the user's default search engine with a 150ms debounce and cancellation.
- Command registry is the single source of truth for shortcuts (settings UI renders from it).

## Out of scope

Natural-language/AI queries (non-goal for v1, `docs/PLAN.md`).
