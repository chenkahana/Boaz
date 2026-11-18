# Craft research: progress

RESUME HERE: R3.3, Arc (the Mac app to beat): known mechanics for sidebar drag, space switch swipe, command bar, Little Arc/peek, split, archive, ⌘Z.

Runtime rules for whoever resumes: never move, delete or modify `~/Library/Containers/com.chenkahana.boaz` or Chen's
Chromium profile data, and never quit Chen's running Boaz (must-have 13). Mac runtime that would risk either is
recorded as "needs Chen session" with exact steps. The iOS simulator only drives the Duo's folded screen; open, book
and laptop postures are "needs device". Binaries go to `~/tmp/codex/boaz-craft/`, never into git.

## Log

Append-only. One line per completed sub-step: date, step, what was done, commit.

- 2026-11-18 · setup · Worktree `~/.worktrees/Boaz/craft-research` on `docs/craft-research` from `origin/master` 66c3d63; plan copied to `PLAN.md` with checklist; `tasks/ux-review.md` copied to `inputs/` · (this commit)
- 2026-11-18 · R0.1 · iPhone Duo sim (folded) installed; isolated Mac WebKit build runs in background; standard iPhone, Duo postures and DMG runtime marked needs device / needs Chen session · (this commit)
- 2026-11-18 · R0.2 · iPhone main + tab flows recorded light and dark with audits; Mac static captures and menu inventory · (this commit)
- 2026-11-18 · R0.3 · iPhone launch metric 2.4–2.9 s first frame (sim Debug); hitches unsupported in sim; Mac isolated window 0.36–0.66 s · (this commit)
- 2026-11-18 · R0.4 · R0-baseline.md summary written; R0 complete · (this commit)
- 2026-11-18 · R1.1 · iPhone inventory, 23 surfaces · (this commit)
- 2026-11-18 · R1.2 · Mac inventory, 27 surfaces incl. DMG-only · (this commit)
- 2026-11-18 · R1.3 · widgets, share extension, intents, links, system integrations inventoried · (this commit)
- 2026-11-18 · R1.4 · R1 summary of cross-surface patterns; toast announcement claim corrected after checking code · (this commit)
- 2026-11-18 · R2.1 · Mac sidebar: 12 findings (MS-1…MS-12) · (this commit)
- 2026-11-18 · R2.2 · Mac command bar: 6 findings (MC-1…MC-6) · (this commit)
- 2026-11-18 · R2.3 · Mac web pane and split: 8 findings (MW-1…MW-8) · (this commit)
- 2026-11-18 · R2.4 · Mac library panel: 6 entries (ML-1…ML-6, ML-6 a pass) · (this commit)
- 2026-11-18 · R2.5 · Settings: 6 findings (ST-1…ST-6); fixed a mis-read ellipsis in R1 · (this commit)
- 2026-11-18 · R2.6 · Onboarding: 5 findings (OB-1…OB-5) · (this commit)
- 2026-11-18 · R2.7 · iPhone bar/fan/carousel: 10 findings (IB-1…IB-10); Incognito flow captured; corrected R1 page-menu row · (this commit)
- 2026-11-18 · R2.8 · iPhone search panel: 4 findings (IS-1…IS-4) · (this commit)
- 2026-11-18 · R2.9 · iPhone page menu: 6 entries (IM-1…IM-6) · (this commit)
- 2026-11-18 · R2.10 · Duo postures: 4 code-read findings + needs-device checklist · (this commit)
- 2026-11-18 · R2.11 · Widgets/extensions/system: 5 findings (WX-1…WX-5) · (this commit)
- 2026-11-18 · R2.12 · iPhone audits summarised (18 screens); Mac CI audit from master's UITestResults (69 screenshots in shots/mac-ci); 3 AX findings; added MW-9 and CI evidence to ML-1, MS-9, MW-8 · (this commit)
- 2026-11-18 · R2.13 · VoiceOver walk derived from trees and code; 4 findings (AX-4…AX-7); device walk needs Chen · (this commit)
- 2026-11-18 · R2.14 · Dynamic Type AX3/AX5: 4 findings (AX-8…AX-11), incl. two S1 overlaps/truncations · (this commit)
- 2026-11-18 · R2.15 · Contrast/Motion/Transparency: 4 entries (AX-12…AX-15) · (this commit)
- 2026-11-18 · R2.16 · Re-verified all 40 findings of the 2026-11-09 review: 19 fixed, 11 open/partly open, 10 obsolete; added MS-13, MS-14 · (this commit)
- 2026-11-18 · R2.16 correction · recount of the re-verification table: 21 fixed, 10 open/partly open, 8 obsolete, 1 mixed (R2-findings.md tally fixed) · (this commit)
- 2026-11-18 · R2.17 · Craft scores for 11 surfaces (18–30 of 36); R2 complete · (this commit)
- 2026-11-18 · R3.1 · Safari iPhone driven in the Duo simulator; mechanics table + 5 steal-this items · (this commit)
- 2026-11-18 · R3.2 · Safari Mac known mechanics + 3 steal-this items · (this commit)
