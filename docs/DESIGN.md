# Design language

How Canopy looks and feels. Inspired by the qualities users describe in Arc (calm, warm, alive, personal) expressed through original tokens and assets. Research basis: `docs/RESEARCH.md` section 3.

## Principles

1. **The page is the protagonist.** Chrome recedes: translucency, no visible borders, the web page fills the window. UI appears on intent (hover, shortcut, drag) and rests quietly otherwise.
2. **Warm, not sterile.** Every space has an emotional temperature set by its gradient. The browser should feel like a room you decorated, not a dashboard.
3. **Soft geometry.** Squircle radii everywhere; nothing sharp.
4. **One motion language.** Fast (120-200ms), spring-eased, always interruptible. Nothing bounces for attention; state changes glide.
5. **Honest focus.** Hiding the sidebar is one gesture and gives a truly blank canvas (Arc never allowed a blank window; we do).

## Tokens

All implementation values come from this table. Names are canonical; values are the default theme ("Dawn").

### Color

| Token | Value | Use |
| --- | --- | --- |
| `glass.bg` | `rgba(255,255,255,0.5)` | pane separation washes over gradient |
| `glass.bg.dark` | `rgba(20,20,24,0.55)` | dark mode wash |
| `ink.primary` | `#1C1C1E` / `#F2F2F5` (dark) | text, icons |
| `ink.secondary` | `#6E6E73` / `#A0A0A8` | hints, timestamps |
| `accent` | derived from active space gradient, stop 2 | active tab, focus rings, links in chrome |

### Space gradients (theming engine)

A gradient is two stops plus an angle. Ship six presets; users compose their own with a two-stop picker.

| Preset | Stops | Mood |
| --- | --- | --- |
| Dawn | `#FFB199 -> #FF7E5F` | peach-coral, warm default |
| Iris | `#8E7CFF -> #E45CC4` | violet-fuchsia |
| Meadow | `#7BE0C3 -> #4FB3D9` | mint-cyan |
| Dusk | `#3A3E5C -> #B06AB3` | evening |
| Paper | `#F5F1E8 -> #E8DFC8` | near-neutral light |
| Slate | `#23252B -> #3E4652` | near-neutral dark |

Gradient fills the window behind frosted glass at 60-80% blur strength; the page area renders opaque.

### Shape

| Token | Value |
| --- | --- |
| `radius.card` | 14px |
| `radius.tab` | 8px |
| `radius.pill` | 9999px |
| `radius.window` | platform default |
| `border` | none; use `glass.bg` washes for separation |

### Typography

| Token | Value |
| --- | --- |
| `font.ui` | Inter, system-ui fallback |
| `font.size.tab` | 13px, weight 500 |
| `font.size.body` | 13px |
| `font.size.title` | 15px, weight 600 |
| `tracking` | -0.01em on UI text |
| `line.height` | 1.45 |

### Motion

| Token | Value |
| --- | --- |
| `motion.fast` | 120ms |
| `motion.base` | 180ms |
| `motion.slow` | 260ms |
| `motion.ease` | spring (damping 0.85, no overshoot) or `cubic-bezier(0.2, 0.9, 0.25, 1)` |
| reduced motion | honor OS setting: instant state changes, no parallax |

## Anatomy

```
+------------------------------------------------------------------+
| sidebar (240-320px, collapsible) |  page (opaque, radius.card    |
|  [favorites row: icon grid]      |  when split, gap 8px)         |
|  [pinned tabs + folders]         |                                |
|  ------------------------------- |                                |
|  [today tabs, auto-archiving]    |                                |
|  [shelf toggle] [command hint]   |                                |
+------------------------------------------------------------------+
```

- **Address "bar"** is a compact pill in the top-left of the sidebar showing origin only; expands to full URL on focus/`Cmd+L`. 
- **Sidebar collapse**: `Cmd+S` hides it fully (blank canvas mode, Arc gap fixed); hovering the left edge at any time reveals it temporarily over the page with a `glass.bg` scrim.
- **New window** opens blank by default (one quiet gradient, one centered command bar). Populated windows are opt-in.
- **Active tab** in sidebar: `accent` 12%-alpha wash + 2px left indicator; renamed tabs show the custom name in `ink.primary`, original title as tooltip.

## Theming engine

- Per-space theme: preset or custom gradient; sidebar tint and accent derive automatically (contrast-checked to WCAG AA for `ink.*` on washes).
- Light/dark: follows OS, overridable per space.
- Everything animates between themes with `motion.base` cross-fade.

## Sound and haptics

None in v1. The browser is quiet.

## What we deliberately avoid

- Dense power-user chrome (Vivaldi's trap): no panels stacked on panels; one sidebar, three sections.
- Chat-first layout (Dia's trap): no persistent assistant rail.
- Any Arc asset, icon, illustration, or marketing voice. Original codename, original marks.
