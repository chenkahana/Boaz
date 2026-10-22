# Architecture

## The engine decision

Arc's killer was maintenance: keeping a raw Chromium fork secure became untenable even for a funded company. Our first architectural law: **never own the engine's security surface**. We build on an upstream that ships security updates we inherit.

Cost ladder for building a browser (source: <https://entalogics.com/blog/what-it-takes-to-fork-chromium-enterprise-browser-development>): Electron wrap (weeks) < embed via CEF/Qt WebEngine (months) < raw Chromium fork (quarters + permanent maintenance, 100GB+ builds, 2-week upstream cadence from Chrome 153). A raw fork is off the table for this team size.

### Options compared

| Option | Engine | Pros | Cons | Verdict |
| --- | --- | --- | --- | --- |
| **Fork Zen Browser** (<https://github.com/zen-browser/desktop>, MPL-2.0) | Firefox | Already has workspaces, vertical tabs, split view, glance, compact mode; active upstream security; MPL allows a fork | Firefox site/extension compat differences; some Meet/PiP quirks reported; we inherit Zen's look unless we reskin deeply | **Base for Phase 0-1** |
| Electron shell | Chromium (via Electron) | Fast UI iteration in web tech; Codex-friendly; total chrome control | Poor Chrome-extension support; memory/perf stigma; you own more of the stack than it looks | Design playground only |
| CEF embed | Chromium | Real Chromium, native chrome | Months of plumbing; you maintain CEF upgrades | Reconsider at Phase 3 gate |
| Raw Chromium fork | Chromium | Total control | Exactly what killed Arc | Rejected |

### Decision of record

**Phase 0-2 base: fork `zen-browser/desktop`.** Replace its chrome layer with our design system (tokens in `docs/DESIGN.md`), then implement the feature specs in `docs/features/`. Zen's workspace/tab infrastructure covers a large part of the core loop; our work concentrates on what Zen lacks per the gap analysis in `docs/RESEARCH.md` section 5 (folders with nesting, tab rename, lifecycle rules with exceptions, command bar, Peek, ATC routing, duplicate interception, Shelf, owned sync).

**Phase 3 gate:** re-evaluate CEF/Chromium if Firefox-compat issues block daily driving for the founder (track every site that misbehaves from day one in `docs/compat-log.md`).

## Module map (target state)

```
canopy/
  engine/            # zen fork, minimal patches; upstream-mergeable
  chrome/            # our UI layer (themeable)
    sidebar/         # pins, today tabs, folders, shelf
    command-bar/
    peek/
    split-view/
    routing/         # link rules (ATC)
    media/           # PiP controller, mini-player
  core/              # engine-agnostic logic
    lifecycle/       # auto-archive rules, digest
    dupes/           # duplicate interception
    spaces/          # space model, profiles, per-space state
    sync/            # E2E sync client
    theming/         # token engine, gradients, glass
  docs/              # this repo's specs
```

Rule: features live in `core/` as engine-agnostic state machines wherever possible, with thin adapters into `engine/`. This keeps the Phase 3 engine re-evaluation cheap.

## Data model (v1)

- **Space**: id, name, theme (gradient id or custom stops), profile/container binding, sort order.
- **TabItem**: id, url, title, customName?, kind (favorite | pinned | today | shelf), folderId?, spaceId, openedAt, lastActiveAt, lifecyclePolicy?, splitGroupId?
- **Folder**: id, name, parentId?, spaceId, collapsed.
- **Route**: id, match (contains|equals|regex), value, targetSpaceId.
- **LifecyclePolicy**: archiveAfter (12h|24h|7d|30d|never), exceptions[] (site or folder), digestEnabled.
- All of the above serialize to JSON for sync/export.

## Sync

E2E-encrypted (keys derived from a user passphrase, never server-readable). Relay is a dumb encrypted-blob store with a reference implementation the user can self-host in one container. See `docs/features/sync.md`.

## Extensions

Phase 1-2: whatever the engine supports (Firefox extensions on the Zen base). Do not build custom extension infrastructure.
