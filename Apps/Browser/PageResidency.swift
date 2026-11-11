import WebKit

/// Which live pages a browser closes to stay within its page limit: the least recently used first, never one that's
/// doing something the user would notice stopping.
enum PageResidency {
    /// Playing media, floating a video in Picture in Picture, using the camera or microphone, or in full screen.
    static func isBusy(_ page: WebPage) async -> Bool {
        if page.cameraCaptureState != .none || page.microphoneCaptureState != .none
            || page.fullscreenState != .notInFullscreen
            || PictureInPicture.controller(of: page)?.isFloating == true { return true }
        return await page.mediaPlaybackState() == .playing
    }

    /// The pages to close, oldest first, until `limit` remain: `recency` runs from least to most recently used, and
    /// `kept` (the pages in view) and busy pages stay. Callers check `kept` again, since it may change meanwhile.
    static func pagesToClose(recency: [String], pages: [String: WebPage], limit: Int,
                             keeping kept: Set<String>) async -> [String] {
        var excess = pages.count - limit
        var close: [String] = []
        for id in recency where excess > 0 {
            guard !kept.contains(id), let page = pages[id] else { continue }
            let busy = await isBusy(page)
            if !busy { close.append(id); excess -= 1 }
        }
        return close
    }
}
