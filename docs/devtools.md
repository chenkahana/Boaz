# Developer tools (Mac)

The Develop menu holds browser-level tools for building and testing sites. Web Inspector itself is WebKit's. The
state lives in [`Apps/macOS/Model/DevTools.swift`](../Apps/macOS/Model/DevTools.swift) and the menu, bar, console
and sheets in [`Apps/macOS/Views/DevToolsViews.swift`](../Apps/macOS/Views/DevToolsViews.swift).

Every setting below applies to the active tab and lasts as long as that tab's page does: closing the tab, or Boaz
unloading an idle page, drops it. Nothing is saved or synced. Incognito windows have the full menu.

| Tool | Shortcut |
| --- | --- |
| Responsive Design Mode | ⌥⌘R |
| Show JavaScript Console | ⌥⌘C |
| View Page Source | ⌥⌘U |
| Empty Caches | ⌥⌘E |

The shortcuts are rebindable like the others (`KeyBindings.swift`).

## Tools

- **Web Inspector.** Every page is inspectable in every build: right-click › Inspect Element. Quick Window pages too,
  and iPhone pages, which Safari's Develop menu on a Mac can inspect. WebKit has no public call that opens the
  inspector, so the menu only points to the context menu.
- **Responsive Design Mode.** The page takes a device's viewport, centered on a neutral backdrop, with a bar above
  it: a device menu (iPhone SE, iPhone 17, iPhone 17 Pro Max, iPad mini, iPad Pro 13", Laptop, Desktop, Fill
  Window), width and height fields, and Rotate. A viewport bigger than the pane is scaled down to fit and the bar
  shows the zoom. Phone and tablet devices also switch to Safari's iPhone or iPad user agent and reload, unless a user
  agent was picked from the menu. Leaving the mode restores the user agent and the full size.
- **User Agent.** Default, Safari (iPhone, iPad, Mac), Chrome (Mac, Windows, Android), Firefox (Mac), Edge (Windows),
  or Other… for any string. Picking one reloads the page. Picking Default keeps WebKit's own agent even in
  Responsive Design Mode on a phone or tablet.
- **Emulate Media.** Screen or Print (CSS `@media print`), and Light, Dark or System appearance for
  `prefers-color-scheme`. The appearance is the WebView's own, so the rest of the window keeps its theme.
- **Vision Simulator.** Protanopia, Deuteranopia, Tritanopia and Achromatopsia (Machado et al. 2009 color matrices
  in an SVG `feColorMatrix`), Blurred Vision and Low Contrast (CSS filters). Boaz puts the filter on the page's root
  element from its own script world, and again after every navigation. None removes it.
- **Disable JavaScript.** The page's own scripts stop running from the next load; toggling it reloads.
- **JavaScript Console.** A panel under the page. It runs what you type in the page's script world: an expression
  shows its value (strings quoted, objects and arrays as JSON), and anything that doesn't parse as one (`let`,
  `if`, `return`) runs as a function body. The input is only parsed to decide, so it always runs once. ↑ and ↓ go through what was run in the tab. While the panel is open it also shows the
  page's `console.log`, `info`, `warn`, `error` and `debug` calls and uncaught errors, by wrapping `console` in each
  document; closing the panel unwraps it. Messages from before the panel opened, and from the first moments of each
  new page before the next poll, aren't shown. While the hook is in, Web Inspector's console attributes those calls
  to Boaz's wrapper instead of the line in the page that made them; close the panel to get the page's own source
  links back.
- **View Page Source.** The live document (`document.documentElement.outerHTML`, so after scripts ran) in a
  monospaced, selectable sheet with the find bar open, and a Copy button.
- **Show Storage…** The site's cookies (its own and its parent domains': name, value, domain, path, expiry and
  flags) and its local and session storage. Double-click or the context menu copies a value; Delete removes the
  selected rows; Clear All empties the section.
- **Capture Visible Area / Capture Full Page.** A PNG in `~/Downloads`, named `<host> <yyyy-MM-dd HH.mm.ss.SSS>.png`, also put on
  the pasteboard.
- **Export as PDF…** The whole page as one PDF, saved where you choose.
- **Empty Caches.** Clears the profile's disk, memory and fetch caches and reloads from the server. Cookies and site
  data stay; View › Reload Ignoring Cache and Cookies (⇧⌘R) is the one that forgets the site.
