import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The Develop menu's per-tab settings (`docs/devtools.md`). One per window; a tab's entry goes with its page
/// (`BrowserState.unload`), and nothing is saved or synced.
@Observable
final class DevTools {
    struct TabState {
        /// The agent picked from the menu (`.default` included); nil follows Responsive Design Mode's device, else
        /// WebKit's default.
        var userAgent: UserAgent?
        /// Non-nil while Responsive Design Mode is on.
        var responsive: Viewport?
        var media: WebPage.CSSMediaType?
        var appearance: ColorScheme?
        var vision: Vision = .none
        var javaScriptDisabled = false
        var console: [ConsoleLine] = []
        var consoleHistory: [String] = []

        var effectiveUserAgent: UserAgent? { userAgent ?? responsive?.userAgent }
    }

    struct Viewport: Equatable {
        /// Nil fills the pane.
        var size: CGSize?
        /// The device's own browser, which a phone or tablet preset brings along.
        var userAgent: UserAgent?
    }

    struct ConsoleLine: Identifiable {
        enum Kind { case input, result, error, log, warning }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    enum Sheet: Identifiable {
        case source(title: String, html: String)
        case storage(tabID: String)
        case userAgent(tabID: String)

        var id: String {
            switch self {
            case .source: "source"
            case .storage: "storage"
            case .userAgent: "userAgent"
            }
        }
    }

    /// Scripts Boaz runs for these tools live apart from the page's own.
    static let world = WKContentWorld.world(name: "boaz-devtools")

    private(set) var tabs: [String: TabState] = [:]
    private(set) var consoleVisible = false
    /// The console takes the keyboard when opened, not each time a pane showing it appears.
    var focusConsole = false
    var sheet: Sheet?

    subscript(tabID: String?) -> TabState {
        get { tabID.flatMap { tabs[$0] } ?? TabState() }
        set { if let tabID { tabs[tabID] = newValue } }
    }

    func drop(_ tabID: String) { tabs[tabID] = nil }

    func toggleConsole() {
        consoleVisible.toggle()
        focusConsole = consoleVisible
    }
}

enum UserAgent: Hashable {
    /// WebKit's own, picked explicitly: it overrides a Responsive Design Mode device's.
    case `default`
    case safariIPhone, safariIPad, safariMac, chromeMac, chromeWindows, chromeAndroid, firefoxMac, edgeWindows
    case custom(String)

    static let presets: [UserAgent] = [
        .safariIPhone, .safariIPad, .safariMac, .chromeMac, .chromeWindows, .chromeAndroid, .firefoxMac, .edgeWindows,
    ]

    var title: String {
        switch self {
        case .default: "Default"
        case .safariIPhone: "Safari — iPhone"
        case .safariIPad: "Safari — iPad"
        case .safariMac: "Safari — Mac"
        case .chromeMac: "Chrome — Mac"
        case .chromeWindows: "Chrome — Windows"
        case .chromeAndroid: "Chrome — Android"
        case .firefoxMac: "Firefox — Mac"
        case .edgeWindows: "Edge — Windows"
        case .custom: "Other…"
        }
    }

    var string: String? {
        switch self {
        case .default: nil
        case .safariIPhone:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        case .safariIPad:
            "Mozilla/5.0 (iPad; CPU OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        case .safariMac:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case .chromeMac:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
        case .chromeWindows:
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
        case .chromeAndroid:
            "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36"
        case .firefoxMac:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:145.0) Gecko/20100101 Firefox/145.0"
        case .edgeWindows:
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0"
        case .custom(let string): string
        }
    }
}

/// Responsive Design Mode's sizes, in CSS pixels, portrait.
struct DevicePreset: Identifiable {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let userAgent: UserAgent?
    var id: String { name }
    var size: CGSize { CGSize(width: width, height: height) }

    static let all: [DevicePreset] = [
        .init(name: "iPhone SE", width: 375, height: 667, userAgent: .safariIPhone),
        .init(name: "iPhone 17", width: 402, height: 874, userAgent: .safariIPhone),
        .init(name: "iPhone 17 Pro Max", width: 440, height: 956, userAgent: .safariIPhone),
        .init(name: "iPad mini", width: 744, height: 1133, userAgent: .safariIPad),
        .init(name: "iPad Pro 13\"", width: 1032, height: 1376, userAgent: .safariIPad),
        .init(name: "Laptop", width: 1280, height: 800, userAgent: nil),
        .init(name: "Desktop", width: 1440, height: 900, userAgent: nil),
    ]

    /// The preset this size is, either way round.
    static func matching(_ size: CGSize?) -> DevicePreset? {
        guard let size else { return nil }
        return all.first { $0.size == size || ($0.height == size.width && $0.width == size.height) }
    }
}

