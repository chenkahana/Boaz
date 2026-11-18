# R3. Reference teardown

What the apps to beat do at the five moments that matter (tab open/close, tab overview, address entry, page menu,
sidebar or tab-strip drag), written as mechanics. Apps to beat (§7.1): **Safari on iPhone**, **Arc on the Mac**;
Chrome, Dia and Orion are secondary.

Evidence levels: **observed** = captured in this pass (screenshots, hierarchy dumps, recordings under
`~/tmp/codex/boaz-craft/`); **known** = documented or widely observed behaviour, not captured here, to confirm by
frame-stepping before an implementation PR relies on it. Driving Arc, Chrome, Safari or other browsers on the Mac
would take over Chen's session and touch his browser profiles, so every Mac reference is "known" and the
frame-stepping is **needs Chen session** (QuickTime at 120 Hz, then step frames in QuickTime or `ffmpeg -vf
select`).

## R3.1 Safari on iPhone (observed, iOS 27.1 simulator, same Duo folded screen as Boaz)

Captured with the same harness driving MobileSafari: `shots/ios/safari/s00–s08`, `rec/safari.mov`. Safari on the
Duo's cover screen also puts its controls in the right-hand column, so the two apps compare directly.

| Moment | Safari mechanics | Boaz today | Gap → finding |
|---|---|---|---|
| Rail / toolbar | Every column control is **48 × 48 pt**: Back (top), Bookmarks, then New Tab and Tabs at the bottom; the page menu is a 48 pt glass button at the **bottom-left** of the page, Reload is a small glyph in the address pill. | 34 × 40 tab fan, 46 New Tab, 56 page menu, 60 Search | One size, one rhythm → IB-2, IB-9 |
| Address entry | Field sits at the bottom of the page area above the keyboard with a dismiss (✕) button beside it; top hit row with the site's icon and the completion highlighted inline ("exam**soft — Examsoft**"); suggestions grouped under a header ("Google Suggestions"); first-run explainer once. | Bottom panel field, inline completion, rows without section headers | Group headers ("Search", "Open Tabs", "History") and spoken kind → AX-4, R4 copy |
| Page menu | A **popover menu** (≈250 pt wide, 42 pt rows) anchored to its button, not a sheet; items grouped by dividers: Reader · Translate │ Share · Add to Bookmarks · Add Bookmark to… │ Find on Page · Page Zoom · Notify Me · Hide Distracting Items │ Extensions │ Tab Actions · Privacy & Security · Request Desktop Website. Rows that open a step end in "…". | Half-height bottom sheet, one undivided list, app items at the end | Group with dividers, move app items out → IM-1, IM-2 |
| Tab overview | Opens from the Tabs button into a **grid of cards** (one column on this narrow screen), each card with its own 22 pt **close ✕** and the favicon + title under it; Search tabs, Filter and More in the column; a **Private │ N Tabs** segmented capsule at the bottom switches tab groups; Done is a filled blue ✓. | Deck of one large card, swipe up to archive, no per-card close, no visible Incognito switch | Visible mode switch and per-card close → IB-1, IB-6 |
| Private | A tab group of its own, chosen in the overview; the whole chrome goes dark in Private. | Toggle in the page menu; chrome unchanged | → IB-1 |

Steal this (Safari, iPhone):
1. **One control size (48 pt) for every rail and bar button**, and the page menu as a separate corner button. → IB-2, IB-9, W2.
2. **Page menu as a grouped popover with dividers**, page items first, tab and site items after, nothing app-level. → IM-1, IM-2, W6.
3. **Private as a visible tab group in the overview**, with dark chrome while in it. → IB-1, W6 (needs Chen's yes: visible behaviour change).
4. **Per-card close in the overview** next to the swipe gesture. → IB-6, W6.
5. **Suggestion section headers** ("Google Suggestions") so sighted and VoiceOver users both know a row's kind. → AX-4, W4.
