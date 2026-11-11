# Mac sidebar design rules

The Mac sidebar and its tab list follow these rules. The tokens live in `SidebarStyle`
([`Sidebar.swift`](../Apps/macOS/Views/Sidebar.swift)); change them there, not per view.

## Type

- The system font (SF Pro), never the rounded design.
- Rows 14 pt regular; the selected row 14 pt medium. Settings › General › Sidebar text size sets rows to 13, 14 or
  16 pt; headers and the title keep their offset (-3 pt, +1 pt).
- Section headers 11 pt semibold. The space title 15 pt semibold.

## Spacing

- A 4 pt grid. Rows are 32 pt tall with no gap between them, 8 pt side padding, and 8 pt between sections.

## Fills

- Selection is one flat fill: the label color at 12% (24% with Increase Contrast). Hover is half that, 6%.
- No glow, shadow or border on a selected row or tile. A drop target may outline itself in the space's tint.
- Favorites are flat tiles at the hover fill; only hovering lifts one (1 pt and a soft shadow).

## Contrast

- Text and icons read at 4.5:1 (WCAG AA) or better, in Light and Dark, on every space theme, including over the hover
  and selection fills. Primary text is `SpaceStyle.foreground`; dimmer text and icons use the secondary foreground
  style (`SpaceStyle.secondaryOnFills`), never a lowered opacity.
- Disabled controls are the only exception.

## Backdrop

- The window wears the space's theme (Customize Space) and nothing else: pages never tint the sidebar.
- Grain and the light streak from the top corner are theme options (Customize Space), off by default.

## Motion

- One curve, `SidebarStyle.motion` (smooth, 0.2 s), for hover, selection and list changes.
- With Reduce Motion, nothing moves or scales: hover lifts stay put and the space switch cross-fades.
