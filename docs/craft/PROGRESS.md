RESUME HERE: R5.3, slice each workstream into one-visible-change PRs in R5-backlog.md, in shipping order, marking the ones that need Chen's yes (must-have adjacent, visible behaviour change, new system integration).

# Craft research: progress


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
- 2026-11-18 · R3.3 · Arc known mechanics; new MS-15 (space swipe not interactive) · (this commit)
- 2026-11-18 · R3.4 · Chrome known mechanics, 5 takeaways · (this commit)
- 2026-11-18 · R3.5 · Dia: AI surface takeaway, kept as judgment (must-hve 12) · (this commit)
- 2026-11-18 · R3.6 · Orion: low-weight notes · (this commit)
- 2026-11-18 · R3.7 · 14-item steal-this list mapped to R2; note: the R3.5 commit also carried the R3.6 text · (this commit)
- 2026-11-18 · R4.1 · Motion: 45 curves today → 4 tokens per platform + 6 transitions, Reduce Motion in the token · (this commit)
- 2026-11-18 · R4.2 · Haptic map: 11 iPhone events (4 new), 5 Mac events, Haptics enum shape · (this commit)
- 2026-11-18 · R4.3 · Layout tokens: spacing ladder, radius scale with concentric rule, 44/48 pt targets; corrected E11 (iOS Theme.Radius exists) · (this commit)
- 2026-11-18 · R4.4 · Type ramp: iPhone text-style roles, Mac ramp derived from the sidebar text size · (this commit)
- 2026-11-18 · R4.5 · Copy rules, glossary (9 terms), String Catalog plan; 30 hand-built plurals counted · (this commit)
- 2026-11-18 · R4.6 · State kit: 5 components, 300 ms rule, one PageFailure for all builds · (this commit)
- 2026-11-18 · R4.7 · Handoff design: activity type, Incognito never advertises, landing places, must-haves 2/7/10/11/13, one open question · (this commit)
- 2026-11-18 · R5.1 · R5.1 done: R5-backlog.md ranks 87 findings (scores recomputed by script from R2/R3 cells, all match; AX-15/ML-6 pass notes and IM-6 left out) plus 8 system items SY-1..SY-8 from R4 and the code sweeps (SY-7 ⌘Z UndoManager had no R2 row). S1 first: AX-8, AX-9; then IB-2 12, MW-1 12, AX-12 9, MC-1 9. · (this commit)
- 2026-11-18 · R5.1 correction · The R5.1 parser dropped WX-1 (unescaped `|` inside its evidence code span split the row). Now parsed from both ends: 88 findings, WX-1 at #56 (score 3), all scores still match · (this commit)
- 2026-11-18 · R5.2 · R5.2 done: 96 items (88 findings + SY-1..8) in W1–W9, each exactly once (script-checked). Totals: W4 96.3, W3 68 (both S1s), W2 58, W1 41.5, W5 34.5, W9 29, W6 27, W7 8, W8 7. · (this commit)
