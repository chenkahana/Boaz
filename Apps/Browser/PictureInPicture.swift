import WebKit

/// Picture in Picture for one page: which of its frames has a video worth floating, floating it on request or when the
/// user leaves it playing, bringing back what Boaz floated when they return, and hearing when the user brings it back
/// from its window themselves.
///
/// A script in every frame, in a world of its own the page can't see or call, picks each frame's video: one that's
/// playing, big enough to watch (scrolled away counts; hidden doesn't), not a muted backdrop loop, the one the user
/// last played first, then sound over silence, then size. The page asks the best frame to float it, with a direct
/// call into that frame, which WebKit treats as the user's own action, so a video in another site's frame (an
/// embedded player) floats too. Boaz floats a site's video on its own only where the site allows it
/// (`disablePictureInPicture`); asked by the user, it floats it anyway.
@MainActor
final class PictureInPicture: NSObject, WKScriptMessageHandler {
    /// Whether Boaz floats a playing video when the user leaves it (another tab or space, a hidden window).
    static let whenLeavingKey = "pictureInPictureWhenLeaving"
    static var floatsWhenLeaving: Bool { UserDefaults.standard.object(forKey: whenLeavingKey) as? Bool ?? true }

    /// Whether this build can float video at all: always on iPhone; on the Mac, only the DMG build (`enable(in:)`).
    static var isSupported: Bool {
        #if os(iOS) || DIRECT_DISTRIBUTION
        true
        #else
        false
        #endif
    }

    private static let world = WKContentWorld.world(name: "BoazPictureInPicture")
    private static let handlerName = "boazPictureInPicture"
    private static let controllers = NSHashTable<PictureInPicture>.weakObjects()

    private struct Frame {
        let info: WKFrameInfo
        /// The frame's best playing video and best video of any kind, scored; nil where it has none.
        var playing: Double?
        var any: Double?
        var floating: Bool
    }

    private weak var page: WebPage?
    private var frames: [String: Frame] = [:]
    /// The frame whose video Boaz floated when the user left, so it comes back when they return; one the user floated
    /// stays. Kept apart from `frames`, whose state catches up a moment later.
    private var floatedOnLeaving: WKFrameInfo?
    /// The user is away from the page: set on leaving, cleared on return, so a float that lands after they came back
    /// (they left and returned within the half second floating takes) goes right back.
    private var isAway = false
    /// A float on its way, on any page: until it lands, another page's state can't show it yet.
    private static var floatInFlight = false
    /// The user brought the video back to its page from its window.
    var onRestore: (() -> Void)?

    var isFloating: Bool { frames.values.contains(where: \.floating) }
    var hasPlayingVideo: Bool { frames.values.contains { $0.playing != nil } }
    var hasVideo: Bool { frames.values.contains { $0.any != nil } }

