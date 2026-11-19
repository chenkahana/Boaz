# Copy rules

How Boaz's words read, on the Mac and the iPhone. English only. Every target has a `Localizable.xcstrings` that Xcode
fills from the code as it builds: open it to review every string in one place against these rules.

## Capitalization

| Element | Rule | Example |
|---|---|---|
| Buttons, menu items, window and sheet titles, tab names, tooltips | Title case | "Reopen Closed Tab", "Previous Match" |
| Settings labels and section headers | Title case on both platforms | "Search Engine", "Block Ads and Trackers" |
| Empty-state titles | Title case, "No …" | "No Archived Tabs", "No History" |
| Descriptions, footers, alert messages, toasts, placeholders | Sentence case; a period only after a full sentence | "Closed and inactive tabs appear here." |
| Error titles | One title per kind | "Can't Open This Page", "You're Offline", "This Page Stopped Responding" |

- "…" (one character, U+2026) on items that open a further step (a sheet, a dialog, a picker); never on items that
  act at once; never "...".
- Errors say what happened, then what to do, in plain words. Never show `error.localizedDescription`; log it.

## Numbers and plurals

- Plurals through automatic grammar agreement, never `count == 1 ? "" : "s"`: `Text("^[\(count) tab](inflect: true)")`,
  or `String(inflecting: "Archived ^[\(count) tab](inflect: true)")` where the copy isn't a `Text`.
- Percentages through `FormatStyle` (`.percent`), never `"\(Int(value * 100))%"`. Sizes through
  `ByteCountFormatStyle`, lists through `.list(type: .and)`.
- CI fails on the two hand-built patterns above (`Tools/copy-lint.sh`).

## Glossary

| Term | Means | Not |
|---|---|---|
| **Archive** | Where closed and inactive tabs go; "Archive Tab" | "Archived Tabs" as a separate name, "Clear" for archiving Today |
| **Today** | Unpinned tabs of the current space (Mac) | "Today Tab" |
| **Pinned** | Tabs kept in a space | "Saved" |
| **Favorites** | The tiles at the top of the sidebar | "Bookmarks" |
| **Space** | A Mac-only sidebar context, never on the iPhone | — |
| **Incognito** | Private browsing, both platforms | "Private" |
| **Live Folder** | A folder filled from GitHub | — |
| **Library** | The iPhone sheet (Archive and History); the Mac panel | — |
| **Page Menu** | The **…** menu on the iPhone, and its spoken name | "Page Settings" |
