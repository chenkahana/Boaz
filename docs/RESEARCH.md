# Research: what attracts people to Arc

Grounded findings from public reviews, Arc's own documentation, and user reactions to the shutdown. Every claim links to its source. Compiled 2026-10-22.

## 1. The situation

- Arc is being sunset on **December 22, 2026**. macOS and Windows builds stop working, sign-in and sync shut off. New accounts were disabled on October 22, 2026; mobile AI features turn off November 23, 2026. The Browser Company's stated reason: keeping a browser secure "in the age of AI" got too hard, and the security team is moving to Dia. Source: <https://resources.arc.net/hc/en-us/articles/44412972248471-Arc-Sunset-Key-Dates-and-What-to-Expect>
- News coverage: <https://www.theverge.com/tech/1016832/arc-browser-shutting-down> (2026-10-22)
- The maintenance burden that killed Arc is a design constraint for us: any engine strategy must inherit security updates from an upstream that ships them (see `docs/ARCHITECTURE.md`).

## 2. What people actually loved (ranked by users, corroborated by reviews)

A long-time user's ranked list after the shutdown (<https://www.reddit.com/r/ArcBrowser/comments/1no5t2b/i_miss_arc_and_what_it_couldve_become/>), matching what The Verge (<https://www.theverge.com/23462235/arc-web-browser-review>) and Zapier (<https://zapier.com/blog/arc-browser-review/>) found:

1. **Tab folders** - nested folders in the sidebar; the top organizational win.
2. **Renaming tabs** - give any tab your own name; "magical", kills unreadable page titles.
3. **Picture-in-picture that works** - PiP auto-opens when you switch away from a video call tab (Google Meet), auto-returns when you come back. Feels like the browser "is paying attention".
4. **The sidebar** - vertical tabs as the primary model, not an add-on. Merges tabs and bookmarks into one list; kills duplicate-tab sprawl ("I kept opening Gmail five times").
5. **Minimalist, calm design** - no clutter, no feeling of missing something.
6. **Auto-closing inactive tabs** - "Today tabs" archive after 12h (configurable to 24h/7d/30d); archived tabs land in a searchable list. Bold default, divisive, but a must-have for converts.
7. **Shortcuts everywhere + command bar** - `Cmd/Ctrl+T` opens a Spotlight-style bar that searches open tabs first, then the web; `Tab` turns it into a command runner for every action. Remappable shortcuts set a benchmark people now miss in every other app.
8. **Spaces / profiles in one window** - separate contexts (work, personal, a project) with their own pins, folders, theme color, and accounts, switched by swipe or shortcut, not by window.

Also cited repeatedly in reviews:

- **Peek**: clicking a link from a pinned tab opens a floating preview you can read and dismiss, instead of a new tab that lingers. Fewer tabs get opened in the first place. (<https://zapier.com/blog/arc-browser-review/>)
- **Split view**: up to 4 tabs tiled in one window; the tiled arrangement itself becomes a saveable, renamable tab. (<https://zapier.com/blog/arc-browser-review/>)
- **Air Traffic Control**: rules that route links to the right space automatically (e.g. all sheets.google.com links open in Work). Source: <https://resources.arc.net/hc/en-us/articles/22932014625431-Air-Traffic-Control-Automate-Your-Link-Routing>
- **Favorites with hover previews**: pinned apps act like a dock; hovering supported sites (calendar) shows unread state. (<https://zapier.com/blog/arc-browser-review/>)
- **Boosts**: no-code per-site restyling (custom CSS/colors). Power feature, smaller audience.
- **Always-present media controls** and a mini-player; recent downloads hover in the corner, draggable onto pages.

## 3. The design language

Distilled from <https://open-design.ai/plugins/design-system-arc/> plus reviews:

- **Chrome dissolves into the page.** The browser frame is scenery, not a container: translucency everywhere, toolbar tinted by the page or the space's theme.
- **Frosted glass + one saturated gradient.** The window's mood comes from a user-picked theme gradient (peach-to-coral, violet-to-fuchsia, mint-to-cyan). Per-space color = per-space emotional temperature.
- **Squircle-soft geometry.** 12-16px radii on cards, 8px on tabs, full pills for tags. Borders are rare; panes are separated by translucent washes (`rgba(255,255,255,0.5)` over the gradient).
- **Typography**: Inter for UI, tight tracking, generous line height.
- **Sidebar-first layout.** Everything lives on the left; the address bar shrinks to a corner and expands on demand. The web page gets the screen.
- **User-driven theming.** The color picker is a brand surface; themes are chosen, not fixed.

## 4. Known weaknesses (our openings to surpass Arc)

From the same reviews:

- Duplicate tabs still happen; Arc doesn't warn that a page is already open elsewhere. (Verge)
- Heavy pinning clutters the sidebar fast; no good home for occasional bookmarks or bookmarklets. (Verge)
- Command bar search can lag a beat. (Zapier)
- No way to open a truly blank window/space; new windows come pre-populated. (Zapier)
- Auto-archive maxes at 30 days and has no per-site exceptions in the UI.
- Sync was account-bound to The Browser Company's servers - and dies with them. Owning sync is an existential requirement for us, not a feature.
- Arc never shipped its ideas to Linux; Windows lagged macOS.

## 5. The alternatives landscape (what we're up against)

Source: <https://browser.horse/articles/browsers/arc-browser-alternative> plus project pages.

| Browser | Base | What it carries | Gap we can exploit |
| --- | --- | --- | --- |
| Zen (<https://zen-browser.app/>, <https://github.com/zen-browser/desktop>, MPL-2.0, ~45k stars) | Firefox | Vertical tabs, workspaces, glance, split view, compact mode | Firefox engine (site/extension compat, Meet PiP complaints); "exactly like Arc" but not surpassing it |
| Dia | Chromium | TBC's design taste, profiles | AI-centric, dropped folders/renaming/auto-archive; not Arc's interface |
| Vivaldi | Chromium | Everything, configurable | Cluttered; "Arc on steroids, lost control" |
| Edge | Chromium | Vertical tabs, workspaces, split screen | Microsoft account coupling; no design soul |
| Horse | Proprietary | Persistent sidebar with parent/branch trails | Tab-less model is a different bet |

**Opening:** nobody is shipping Arc's exact ergonomics (folders + rename + auto-PiP + ATC + calm design) on a maintained engine, and nobody is pushing past Arc. That is the product.

## 6. Implications for the plan

1. Feature priority follows the user ranking in section 2: folders, rename, auto-PiP, sidebar, calm design, lifecycle rules, command bar, spaces.
2. Engine strategy must guarantee security updates with a tiny team (the exact thing that killed Arc). See `docs/ARCHITECTURE.md`.
3. Sync must be self-hostable/E2E-encrypted so no company can sunset this browser out from under its users.
4. Design must feel natural and warm (gradient + glass + softness), not like developer tooling (Vivaldi's trap) and not like a chatbot (Dia's trap).
