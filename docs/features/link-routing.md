# Feature: Link routing (Air Traffic Control, evolved)

Priority basis: documented Arc power feature (`docs/RESEARCH.md` section 2). Arc source: <https://resources.arc.net/hc/en-us/articles/22932014625431-Air-Traffic-Control-Automate-Your-Link-Routing>

## Goal

Links open where they belong, automatically. Work links land in Work, music in Music - no matter where they were clicked.

## Spec

- Rules: match type `contains` | `equals` | `regex` against URL -> target space (optionally: folder, pinned vs today).
- Default rule: external links (clicked from other apps) open in a chosen default space, or "most recent space".
- Rule evaluation order: first match wins; drag to reorder.
- Rule editor: one screen (`Cmd+, -> Links`), rows of match/value/target, test-a-URL field.
- When a rule fires, a subtle toast names the rule ("Opened in Work - rule: sheets.google.com"), with "don't route this next time" escape.

## Surpass-Arc additions

- Suggest rules: after the user manually moves the same domain to a space 3 times, offer a rule.
- Import/export rules as JSON (syncable, shareable).

## Acceptance criteria

- [ ] contains/equals/regex rules route links to the right space from any source app
- [ ] Default-space rule covers unrouted external links
- [ ] Rule reorder changes evaluation outcome; test field shows which rule matches
- [ ] Toast appears on rule fire with working undo-for-next-time
- [ ] Rule suggestion appears after 3 manual moves and can be dismissed permanently
- [ ] Rules export/import round-trips

## Implementation notes

- `core/routing` intercepts navigation intents before tab creation (pairs with duplicate interception: route first, dedupe second).
- Rules live in the JSON data model; sync later via sync.md.

## Out of scope

Per-rule time schedules ("route work links only 9-5") - post-v1 candidate.
