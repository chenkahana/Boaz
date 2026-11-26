# The Boaz plan

**North star (Chen, 2026-11-26): Boaz is the go-to browser for people looking for simplicity, stability and accuracy. Make it perfect.**

This plan turns the November 25 gap analysis (Boaz vs Arc, Dia and the other Chromium browsers) into ordered,
agent-executable work items. Product owner: Instinct (main agent). Devs: coding agents (Claude, Codex, Instinct).
Chen decides must-have changes and every item marked **Needs Chen**; nobody else does.

Wave order follows the pillars: stability is the foundation accuracy and simplicity stand on, so it goes first.
Features nobody will love come last, after the browser is provably solid.

## How agents work this plan

1. Read [docs/must-haves.md](../must-haves.md) before anything. A fix that breaks a must-have is not a fix.
   Only Chen adds, changes or removes one.
2. Pick the first **Ready** item whose dependencies are **Done**. Work waves in order. Items in different waves
   with no dependency between them may run in parallel.
3. Claim an item by setting its `Status:` line to `In progress — <agent name>, <date>` on your branch and opening
   a draft PR titled `[plan] PLAN-NN: <title>`. First come, first served. Never touch an item another agent holds.
4. Append to the item's **Progress log** in every PR that advances it: one line per session — what changed and
   what evidence (CI runs, measurements, screenshots).
5. An item is **Done** when every acceptance criterion is met, the evidence is recorded in the item file, and the
   same PR sets `Status: Done` and ticks the board row below. Partial work updates the log, never the status.
6. Every app change merged to master ships with a CHANGELOG entry (must-have #14). Docs-only changes don't need
   one, and don't trigger a DMG release.
7. Reviews follow [REVIEW.md](../../REVIEW.md). QA follows [docs/qa.md](../qa.md); the Chromium ledger is
   [docs/chromium/parity.md](../chromium/parity.md).
8. Hit a decision only Chen can make? Set `Status: Needs Chen — <the exact question>` and move to another item.
   Never guess on his behalf.
9. Found a problem outside your item? File a GitHub issue per docs/qa.md's Reporting section; don't fix it in
   your PR.

## The board

| Item | Title | Wave | Status |
|---|---|---|---|
| [PLAN-01](items/01-green-mac-ui-tests.md) | Green, trustworthy Mac UI tests | 0 Stability | Ready |
| [PLAN-02](items/02-runtime-acceptance-dmg.md) | Chromium DMG runtime acceptance | 0 Stability | Ready |
| [PLAN-03](items/03-chromium-update-runbook.md) | Chromium security-update runbook, drilled | 0 Stability | Ready |
| [PLAN-04](items/04-performance-baselines.md) | Performance baselines refreshed | 0 Stability | Ready |
| [PLAN-05](items/05-safe-browsing.md) | Phishing and malware protection | 1 Accuracy | Ready |
| [PLAN-06](items/06-two-products-one-name.md) | Two products, one name: clear separation | 1 Accuracy | Needs Chen — naming decision |
| [PLAN-07](items/07-password-sync.md) | Passwords sync across devices + iOS AutoFill | 1 Accuracy | Ready |
| [PLAN-08](items/08-site-space-routing.md) | Site-to-space routing (Air Traffic Control) | 2 Simplicity | Ready |
| [PLAN-09](items/09-tab-groups.md) | Tab groups | 2 Simplicity | Ready |
| [PLAN-10](items/10-boosts-lite.md) | Boosts-lite: per-site customization | 2 Simplicity | Ready |
| [PLAN-11](items/11-testflight-beta-ring.md) | TestFlight beta ring | 3 Operations | Needs Chen — App Store Connect access |
| [PLAN-12](items/12-crash-feedback-loop.md) | Crash feedback loop without telemetry | 3 Operations | Ready |
| [PLAN-13](items/13-app-store-pipeline.md) | App Store submission pipeline | 3 Operations | Needs Chen — App Store Connect access |

## Not planned, and why

- **Widevine DRM**: waiting on Google's answer to the license inquiry (submitted 2026-11-13). Vendor-waiting, not
  engineering. Status lives in [docs/chromium/widevine.md](../chromium/widevine.md).
- **Passkeys**: waiting on Apple's managed-entitlement grant (request Z6525VUX9T; Chen to check its status and
  confirm iOS coverage). Once granted, the repo side is one line: set the `passkeys.yml` include to `enable: true`
  in `project.yml` and regenerate.
- **History sync**: forbidden by must-have #11 — history never leaves the device. This is a feature, not a gap.
- **Server-side AI**: forbidden by must-have #12. Positioning is settled: calm, private, accurate beats a cloud
  model for this product. Not revisited without Chen.
- **Easels**: Arc's surface that even Arc and Dia abandoned. Revisit after Wave 2 lands and only if users ask.
- **Windows/Android**: accepted platform ceiling. Boaz is the Apple-native browser; that focus is the product.
- **Monetization**: not on the table. Boaz is a craft product; Chen decides if that ever changes.