    /// Adds the script to a new page's configuration. `attach(_:)` it to the page once there is one.
    static func install(in configuration: inout WebPage.Configuration) -> PictureInPicture {
        let controller = PictureInPicture()
        guard isSupported else { return controller }
        let controllerForScripts = configuration.userContentController
        controllerForScripts.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                                        forMainFrameOnly: false, in: world))
        controllerForScripts.add(controller, contentWorld: world, name: handlerName)
        return controller
    }

    func attach(_ page: WebPage) {
        self.page = page
        Self.controllers.add(self)
        if let webView = backingWebView(of: page) { Self.enable(in: webView) }
    }

    /// The page is closing: nothing floats from it any more, even a request already on its way.
    func detach() {
        page = nil
        onRestore = nil
        Self.controllers.remove(self)
    }

    /// The page's controller, if it has one.
    static func controller(of page: WebPage) -> PictureInPicture? {
        controllers.allObjects.first { $0.page === page }
    }

    /// Mac WebKit floats video only with its Picture in Picture preference on, which has no public setter: the DMG
    /// build turns it on as WebKit's own MiniBrowser does. The App Store build can't, so it has no Picture in Picture,
    /// and its pages see `document.pictureInPictureEnabled` false and hide their own buttons.
    static func enable(in webView: WKWebView) {
        #if os(macOS) && DIRECT_DISTRIBUTION
        let preferences = webView.configuration.preferences
        let selector = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        guard preferences.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: selector), to: Setter.self)(preferences, selector, true)
        #endif
    }

    // MARK: Floating

    /// The user left the page (another tab or space, a hidden window) while it played a video: float it, unless
    /// something already floats, Boaz's or another app's.
    func floatOnLeaving() {
        isAway = true
        guard Self.floatsWhenLeaving, hasPlayingVideo, !Self.anyFloating else { return }
        Task { _ = await float(onLeaving: true) }
    }

    /// The user is back on the page: what Boaz floated when they left returns to it.
    func returnFromLeaving() {
        isAway = false
        guard let frame = floatedOnLeaving else { return }
        floatedOnLeaving = nil
        call("globalThis.__boazPiP?.returnFromLeaving()", in: [frame])
    }

    /// Floats the page's video, or brings it back if it's floating: the menu command.
    func toggle() {
        if isFloating {
            floatedOnLeaving = nil
            call("globalThis.__boazPiP?.exit()", in: frames.values.filter(\.floating).map(\.info))
        } else {
            Task { _ = await float(onLeaving: false) }
        }
    }

    private func float(onLeaving: Bool) async -> Bool {
        guard !Self.floatInFlight, let page, let webView = backingWebView(of: page) else { return false }
        Self.floatInFlight = true
        defer { Self.floatInFlight = false }
        Self.enable(in: webView)
        let ranked = frames.values
            .filter { onLeaving ? $0.playing != nil : $0.any != nil }
            .sorted { ($0.playing ?? -1, $0.any ?? -1) > ($1.playing ?? -1, $1.any ?? -1) }
        for frame in ranked.prefix(4) {
            // Back already, or the tab closed: nothing to float.
            guard self.page != nil, !onLeaving || isAway else { return false }
            let result = try? await webView.callAsyncJavaScript(
                "return await globalThis.__boazPiP?.float(onLeaving) ?? false", arguments: ["onLeaving": onLeaving],
                in: frame.info, contentWorld: Self.world)
            guard result as? Bool == true else { continue }
            floatedOnLeaving = onLeaving ? frame.info : nil
            if onLeaving && (!isAway || self.page == nil) { returnFromLeaving() }
            return true
        }
        return false
    }

    /// Clears what the page's frames said, once they're gone without saying so (its web content process ended).
    func pageDidReset() {
        frames.removeAll()
        floatedOnLeaving = nil
    }

    private func call(_ script: String, in frames: [WKFrameInfo]) {
        guard let page, let webView = backingWebView(of: page) else { return }
        for frame in frames {
            webView.evaluateJavaScript(script, in: frame, in: Self.world) { _ in }
        }
    }

    /// Whether any page floats a video, or another app shows Picture in Picture.
    static var anyFloating: Bool {
        floatInFlight || controllers.allObjects.contains(where: \.isFloating) || systemShowsPictureInPicture
    }

    /// Another app's Picture in Picture window (FaceTime, a video player). Window metadata only: no screen contents and
    /// no Screen Recording permission.
    private static var systemShowsPictureInPicture: Bool {
        #if os(macOS)
        let agents = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.PIPAgent")
            .map(\.processIdentifier))
        guard !agents.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, agents.contains(pid),
                  let bounds = window[kCGWindowBounds as String] as? [String: Double] else { return false }
            return (bounds["Width"] ?? 0) > 1 && (bounds["Height"] ?? 0) > 1
        }
        #else
        return false
        #endif
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["frame"] as? String, id.count <= 64,
              let kind = body["kind"] as? String else { return }
        let score = { (key: String) in (body[key] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        switch kind {
        case "state":
            guard frames[id] != nil || frames.count < 64 else { return }
            frames[id] = Frame(info: message.frameInfo, playing: score("playing"), any: score("any"),
                               floating: body["floating"] as? Bool == true)
        case "document":
            // A new main document: whatever the previous one's frames said is gone with them, said or not.
            guard message.frameInfo.isMainFrame else { return }
            pageDidReset()
        case "gone":
            frames[id] = nil
        case "restored":
            floatedOnLeaving = nil
            // Another video taking the window over brings this one back too: that isn't the user asking for it.
            let replaced = Self.floatInFlight || Self.controllers.allObjects.contains { $0 !== self && $0.isFloating }
            if !replaced { onRestore?() }
        default:
            break
        }
    }

    // MARK: Script

    private static let script = #"""
    (() => {
      'use strict';
      if (globalThis.__boazPiP) return;
      const handler = globalThis.webkit?.messageHandlers?.boazPictureInPicture;
      if (!handler) return;
      const frame = (crypto.randomUUID?.() ?? String(Math.random())).slice(0, 64);
      const post = message => { try { handler.postMessage({ frame, ...message }); } catch {} };
      if (window === top) post({ kind: 'document' });
      let floatedOnLeaving = null;
      let returning = false;
      let lastPlayed = null;

      const videos = () => {
        const found = [];
        const walk = root => {
          found.push(...root.querySelectorAll('video'));
          for (const host of root.querySelectorAll('*')) if (host.shadowRoot) walk(host.shadowRoot);
        };
        walk(document);
        return found;
      };
      const isFloating = video => document.pictureInPictureElement === video
        || video.webkitPresentationMode === 'picture-in-picture';
      const optsOut = video => video.disablePictureInPicture || video.hasAttribute('disablepictureinpicture');
      // A muted loop without controls is the page's backdrop, not something to watch.
      const isBackdrop = video => video.muted && video.loop && !video.controls;
      const score = (video, playingOnly) => {
        if (isBackdrop(video) || video.videoWidth === 0 || video.readyState < (playingOnly ? 2 : 1)) return 0;
        if (playingOnly && (video.paused || video.ended)) return 0;
        const bounds = video.getBoundingClientRect();
        if (bounds.width < 120 || bounds.height < 68) return 0;
        return bounds.width * bounds.height + (video.muted ? 0 : 1e8) + (video === lastPlayed ? 1e9 : 0);
      };
      const best = (all, playingOnly, respectingOptOut) => {
        let top = null, topScore = 0;
        for (const video of all) {
          if (respectingOptOut && optsOut(video)) continue;
          const value = score(video, playingOnly);
          if (value > topScore) { top = video; topScore = value; }
        }
        return top && { video: top, score: topScore };
      };

      // A frame without a video says nothing, so ad frames don't crowd out the player.
      const silent = JSON.stringify({ playing: 0, any: 0, floating: false });
      let scheduled = false, reported = silent;
      const report = () => {
        scheduled = false;
        const all = videos();
        const state = { playing: best(all, true, true)?.score ?? 0, any: best(all, false, false)?.score ?? 0,
                        floating: all.some(isFloating) };
        const encoded = JSON.stringify(state);
        if (encoded === reported) return;
        reported = encoded;
        post({ kind: 'state', ...state });
      };
      const schedule = () => { if (!scheduled) { scheduled = true; setTimeout(report, 150); } };
      for (const type of ['playing', 'pause', 'ended', 'emptied', 'loadeddata', 'volumechange', 'resize',
                          'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged']) {
        document.addEventListener(type, schedule, true);
      }
      document.addEventListener('play', event => {
        if (event.target instanceof HTMLVideoElement) lastPlayed = event.target;
      }, true);
      document.addEventListener('leavepictureinpicture', event => {
        const video = event.target;
        if (floatedOnLeaving === video) floatedOnLeaving = null;
        if (returning) { returning = false; return; }
        // The window's back button returns the video still playing; closing the window pauses it.
        setTimeout(() => { if (!video.paused) post({ kind: 'restored' }); }, 300);
      }, true);
      addEventListener('pagehide', () => { reported = silent; post({ kind: 'gone' }); });
      addEventListener('pageshow', event => { if (event.persisted) schedule(); });

      const leave = video => {
        returning = true;
        if (document.pictureInPictureElement === video) document.exitPictureInPicture().catch(() => {});
        else video.webkitSetPresentationMode?.('inline');
      };
      globalThis.__boazPiP = Object.freeze({
        async float(onLeaving) {
          const all = videos();
          if (all.some(isFloating)) return true;
          const found = best(all, true, onLeaving) ?? (onLeaving ? null : best(all, false, false));
          if (!found) return false;
          const video = found.video;
          // Asked by the user, Boaz floats it even where the site opts out of offering it, and puts the opt-out back.
          const optedOut = video.disablePictureInPicture;
          if (!onLeaving) video.disablePictureInPicture = false;
          try {
            if (video.requestPictureInPicture) await video.requestPictureInPicture();
            else video.webkitSetPresentationMode('picture-in-picture');
          } catch { return false; } finally { if (optedOut) video.disablePictureInPicture = true; }
          floatedOnLeaving = onLeaving ? video : null;
          return true;
        },
        returnFromLeaving() {
          if (floatedOnLeaving && isFloating(floatedOnLeaving)) leave(floatedOnLeaving);
        },
        exit() {
          const video = videos().find(isFloating);
          if (video) leave(video);
        },
      });
      schedule();
    })();
    """#
}
