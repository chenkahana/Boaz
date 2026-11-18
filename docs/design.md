# Mac sidebar design rules

The Mac sidebar and its tab list follow these rules. The tokens live in `SidebarStyle`
([`Sidebar.swift`](../Apps/macOS/Views/Sidebar.swift)); change them there, not per view.

## Type

- The system font (SF Pro), never the rounded design.
- Rows 15 pt regular; the selected row 15 pt medium. Settings › General › Sidebar text size sets rows to 14, 15 or
  17 pt; headers and the title keep their offset (-3 pt, +1 pt).
- Section headers 12 pt semibold. The space title 16 pt semibold.
- Every other chrome size comes from the same base through `ChromeType` (`Sidebar.swift`): sidebar glyphs base − 3
  semibold, the command bar field base + 4, its rows base − 1 and captions base − 4, Library panel labels
  base − 4 but never under 11 pt. The iPhone uses text styles only, never fixed sizes for text.

## Spacing

- Rows are 34 pt tall with 2 pt between them, 8 pt side padding, and 8 pt between sections. The line above Today
  has 8 pt above and below it; the space buttons at the bottom sit 10 pt apart.
- Elsewhere, spacing and corners come from `Spacing` (2, 4, 6, 8, 12, 16, 20, 24, 32) and `Radius` (Mac: icon 6, row
  8, tile 10, card 12, panel 16; iPhone: 8, 12, 16, 20, 28) in `Apps/Shared/Theme/Layout.swift`. A container inset in
  another takes `Radius.concentric(in:inset:)`.

## Fills

- Selection is one flat fill: the label color at 12% (24% with Increase Contrast). Hover is half that, 6%.
- No glow, shadow or border on a selected row or tile. A drop target may outline itself in the space's tint.
- Favorites are flat tiles in their icon's main color at 24% (42% selected), or the hover fill (the selection fill)
  for black, white and gray icons, and until an icon loads; only hovering lifts one (1 pt and a soft shadow).

## Contrast

- Text and icons read at 4.5:1 (WCAG AA) or better, in Light and Dark, on every space theme, including over the hover
  and selection fills. Primary text is `SpaceStyle.foreground`; dimmer text and icons use the secondary foreground
  style (`SpaceStyle.secondaryOnFills`), never a lowered opacity.
- Disabled controls are the only exception.

## Backdrop

- The window wears the space's theme (Customize Space) and nothing else: pages never tint the sidebar.
- Grain and the light streak from the top corner are theme options (Customize Space), off by default.

## Motion

- Curves come from the tokens in `Apps/Shared/Theme/Motion.swift`, never from literals: `quick` for hover, press and
  selection (`SidebarStyle.motion`, smooth 0.2 s on the Mac), `standard` for panels and list changes, `emphasized`
  for presenting a hero, and `gesture(velocity:)` for anything a finger lets go of, carrying its speed.
- With Reduce Motion, nothing moves or scales: hover lifts stay put and the space switch cross-fades. The tokens
  read the setting themselves (`withMotion(_:)` in models, `.motion(_:value:)` in views).

## Haptics

- One haptic per meaningful moment (a commit, a threshold crossed, a snap), never on scrolling, hover or a plain tap.
  Call sites name the moment from `Apps/Shared/Theme/Haptics.swift`: `.sensoryFeedback(Haptics.tabChanged.feedback,
  trigger:)` on the iPhone, `Haptics.snap.play()` on the Mac trackpad.
