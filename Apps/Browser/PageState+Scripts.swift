import Foundation

extension PageState {
    /// Scroll events don't bubble, but the document sees every one while capturing: the elements the user scrolled are
    /// remembered as they go, so reading never walks the DOM. A selector stops at the nearest element with an id.
    static func trackingScript(report: String) -> String {
        """
        (() => {
            if (window.__boazPageState) return;
            const seen = new WeakSet();
            let scrollers = [], settle = 0, restoring = false;
            const atEnd = (offset, max) => max > 4 && offset >= max - 4;
            const selector = element => {
                const parts = [];
                for (let e = element; e && e !== document.documentElement; e = e.parentElement) {
                    if (e.id) { parts.unshift('#' + CSS.escape(e.id)); return parts.join(' > '); }
                    let n = 1;
                    for (let s = e.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === e.localName) n++;
                    parts.unshift(e.localName + ':nth-of-type(' + n + ')');
                }
                return [':root', ...parts].join(' > ');
            };
            const read = () => {
                if (restoring) return null;
                const root = document.scrollingElement || document.documentElement;
                const live = scrollers.map(r => r.deref())
                    .filter(e => e && e.isConnected && (e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth))
                    .sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)
                    .slice(0, 8);
                return JSON.stringify({
                    url: location.href,
                    window: { top: scrollY, left: scrollX, atBottom: atEnd(scrollY, root.scrollHeight - innerHeight) },
                    scrollers: live.map(e => ({ path: selector(e), top: e.scrollTop, left: e.scrollLeft,
                                                atBottom: atEnd(e.scrollTop, e.scrollHeight - e.clientHeight) })),
                });
            };
            // Off screen a page is laid out 1024 wide, which moves it: a chat at its end comes back halfway up, or at the
            // top. So readings are taken only at the width the page shows at (the one it had as the reader last touched
            // it, or at the last reading), and it goes back to one once it is that wide again. Within two points: the
            // browser gives the rail a point of clearance as it appears.
            const near = width => Math.abs(innerWidth - width) <= 2;
            let shown = null, kept = null, latest = null, before = null, latestAt = 0;
            ['wheel', 'touchstart', 'keydown', 'pointerdown']
                .forEach(type => addEventListener(type, () => { shown = innerWidth; }, { capture: true, passive: true }));
            const onScreen = () => document.visibilityState === 'visible' && (shown === null || near(shown));
            const keep = (state, width) => {
                kept = { state, width };
                shown = width;
                latest = before = null;
                \(report)
            };
            document.addEventListener('scroll', event => {
                const target = event.target;
                if (target instanceof Element && !seen.has(target)) {
                    seen.add(target);
                    scrollers.push(new WeakRef(target));
                    if (scrollers.length > 32) scrollers = scrollers.filter(r => r.deref()?.isConnected).slice(-32);
                }
                if (!onScreen()) return;
                // Read as it goes too, for a page that leaves the screen before its scrolling settles.
                if (Date.now() - latestAt > 100) {
                    latestAt = Date.now();
                    before = latest;
                    latest = { state: read(), width: innerWidth };
                }
                clearTimeout(settle);
                settle = setTimeout(() => {
                    settle = 0;
                    const state = onScreen() && read();
                    if (state) keep(state, innerWidth);
                }, 400);
            }, { capture: true, passive: true });
            // Tries again every 150 ms while the page is still rendering what it scrolled (the element is missing, or
            // too short to get there), and once more to see it stayed; at the end, until there is content and it has
            // stopped growing for 450 ms.
            const restore = place => new Promise(resolve => {
                const deadline = Date.now() + 8000, heights = new Map(), interactions = ['wheel', 'touchstart', 'keydown', 'pointerdown'];
                const { top, left, atBottom } = place.window;
                const offsets = (top || left || atBottom ? [place.window] : []).concat(place.scrollers);
                let timer = 0, held = 0;
                const finish = () => {
                    clearTimeout(timer);
                    interactions.forEach(type => removeEventListener(type, finish, true));
                    restoring = false;
                    resolve(null);
                };
                const step = () => {
                    let done = true;
                    for (const offset of offsets) {
                        let element = null;
                        if (offset.path) {
                            try { element = document.querySelector(offset.path); } catch {}
                            if (!element) { done = false; continue; }
                        }
                        const root = document.scrollingElement || document.documentElement;
                        const height = (element || root).scrollHeight;
                        const max = height - (element ? element.clientHeight : innerHeight);
                        const y = offset.atBottom ? max : offset.top;
                        if (element) { element.scrollTop = y; element.scrollLeft = offset.left; } else { scrollTo(offset.left, y); }
                        const now = element ? element.scrollTop : scrollY;
                        if (offset.atBottom) {
                            const last = heights.get(offset.path);
                            const steady = last && last.height === height ? last.steady + 1 : 0;
                            heights.set(offset.path, { height, steady });
                            if (max <= 4 || steady < 3) done = false;
                        } else if (Math.abs(now - y) > 2) {
                            done = false;
                        }
                    }
                    held = done ? held + 1 : 0;
                    if (held > 1 || Date.now() > deadline) finish(); else timer = setTimeout(step, 150);
                };
                interactions.forEach(type => addEventListener(type, finish, { capture: true, passive: true }));
                restoring = true;
                step();
            });
            // Back on screen, a page still at the address it was last read at goes back there, once it is laid out as
            // wide as it was read at (within a second). Once, however many ask.
            let returning = null;
            const returnToPlace = () => {
                if (returning) return returning;
                const place = kept && !restoring && JSON.parse(kept.state);
                if (!place || place.url !== location.href) return null;
                const deadline = Date.now() + 1000;
                return returning = new Promise(resolve => {
                    const wait = () => {
                        if (document.visibilityState === 'visible' && near(kept.width)) resolve(restore(place));
                        else if (Date.now() > deadline) resolve(null);
                        else setTimeout(wait, 50);
                    };
                    wait();
                }).then(() => { returning = null; return null; });
            };
            // Leaving the screen, a reading still settling is kept as it was last read, unless that was as the page left:
            // WebKit lays it out at its off-screen size first, and the scroll that moves comes in at the old one.
            document.addEventListener('visibilitychange', () => {
                if (document.visibilityState === 'visible') { returnToPlace(); return; }
                if (!settle) return;
                clearTimeout(settle);
                settle = 0;
                const reading = Date.now() - latestAt < 100 ? before : latest;
                if (reading?.state) keep(reading.state, reading.width);
            });
            window.__boazPageState = { read, restore, returnToPlace };
        })();
        """
    }
}
