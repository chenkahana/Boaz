# Must-haves

These describe what Boaz is. They are not up for trade: a change that breaks one is a regression, even when it fixes
something else. Each one is Chen's call, with the date he made it.

## Rules for every change, automated or not

1. Read this page before changing how Boaz behaves.
2. A fix that breaks a must-have is not a fix. If the only fix you can find breaks one, stop. Write up the options
   and wait for Chen. Don't ship it, and don't ship it "for now".
3. A workaround that changes what the user sees or does needs Chen's yes first. That covers extra windows, a
   different engine, hidden or disabled features, moved controls and new prompts.
4. Before calling a fix done, check in the real app that the must-haves it touches still hold, not only that the bug
   is gone.
5. Only Chen adds, changes or removes a must-have.

## Browser (Mac DMG)

1. **Boaz is Chromium.** Every page the user opens runs in Chromium. WebKit exists only as an invisible fallback for
   protected video that Chromium can't play. It never appears in the UI, settings, menus or docs. *(2026-11-14)*
2. **One window holds every profile, as in Arc.** A window shows the spaces of every profile. Switching spaces stays
   in that window: it never opens, swaps or hides a window. *(2026-11-17)*
3. **Each space runs in its profile's own Chromium session.** That means its own cookies, sign-ins, history and
   extensions, with `chrome://` pages working. *(2026-11-17)*
4. **Extensions behave as in Chrome.** `chrome://extensions`, Chrome Web Store installs, toolbar pins, popups,
   keyboard shortcuts and side panels all work, with no Boaz-only extension behavior. *(2026-11-15)*

## Arc's way of working

5. **Spaces, Favorites, Pinned, Today and folders in the sidebar, as in Arc.** *(2026-11-15)*
6. **Pull Requests live folders read github.com with the user's own sign-in, as Arc does.** There's no GitHub app,
   OAuth grant or token. *(2026-11-16)*

## iPhone app

7. **The page comes first.** Boaz opens on the last page you had open. On a standard iPhone, the bar across the
   bottom holds the tab fan, **+** and **…**, and it takes its own height: page content never sits behind it.
   *(2026-11-14)*
8. **No Spaces on iPhone.** Spaces are a Mac idea; the iPhone shows your tabs without them. *(2026-11-14)*
9. **iPhone Duo in every posture.** Folded, open, book and laptop each have their own layout, and the page never
   reloads as the hinge moves.
10. **WebKit, as App Store rules require.** The iPhone and Mac App Store apps use WebKit, while the Mac DMG is
    Chromium.
11. **iPhone and Mac stay in sync.** Pins, folders, favorites and Today sync through the user's private iCloud
    database, and the iPhone can open the Mac's tabs. History and Incognito tabs never leave the device.

## Privacy and data

12. **AI runs only on Apple's on-device model.** Nothing is sent to a server.
13. **The user's library is never lost.** Spaces, tabs, folders, history, passwords and signed-in sites survive every
    update, migration and fix, on the Mac and the iPhone.

## Shipping

14. **Every app change merged to master ships** as a signed, notarized release with a CHANGELOG entry. *(2026-11-16)*
