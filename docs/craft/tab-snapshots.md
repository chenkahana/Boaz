# Live tab snapshots (Mac DMG) — added at Chen's request, 2026-11-18

**Ask (Chen):** "The tab preview is blurred and doesn't display the actual last seen tab. It should save the HTML
presented and keep it activated, so the user can scroll."

## What happens today (code, `66c3d63`+)

- A window keeps at most 10 live Chromium pages (`BrowserState.swift:413`, `maxLivePages`). Older tabs are closed and
  reload from the network when you return to them, with their scroll position restored afterwards
  (`prepareChromiumScroll`, `BrowserState.swift:1227`).
- While that reload runs, the pane shows an image over the page with a "Saved preview" caption
  (`WebPane.swift:107-121`). The image is:
  - **captured once, when the page first finished loading** (`WebPane.swift:158-173`, keyed by navigation), so it shows the top of
    the page as it first loaded, not what you last saw;
  - **at most 1024 × 768 px** (`ChromiumEnginePageAdapter+Capture.swift:12`), then `scaledToFit` across the whole
    pane: a 1400 × 900 pt pane on Retina is 2800 × 1800 px, so the image is stretched about 2.7× → blurred;
  - **dead**: `.contentShape(Rectangle()).onTapGesture {}` swallows clicks and scrolling until the live page is ready;
  - **memory only, 20 per window** (`BrowserState.swift:160`), so after a relaunch there is no preview at all.
- The sidebar hover preview (`ChromiumTabPreview.swift`) uses the same stale image.

This supersedes MW-2 (the "Saved preview" caption).

## Proposal

The tab you come back to looks exactly as you left it, sharp, at the same scroll position, and you can scroll,
select and copy right away. The live page takes over underneath without a visible jump.

1. **Freeze before you unload.** Past the live-page budget, freeze pages (Chromium page lifecycle: frozen, no CPU,
   DOM kept) instead of closing them. Close frozen pages only under system memory pressure
   (`DispatchSource.makeMemoryPressureSource`), oldest first. Most returns become instant and exact, with no
   snapshot needed.
2. **Snapshot the DOM, not pixels, when a page has to close.** Just before closing a page, and on app quit, save:
   - the current DOM as MHTML (Chromium's `WebContents::GenerateMHTML`, which serializes the page as presented, with its
     CSS and images);
   - the scroll position, plus an anchor element for each scrolling container;
   - one full-resolution capture of the visible area at the window's backing scale, used as the very first frame and
     by the sidebar hover preview.
3. **Show the snapshot as a live, read-only page.** On return, the pane immediately shows the MHTML in a Chromium page
   in the tab's own profile with JavaScript off and network off, scrolled to the saved spot. Scrolling, text
   selection, copy and Find work. A click on a link or a form field hands over to the live page (queued until it's
   ready).
4. **Hand over without a jump.** The live page loads underneath. Once it's interactive, its scroll is set to where the
   user has scrolled in the snapshot (anchor first, offset as fallback), then the two cross-fade (Reduce Motion: an
   instant swap). Remove the "Saved preview" caption. If the live load fails (offline), the snapshot stays, with the
   existing offline banner.
5. **Storage and privacy.**
   - Snapshots are stored per profile, inside that profile's data directory, as an LRU (for example 200 MB per profile).
   - A snapshot is deleted when its tab is closed, archived or navigated away from.
   - Incognito snapshots stay in memory only and are never written.
   - Snapshots are never synced (must-have 11).
   - `docs/privacy.md` gets a line saying this.
6. **Sidebar hover preview.** Refresh the capture whenever a tab is deactivated, so it shows the last-seen state at
   full resolution.

## Must-haves

- 1 (Chromium): the snapshot renders in Chromium. Holds.
- 3 (per-profile session): the snapshot page uses the tab's own profile, with its network turned off. Holds.
- 11 (sync): snapshots never leave the device. Holds.
- 13 (library never lost): untouched. A snapshot is a cache; losing one only costs a reload.

## Risks to check in the spike

- What MHTML can't capture: canvas, WebGL, video frames and closed shadow roots render blank. Fall back to the
  full-resolution image for those regions, or for the whole page when the DOM is mostly canvas (Figma, Google
  Docs).
- Cost of MHTML generation on heavy pages: it must run off the UI path and be bounded by size and time. If it's
  too slow, keep the capture and drop the snapshot.
- Layout drift between the snapshot and the live page (fonts, ads, A/B tests). The scroll anchor has to land on
  the same element.
- Memory held by frozen pages. Measure with 30 or more tabs before setting the budget.

## Verification

Before/after recordings with 15+ tabs in a window, returning to a tab scrolled halfway down a long article, a
GitHub PR, Gmail and a canvas app. Check sharpness at 100%, immediate scroll, no jump at handover, the offline
return, a relaunch, Incognito leaving no files on disk, and must-haves 1, 3, 11 and 13 in the real app.