/// Color-vision filters: Machado, Oliveira and Fernandes (2009) matrices at full severity, applied in linear RGB
/// (`feColorMatrix`'s default), and CSS filters for blur and contrast.
enum Vision: String, CaseIterable, Identifiable {
    case none, protanopia, deuteranopia, tritanopia, achromatopsia, blurred, lowContrast
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .protanopia: "Protanopia"
        case .deuteranopia: "Deuteranopia"
        case .tritanopia: "Tritanopia"
        case .achromatopsia: "Achromatopsia"
        case .blurred: "Blurred Vision"
        case .lowContrast: "Low Contrast"
        }
    }

    private var matrix: [Double]? {
        switch self {
        case .protanopia: [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]
        case .deuteranopia: [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]
        case .tritanopia: [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.304900]
        case .achromatopsia: [0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722]
        default: nil
        }
    }

    /// `css` for the root's `filter`, and the 4×5 `feColorMatrix` values it points at, if any.
    fileprivate var filter: (css: String, matrix: String) {
        if let matrix {
            let rows = stride(from: 0, to: 9, by: 3).map { row in
                (matrix[row..<row + 3].map { String($0) } + ["0", "0"]).joined(separator: " ")
            }
            return ("url(#boaz-devtools-vision-filter)", (rows + ["0 0 0 1 0"]).joined(separator: " "))
        }
        switch self {
        case .blurred: return ("blur(3px)", "")
        case .lowContrast: return ("contrast(0.4)", "")
        default: return ("", "")
        }
    }

    fileprivate static let script = """
        for (const node of document.querySelectorAll('[data-boaz-devtools-vision]')) node.remove();
        const root = document.documentElement;
        if (!css || !root) return;
        if (matrix) {
            const ns = 'http://www.w3.org/2000/svg';
            const svg = document.createElementNS(ns, 'svg');
            svg.setAttribute('data-boaz-devtools-vision', '');
            svg.setAttribute('aria-hidden', 'true');
            svg.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
            const filter = document.createElementNS(ns, 'filter');
            filter.id = 'boaz-devtools-vision-filter';
            const colors = document.createElementNS(ns, 'feColorMatrix');
            colors.setAttribute('type', 'matrix');
            colors.setAttribute('values', matrix);
            filter.appendChild(colors);
            svg.appendChild(filter);
            root.appendChild(svg);
        }
        const style = document.createElement('style');
        style.setAttribute('data-boaz-devtools-vision', '');
        style.textContent = `html { filter: ${css} !important; }`;
        root.appendChild(style);
        """
}

/// The JavaScript Console's page side: eval with result formatting, and a `console` hook drained by polling.
enum ConsoleScripts {
    private static let format = """
        const __boazFormat = value => {
            if (typeof value === 'string') return JSON.stringify(value);
            if (value === undefined) return 'undefined';
            if (['function', 'symbol', 'bigint'].includes(typeof value) || value instanceof Error) return String(value);
            if (typeof Node !== 'undefined' && value instanceof Node) return value.outerHTML ?? value.nodeName;
            try { return JSON.stringify(value, null, 2) ?? String(value); } catch { return String(value); }
        };
        """

    /// Whether `source` parses as an expression; a statement list (`let`, `if`, `return`…) doesn't. Run in Boaz's
    /// world, which the page's Content Security Policy doesn't hold to `unsafe-eval`.
    static let parsesAsExpression = """
        try {
            new (Object.getPrototypeOf(async function () {}).constructor)('return (\\n' + source + '\\n);');
            return true;
        } catch (error) {
            return !(error instanceof SyntaxError);
        }
        """

    /// The input as an expression.
    static func expression(_ input: String) -> String { "\(format)\nreturn __boazFormat(await (\n\(input)\n));" }
    static func body(_ input: String) -> String { "\(format)\nreturn __boazFormat(await (async () => {\n\(input)\n})());" }

    /// Installs the hook unless the page already has it (a new document doesn't), and returns what was logged since
    /// the last call as JSON `[[level, text], …]`.
    static let drain = """
        const key = Symbol.for('boaz.devtools.console');
        let state = window[key];
        if (!state) {
            const text = value => {
                if (typeof value === 'string') return value;
                try { return JSON.stringify(value) ?? String(value); } catch { return String(value); }
            };
            state = { lines: [], original: {} };
            for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
                const original = console[level];
                state.original[level] = original;
                console[level] = function (...args) {
                    state.lines.push([level, args.map(text).join(' ')]);
                    if (state.lines.length > 500) state.lines.shift();
                    return original.apply(this, args);
                };
            }
            state.onError = event => state.lines.push(['error', String(event.message ?? event)]);
            addEventListener('error', state.onError);
            Object.defineProperty(window, key, { value: state, configurable: true });
        }
        return JSON.stringify(state.lines.splice(0));
        """

    static let uninstall = """
        const key = Symbol.for('boaz.devtools.console');
        const state = window[key];
        if (!state) return;
        for (const [level, original] of Object.entries(state.original)) console[level] = original;
        removeEventListener('error', state.onError);
        delete window[key];
        """
}

extension BrowserState {
    // MARK: Emulation

    func setUserAgent(_ agent: UserAgent?, tabID: String? = nil) {
        guard let id = tabID ?? activeTabID else { return }
        devTools[id].userAgent = agent
        applyUserAgent(id)
    }

    func toggleResponsiveDesign(tabID: String? = nil) {
        guard let id = tabID ?? activeTabID else { return }
        devTools[id].responsive = devTools[id].responsive == nil ? DevTools.Viewport(size: nil) : nil
        applyUserAgent(id)
    }

