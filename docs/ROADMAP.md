# Roadmap

Phase-gated task breakdown. Each task is sized for a single coding-agent PR. Specs: `docs/features/`. Conventions: `AGENTS.md`.

## Phase 0 - Foundation

- [ ] Fork `zen-browser/desktop` into `engine/`, document upstream sync procedure in `engine/UPSTREAM.md`
- [ ] CI: build on macOS, Windows, Linux; cache aggressively; artifact per commit
- [ ] Strip Zen branding, apply codename + neutral theme
- [ ] Token pipeline: `docs/DESIGN.md` tokens -> theme JSON -> chrome CSS variables
- [ ] `docs/compat-log.md` started; log every site misbehavior from day one

## Phase 1 - Core loop (daily-driver MVP)

- [ ] `features/sidebar-and-tabs.md`: three-section sidebar, pins, favorites
- [ ] `features/sidebar-and-tabs.md`: nested folders, drag between sections
- [ ] `features/sidebar-and-tabs.md`: tab rename (custom name + original tooltip)
- [ ] `features/spaces-and-profiles.md`: spaces with per-space theme + container binding, swipe/shortcut switching
- [ ] `features/command-bar.md` v1: open-tab-first search, web fallback, `Tab` command mode
- [ ] Blank new window + sidebar hide/show (`Cmd+S`)
- [ ] Gate review: founder daily-drives for 1 week

## Phase 2 - Order

- [ ] `features/tab-lifecycle.md`: auto-archive engine + searchable archive
- [ ] `features/tab-lifecycle.md`: per-site/folder exceptions + morning digest
- [ ] `features/duplicate-interception.md`: focus-existing + location flash, per-site opt-out
- [ ] `features/peek.md`: preview overlay from pinned/favorite tabs
- [ ] `features/shelf.md`: occasional bookmarks + bookmarklets, command-bar searchable
- [ ] Gate review: 30-tab chaos session self-organizes

## Phase 3 - Flow (Arc parity)

- [ ] `features/split-view.md`: 2-4 tile splits, splittable groups as saveable tabs
- [ ] `features/link-routing.md`: ATC rules engine + UI
- [ ] `features/media-and-pip.md`: auto-PiP, per-site rules, mini-player
- [ ] Hover previews for favorites (unread state for supported sites)
- [ ] Engine re-evaluation gate (Firefox vs CEF, per `docs/ARCHITECTURE.md`)

## Phase 4 - Surpass + ship

- [ ] `features/sync.md`: E2E sync + self-hostable relay + JSON/Markdown export
- [ ] Theming engine: custom gradients, per-space light/dark
- [ ] Arc import: read Arc's exported links/data into spaces
- [ ] Onboarding: 3-minute setup that teaches sidebar, spaces, command bar
- [ ] Public beta checklist: update channel, crash reporting (opt-in), privacy policy
