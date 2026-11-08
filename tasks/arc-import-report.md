# Arc import fidelity report

Measured against the user's real Arc data (read-only copies of `StorableSidebar.json`, `StorableWindows.json`, `User Data/Local State`, plus a symlink to `SidebarItemsFaviconCache`), imported into an in-memory Folio store by a throwaway harness kept outside the repo. The harness and its data copies have been deleted. Only aggregates are listed below.

## Fidelity

| Aspect | Arc (what Arc shows) | Folio before | Folio after |
|---|---|---|---|
| Spaces, in order | 2 | 2, order matches | 2, order matches |
| Space icons (emoji) | 2/2 | 2/2 | 2/2 |
| Space themes | 1/2 (the other has no theme) | 1/2 stored; flat-ish background→tint wash, follows system appearance | 1/2; Arc's flat color, pinned to its light appearance on Mac like Arc |
| Profiles | 2 used by spaces (+1 "Default" with favorites but no spaces) | 3 (hidden Default imported) | 2 |
| Favorites per profile (this Mac) | 6 / 4 | 6 / 4 (+6 under hidden Default) | 6 / 4 |
| Pinned tabs per space | 49 (+1 arc:// style) / 122 | 49 / 122 | 49 / 122 |
| Folders per space, max depth | 10 / 14, depth 3 | 10 / 14, depth 3 | 10 / 14, depth 3 |
| Folders expanded | 0 / 1 | 0 / 1 | 0 / 1 |
| Child order (30 parents) | n/a | 30/30 match | 30/30 match |
| Custom tab titles (`title` ≠ `savedTitle`) | 28 / 67 | 28 / 67 | 28 / 67 |
| Unpinned (Today) tabs | 0 / 0 | 0 / 0 | 0 / 0 |
| Split views / easels / notes | 0 in this data | split views dropped with their tabs | split view → its tabs as siblings in place (synthetic check: order T1,T2,T3,T4; 1 split counted; 1 easel counted as skipped) |
| Favicons | 155 of 177 tab URLs cached (65/72 hosts) | none; fetched from sites later | 155 URLs seeded into Folio's icon cache at import (Mac) |
| Non-http tabs | 1 | skipped, counted | skipped, counted, named in the preview |
| Re-import | n/a | idempotent | idempotent: 0 inserted, 0 updated, 215 unchanged |

## Gaps closed
- **Hidden profile**: favorites of an Arc profile that has no spaces (Arc never shows them) no longer create a Folio profile.
- **Theme rendering** (`SpaceStyle`, both apps): Arc's `background` is now parsed (`single` / `appearanceBased`, `blendedSingleColor` / `blendedGradient` / `basicColor`, `noiseFactor`, `overlay`, `contentOverBackgroundAppearance`, `isVibrant`). Single-color themes render flat in Arc's own blended `background`. Gradients keep each base color's hue, take Arc's blend for that appearance, and run diagonally. Colors keep Arc's extended-sRGB values. Text uses Arc's `title` role instead of `foregroundPrimary` (an accent pink in the user's theme, which gave low contrast). Grain renders as a tiled noise overlay (Mac window backdrop and import preview). All of this was checked by rendering swatches with `ImageRenderer`.
- **Fixed appearance (Mac)**: Arc themes with a `single` background (or `windowAppearance`) keep their light or dark look whatever the system appearance is. The sidebar gets the matching `colorScheme`; Incognito is unaffected.
- **Split views**: their tabs are imported in place as sibling tabs. Positions are now a running index, so flattened children stay in order. The number of split views is counted in `ArcImportSummary.splitViews`.
- **Favicons**: `ArcSidebarImporter.cachedFavicons(for:)` reads `SidebarItemsFaviconCache/<md5(item id)>`, accepting PNG only, under 512 KB. `Favicons.seed(_:for:)` writes the icon into the per-host cache only when the host has no icon yet.
- **Empty custom titles** are ignored, so the page title is used instead.
- **Mac import UI**: if access was granted before, the sheet opens straight into a preview. The preview shows every space as a card in its own theme with its icon, tab count and profile, a one-line summary (spaces · tabs · favorites · folders · profiles), and what stays in Arc. There is one primary button, "Import N Spaces". When the import finishes, the title becomes "Your Arc is here" and each card gets a checkmark, staggered. The cookie option is still off by default, stays on this Mac, and asks for Keychain approval. Password import is still not offered.
- **Onboarding** already opens this same `ArcImportView` sheet, so it gets the new flow without any edit to `OnboardingView.swift`.

## Gaps remaining
- **Space with no Arc theme**: Arc's built-in default look isn't stored in its data, so Folio uses its own indigo fallback.
- **Translucency / vibrancy** (`translucencyStyle`, `isVibrant`): not rendered. Folio's window is opaque, and supporting this needs window-level visual-effect changes outside this task.
- **Fixed appearance on iOS**: not applied. The Duo views (`RootView`, `SpaceHome`) are owned by another agent and use system colors that would clash with a forced palette. They can adopt `SpaceStyle.colorScheme(of:)`.
- **Overlay textures**: `sand`, `denim` and `tweed` all render as the same grain.
- **Live folders** (2 here): imported as a static snapshot of their current contents, with no refresh.
- **Collapsed pinned sections** (`spacesWithCollapsedPinnedSections`, 0 here): Folio has no collapsible pinned section.
- **Easels, notes and arc:// pages**: not imported, but counted and shown in the preview.
- **Unpinned tabs**: none in this data, so that path was checked only structurally. A renamed Today tab takes the page title after it navigates (existing Folio Today-tab behavior).
- **Older imports**: a hidden "Default" profile created by an earlier build isn't removed automatically. Tombstoning only covers profiles in the current import.
- **Favicons**: 22 URLs had no Arc cache entry and fall back to Folio's normal fetch. Seeding happens on the Mac only.

## Files changed
- `Packages/FolioKit/Sources/FolioKit/Import/ArcSidebarImporter.swift`: profile filter, split-view flattening, running positions, `cachedFavicons(for:)`, `arcFolder`, `splitViews`, `importInto(_:snapshot:now:)`.
- `Packages/FolioKit/Sources/FolioKit/Model/WindowTheme.swift`: backdrop parsing, `fixedAppearance`, public `RGBA.init`.
- `Apps/Shared/Theme/WindowTheme+SwiftUI.swift`: `SpaceStyle` rendering, `colorScheme(of:)`, `grain`, `GrainOverlay`. The API stays source-compatible (`background`, `tint`, `foreground`, `gradient: LinearGradient`).
- `Apps/macOS/Import/ArcImportView.swift`: preview, import and completion flow.
- `Apps/macOS/Views/Sidebar.swift`: one `.environment(\.colorScheme, …)` modifier.
- `Apps/macOS/Views/BrowserWindow.swift`: one grain-overlay line in the window backdrop.
- `Apps/Browser/Favicons.swift`: additive `seed(_:for:)`. The favicons agent was told.

## Build results
- `swift build` (Packages/FolioKit): succeeded. The only warnings are old ones in `Library.swift`.
- `xcodebuild … -scheme Folio-macOS … -derivedDataPath build/agent-arc build`: **BUILD SUCCEEDED**.
- `xcodebuild … -scheme Folio-iOS -destination 'id=4807AAA7-…' … -derivedDataPath build/agent-arc-ios build`: **BUILD SUCCEEDED**.
- The app was not launched against the real library. The UI flow was verified by building only, not by running it.

## Round 2 fixes

Fixes for `tasks/review-round2.md` M3, m7, m8, all in `ArcSidebarImporter.swift`.

- **M3 (resurrected/reverted rows)**: `ArcMergeable` now exposes `deletedAt`; `merge`'s generic `upsert` skips (and counts as `summary.removed`) any row whose existing copy is tombstoned, instead of reviving it with Arc's data and `modifiedAt = now`. Re-import of an unchanged library is still idempotent (0 inserted/updated, N unchanged) since the guard only fires on `deletedAt != nil`.
- **m7 (orphaned Folio-made rows)**: before tombstoning `staleItems`, `merge` now finds every live child whose `parentID` is about to be tombstoned (a Folio-made row never carries the `arc-` prefix, so it's never itself in the stale set) and reparents it: to the live `unpinned` container of its `spaceID` when it has one, otherwise to the live `favorites` container of its `profileID`. Lookups are cached per space/profile. If no live container is found (e.g. the whole space was removed in Arc), the row is left in place rather than guessing a destination — same as before, not a regression.
- **m8 (cross-Mac ping-pong + profile id collision)**:
  - `parse()` now collects `ArcSnapshot.foreignFavoritesIDs`: the id plus every descendant id (via a new `descendantIDs(of:byID:)` helper) of each favorites (`topApps`) candidate that lost to this Mac's own and belongs to a different machine. `merge`'s stale-item query excludes these, so importing on Mac A can no longer tombstone Mac B's still-live favorites just because Mac A's own parse didn't walk them this run.
  - `profileID(directory:)` gained an optional `machineID` parameter; a new `resolvedProfileID(_:)` closure in `parse()` passes a machine id only for directories outside `localProfileDirectories` (built from `spaceProfiles` and favorites-candidate machine ids per directory). This Mac's own profiles keep their existing plain ids (`arc-profile-profile-1`), so an existing import is never orphaned; a same-named directory on another Mac now gets a distinct, machine-suffixed id instead of colliding.
- No test harness was available to rerun: `arc-import-report.md`'s original fidelity pass used a throwaway harness and real-data copies that were deleted after that run (per the report above), so the only verification here is the Xcode build and reading the merge logic against the three findings' evidence.

### Build
`xcodebuild -project Folio.xcodeproj -scheme Folio-macOS -derivedDataPath build/agent-arc -allowProvisioningUpdates build` → **BUILD SUCCEEDED**, no warnings in `ArcSidebarImporter.swift`.