    func setViewport(_ viewport: DevTools.Viewport, tabID: String) {
        devTools[tabID].responsive = viewport
        applyUserAgent(tabID)
    }

    /// Reloads only when the agent changed: sites read it on the server and as the page starts.
    private func applyUserAgent(_ tabID: String) {
        guard let page = existingPage(for: tabID) else { return }
        let agent = devTools[tabID].effectiveUserAgent?.string
        guard (page.customUserAgent ?? "") != (agent ?? "") else { return }
        page.customUserAgent = agent
        page.reload(tabURL: loadFailures[tabID]?.url ?? tab(tabID)?.url)
    }

    func setMediaType(_ media: WebPage.CSSMediaType?) {
        guard let id = activeTabID else { return }
        devTools[id].media = media
        existingPage(for: id)?.mediaType = media
    }

    func setAppearance(_ appearance: ColorScheme?) {
        guard let id = activeTabID else { return }
        devTools[id].appearance = appearance
    }

    func setVision(_ vision: Vision) {
        guard let id = activeTabID else { return }
        devTools[id].vision = vision
        applyVision(id)
    }

    private func applyVision(_ tabID: String) {
        guard let page = existingPage(for: tabID) else { return }
        let filter = devTools[tabID].vision.filter
        Task {
            _ = try? await page.callJavaScript(Vision.script, arguments: ["css": filter.css, "matrix": filter.matrix],
                                               contentWorld: DevTools.world)
        }
    }

    /// A new document starts without the vision filter.
    func devToolsDidLoad(_ tabID: String) {
        if devTools[tabID].vision != .none { applyVision(tabID) }
    }

    func toggleJavaScript() {
        guard let id = activeTabID else { return }
#if BOAZ_CHROMIUM
        if let adapter = activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
            do { try adapter.setJavaScriptDisabled(!devTools[id].javaScriptDisabled) }
            catch { model.showToast(error.localizedDescription); return }
        }
#endif
        devTools[id].javaScriptDisabled.toggle()
        reload()
    }

    func javaScriptDisabled(_ context: NavigationRouter.Context) -> Bool {
        guard case .tab(let id) = context else { return false }
        return devTools[id].javaScriptDisabled
    }

    // MARK: Data

    /// Clears the tab's profile's caches (not its cookies or storage) and reloads from the server.
    func emptyCaches() {
        guard let tab = activeTab, let page = activePage else { return }
        let store = dataStore(profileID: tab.profileID)
        let tabURL = loadFailures[tab.id]?.url ?? tab.url
        Task {
            await store.removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                                             WKWebsiteDataTypeFetchCache], modifiedSince: .distantPast)
            page.reload(tabURL: tabURL, fromOrigin: true)
            model.showToast("Caches emptied")
        }
    }

    func showStorage() {
        guard let id = activeTabID, activePage != nil else { return }
        devTools.sheet = .storage(tabID: id)
    }

    func viewPageSource() {
        guard let page = activePage else { return }
        let title = page.title.isEmpty ? (activeURL?.host() ?? "Page Source") : page.title
        Task {
            let html = try? await page.callJavaScript("return document.documentElement?.outerHTML ?? ''",
                                                      contentWorld: DevTools.world) as? String
            devTools.sheet = .source(title: title, html: html ?? "")
        }
    }

    // MARK: Capture

    /// Saves a PNG of the page (the viewport, or all of it) to ~/Downloads and puts it on the pasteboard.
    func captureScreenshot(fullPage: Bool) {
        guard let page = activePage else { return }
        let host = activeURL?.host() ?? "Boaz"
        Task {
            do {
                var region = WebPage.ExportedContentConfiguration.Region.contents
                // The region is in the view's coordinates, whose origin is the top of what's on screen.
                if !fullPage, let size = try await page.callJavaScript("return [innerWidth, innerHeight]",
                                                                       contentWorld: DevTools.world) as? [Double],
                   size.count == 2 {
                    region = .rect(CGRect(x: 0, y: 0, width: size[0], height: size[1]))
                }
                let data = try await page.exported(as: .image(region: region))
                let formatter = DateFormatter()
                // Milliseconds, so captures in the same second don't overwrite each other.
                formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
                let url = try Downloads.directory().appendingPathComponent("\(host) \(formatter.string(from: .now)).png")
                // A full page can be tens of megapixels: encoded and written off the main thread.
                let png = try await Task.detached {
                    guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try png.write(to: url)
                    return png
                }.value
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(png, forType: .png)
                model.showToast("Screenshot saved")
            } catch {
                model.showToast("Couldn't capture this page")
            }
        }
    }

    func exportPDF() {
        guard let page = activePage else { return }
        let name = (page.title.isEmpty ? (activeURL?.host() ?? "Page") : page.title)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        Task {
            guard let data = try? await page.exported(as: .pdf()) else {
                model.showToast("Couldn't export this page")
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = name + ".pdf"
            let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                model.showToast("PDF saved")
            } catch {
                model.showToast("Couldn't save the PDF")
            }
        }
    }
}
