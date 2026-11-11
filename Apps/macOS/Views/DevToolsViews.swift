import AppKit
import SwiftUI
import WebKit

/// The Develop menu (`docs/devtools.md`). Web Inspector itself opens from the page's context menu: WebKit offers no
/// public way to open it.
struct DevelopCommands: Commands {
    let model: MacModel
    @FocusedValue(BrowserState.self) private var browser

    private func key(_ command: BrowserCommand) -> KeyboardShortcut? { model.keyBindings.shortcut(command) }

    var body: some Commands {
        CommandMenu("Develop") {
            let state = browser?.devTools[browser?.activeTabID] ?? DevTools.TabState()
            let noPage = browser?.activeTab == nil
            Button("Inspect Element: Right-Click the Page") {}.disabled(true)
            Divider()
            Button(state.responsive == nil ? "Enter Responsive Design Mode" : "Exit Responsive Design Mode") {
                browser?.toggleResponsiveDesign()
            }
            .keyboardShortcut(key(.responsiveDesignMode)).disabled(noPage)
            Menu("User Agent") {
                let current = state.effectiveUserAgent ?? .default
                check("Default", current == .default) { browser?.setUserAgent(.default) }
                Divider()
                ForEach(UserAgent.presets, id: \.self) { agent in
                    check(agent.title, current == agent) { browser?.setUserAgent(agent) }
                }
                Divider()
                check("Other…", { if case .custom = current { true } else { false } }()) {
                    if let id = browser?.activeTabID { browser?.devTools.sheet = .userAgent(tabID: id) }
                }
            }
            .disabled(noPage)
            Menu("Emulate Media") {
                check("Screen", state.media != .print) { browser?.setMediaType(nil) }
                check("Print", state.media == .print) { browser?.setMediaType(.print) }
                Divider()
                check("Light Appearance", state.appearance == .light) { browser?.setAppearance(.light) }
                check("Dark Appearance", state.appearance == .dark) { browser?.setAppearance(.dark) }
                check("System Appearance", state.appearance == nil) { browser?.setAppearance(nil) }
            }
            .disabled(noPage)
            Menu("Vision Simulator") {
                ForEach(Vision.allCases) { vision in
                    check(vision.title, state.vision == vision) { browser?.setVision(vision) }
                    if vision == .none { Divider() }
                }
            }
            .disabled(noPage)
            check("Disable JavaScript", state.javaScriptDisabled) { browser?.toggleJavaScript() }.disabled(noPage)
            Divider()
            Button(browser?.devTools.consoleVisible == true ? "Hide JavaScript Console" : "Show JavaScript Console") {
                browser?.devTools.toggleConsole()
            }
            .keyboardShortcut(key(.javaScriptConsole)).disabled(noPage)
            Button("View Page Source") { browser?.viewPageSource() }.keyboardShortcut(key(.viewSource)).disabled(noPage)
            Button("Show Storage…") { browser?.showStorage() }.disabled(noPage)
            Divider()
            Button("Capture Visible Area") { browser?.captureScreenshot(fullPage: false) }.disabled(noPage)
            Button("Capture Full Page") { browser?.captureScreenshot(fullPage: true) }.disabled(noPage)
            Button("Export as PDF…") { browser?.exportPDF() }.disabled(noPage)
            Divider()
            Button("Empty Caches") { browser?.emptyCaches() }.keyboardShortcut(key(.emptyCaches)).disabled(noPage)
        }
    }

    /// A menu item with a checkmark while `isOn`.
    private func check(_ title: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding { isOn } set: { _ in action() })
    }
}

// MARK: Responsive Design Mode

extension View {
    /// Sizes a tab's WebView to the emulated device, scaled down to fit `scale`, on a neutral backdrop, and gives it
    /// the emulated appearance. Always the same modifiers, so the WebView keeps its identity as the mode changes.
    func deviceViewport(_ viewport: DevTools.Viewport?, scale: CGFloat, appearance: ColorScheme?,
                        stage: Binding<CGSize>) -> some View {
        modifier(DeviceViewport(viewport: viewport, scale: scale, appearance: appearance, stage: stage))
    }
}

private struct DeviceViewport: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let viewport: DevTools.Viewport?
    let scale: CGFloat
    let appearance: ColorScheme?
    @Binding var stage: CGSize

    func body(content: Content) -> some View {
        let size = viewport?.size
        content
            // WebKit reads `prefers-color-scheme` from the view's appearance.
            .environment(\.colorScheme, appearance ?? colorScheme)
            .frame(width: size?.width, height: size?.height)
            .scaleEffect(scale)
            .frame(width: size.map { $0.width * scale }, height: size.map { $0.height * scale })
            .shadow(color: .black.opacity(size == nil ? 0 : 0.2), radius: 8, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(viewport == nil ? Color.clear : Color(nsColor: .underPageBackgroundColor))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { stage = $0 }
    }
}

/// Responsive Design Mode's controls above the page: device, size, rotation and zoom.
struct ResponsiveBar: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let tabID: String
    let viewport: DevTools.Viewport
    /// The room the page has, which a viewport filling the pane takes.
    let stage: CGSize
    let scale: CGFloat

    var body: some View {
        let size = viewport.size ?? stage
        HStack(spacing: 8) {
            Menu(DevicePreset.matching(viewport.size)?.name ?? (viewport.size == nil ? "Fill Window" : "Custom")) {
                ForEach(DevicePreset.all) { preset in
                    Button("\(preset.name)  \(Int(preset.width)) × \(Int(preset.height))") {
                        browser.setViewport(.init(size: preset.size, userAgent: preset.userAgent), tabID: tabID)
                    }
                }
                Divider()
                Button("Fill Window") { browser.setViewport(.init(size: nil), tabID: tabID) }
            }
            .fixedSize()
            dimension(size.width, label: "Width") { CGSize(width: $0, height: size.height) }
            Text("×").foregroundStyle(.secondary)
            dimension(size.height, label: "Height") { CGSize(width: size.width, height: $0) }
            HoverIconButton(symbol: "rectangle.portrait.rotate", help: "Rotate", size: 24) {
                browser.setViewport(.init(size: CGSize(width: size.height, height: size.width), userAgent: viewport.userAgent),
                                    tabID: tabID)
            }
            Spacer()
            if scale < 1 {
                Text("\(Int((scale * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                    .help("Scaled to fit the window")
            }
            HoverIconButton(symbol: "xmark", help: "Exit Responsive Design Mode",
                            hint: model.keyBindings.hint("Exit Responsive Design Mode", .responsiveDesignMode),
                            size: 24) { browser.toggleResponsiveDesign(tabID: tabID) }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(height: 36)
    }

    private func dimension(_ value: CGFloat, label: String, size: @escaping (CGFloat) -> CGSize) -> some View {
        TextField(label, value: Binding { Int(value) } set: { new in
            browser.setViewport(.init(size: size(CGFloat(min(max(new, 100), 5000))), userAgent: viewport.userAgent),
                                tabID: tabID)
        }, format: .number.grouping(.never))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.center)
        .monospacedDigit()
        .frame(width: 64)
        .accessibilityLabel(label)
    }
}

// MARK: JavaScript Console

/// Runs JavaScript in the active tab's page and shows what the page logs while it's open.
struct ConsolePanel: View {
    @Environment(BrowserState.self) private var browser
    let tabID: String
    let page: WebPage
    @State private var input = ""
    @State private var historyIndex: Int?
    @FocusState private var focused: Bool

    var body: some View {
        let lines = browser.devTools[tabID].console
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Text("Console").font(.caption.weight(.semibold))
                Spacer()
                HoverIconButton(symbol: "trash", help: "Clear Console", size: 22) { browser.devTools[tabID].console = [] }
                HoverIconButton(symbol: "xmark", help: "Hide Console", size: 22) { browser.devTools.toggleConsole() }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { ConsoleRow(line: $0).id($0.id) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .onChange(of: lines.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tint)
                TextField("Run JavaScript", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .focused($focused)
                    .onSubmit(run)
                    .onKeyPress(.upArrow) { recall(-1); return .handled }
                    .onKeyPress(.downArrow) { recall(1); return .handled }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .frame(height: 220)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            guard browser.devTools.focusConsole else { return }
            browser.devTools.focusConsole = false
            focused = true
        }
        .task(id: ObjectIdentifier(page)) { await watchConsole() }
        // Not from `watchConsole`: its task is cancelled by then.
        .onDisappear { [page] in Task { _ = try? await page.callJavaScript(ConsoleScripts.uninstall, contentWorld: .page) } }
    }

    private func run() {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        input = ""
        historyIndex = nil
        browser.devTools[tabID].consoleHistory.append(source)
        append(.input, source)
        let expression = source.hasSuffix(";") ? String(source.dropLast()) : source
        Task {
            do {
                // Only parsed here, never run, so the input runs once whichever way it's read.
                let isExpression = (try? await page.callJavaScript(ConsoleScripts.parsesAsExpression,
                                                                   arguments: ["source": expression],
                                                                   contentWorld: DevTools.world) as? Bool) ?? true
                let value = try await page.callJavaScript(
                    isExpression ? ConsoleScripts.expression(expression) : ConsoleScripts.body(source), contentWorld: .page)
                append(.result, value as? String ?? "undefined")
            } catch {
                append(.error, Self.exceptionMessage(error) ?? error.localizedDescription)
            }
        }
    }

    private static func exceptionMessage(_ error: Error) -> String? {
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
    }

    /// ↑ and ↓ step through what was run in this tab.
    private func recall(_ step: Int) {
        let history = browser.devTools[tabID].consoleHistory
        guard !history.isEmpty else { return }
        let index = min(max((historyIndex ?? history.count) + step, 0), history.count)
        historyIndex = index
        input = index < history.count ? history[index] : ""
    }

    /// The hook goes in each new document as the console polls, and comes out when the panel goes.
    private func watchConsole() async {
        while !Task.isCancelled {
            if let json = try? await page.callJavaScript(ConsoleScripts.drain, contentWorld: .page) as? String,
               let logged = try? JSONDecoder().decode([[String]].self, from: Data(json.utf8)) {
                for entry in logged where entry.count == 2 {
                    append(entry[0] == "error" ? .error : entry[0] == "warn" ? .warning : .log, entry[1])
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func append(_ kind: DevTools.ConsoleLine.Kind, _ text: String) {
        browser.devTools[tabID].console.append(.init(kind: kind, text: text))
        if browser.devTools[tabID].console.count > 1000 { browser.devTools[tabID].console.removeFirst() }
    }
}

private struct ConsoleRow: View {
    let line: DevTools.ConsoleLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(color).frame(width: 12)
            Text(line.text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var symbol: String {
        switch line.kind {
        case .input: "chevron.right"
        case .result: "arrow.left"
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .log: "circle.fill"
        }
    }

    /// Darker than the system red and orange in Light, lighter in Dark, to read at 4.5:1 on the text background.
    private var color: Color {
        switch line.kind {
        case .error: Self.adaptive(light: (0.75, 0.1, 0.1), dark: (1, 0.47, 0.44))
        case .warning: Self.adaptive(light: (0.6, 0.35, 0), dark: (1, 0.75, 0.3))
        default: .primary
        }
    }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

// MARK: Sheets

extension View {
    func devToolsSheets(_ browser: BrowserState) -> some View { modifier(DevToolsSheets(browser: browser, devTools: browser.devTools)) }
}

private struct DevToolsSheets: ViewModifier {
    let browser: BrowserState
    @Bindable var devTools: DevTools

    func body(content: Content) -> some View {
        content.sheet(item: $devTools.sheet) { sheet in
            Group {
                switch sheet {
                case .source(let title, let html): SourceSheet(title: title, html: html)
                case .storage(let tabID): StorageSheet(tabID: tabID)
                case .userAgent(let tabID): UserAgentSheet(tabID: tabID)
                }
            }
            .environment(browser)
        }
    }
}

private struct UserAgentSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let tabID: String
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom User Agent").font(.headline)
            TextField("User agent", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .frame(width: 460)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set", action: save).keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onAppear { text = browser.devTools[tabID].effectiveUserAgent?.string ?? "" }
    }

    private func save() {
        let agent = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agent.isEmpty { browser.setUserAgent(.custom(agent), tabID: tabID) }
        dismiss()
    }
}

private struct SourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let html: String

    var body: some View {
        VStack(spacing: 0) {
            SourceTextView(text: html)
            Divider()
            HStack {
                Text(title).lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(html, forType: .string)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 480, idealHeight: 640)
    }
}

/// Read-only, selectable source with the system find bar, which opens with the sheet.
private struct SourceTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        Task {
            textView.window?.makeFirstResponder(textView)
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performTextFinderAction(sender)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}

/// The active tab's site's cookies, local storage and session storage.
private struct StorageSheet: View {
    enum Section: String, CaseIterable { case cookies = "Cookies", local = "Local Storage", session = "Session Storage" }
    struct Entry: Identifiable { let key: String; let value: String; var id: String { key } }
    struct Cookie: Identifiable { let cookie: HTTPCookie; var id: String { "\(cookie.name)|\(cookie.domain)|\(cookie.path)" } }

    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let tabID: String
    @State private var section = Section.cookies
    @State private var cookies: [Cookie] = []
    @State private var entries: [Entry] = []
    @State private var selection = Set<String>()

    private var page: WebPage? { browser.existingPage(for: tabID) }
    private var host: String? { page?.url?.host()?.lowercased() }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Storage", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Group {
                if section == .cookies { cookieTable } else { entryTable }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button("Copy Value") { copy(ids) }
                Button("Delete") { Task { await delete(ids) } }
            } primaryAction: { copy($0) }
            .onDeleteCommand { Task { await delete(selection) } }
            Divider()
            HStack {
                Text(host ?? "").foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive) { Task { await delete(nil) } }
                    .disabled(section == .cookies ? cookies.isEmpty : entries.isEmpty)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 440, idealHeight: 520)
        .task(id: section) {
            selection = []
            await refresh()
        }
    }

    private var cookieTable: some View {
        Table(cookies, selection: $selection) {
            TableColumn("Name") { Text($0.cookie.name) }
            TableColumn("Value") { Text($0.cookie.value).lineLimit(1) }
            TableColumn("Domain") { Text($0.cookie.domain) }
            TableColumn("Path") { Text($0.cookie.path) }
            TableColumn("Expires") {
                Text($0.cookie.expiresDate?.formatted(date: .abbreviated, time: .shortened) ?? "Session")
            }
            TableColumn("Flags") { Text(Self.flags($0.cookie)) }
        }
    }

    private var entryTable: some View {
        Table(entries, selection: $selection) {
            TableColumn("Key") { Text($0.key) }
            TableColumn("Value") { Text($0.value).lineLimit(1) }
        }
    }

    private static func flags(_ cookie: HTTPCookie) -> String {
        var flags: [String] = []
        if cookie.isSecure { flags.append("Secure") }
        if cookie.isHTTPOnly { flags.append("HttpOnly") }
        if let sameSite = cookie.sameSitePolicy { flags.append("SameSite=\(sameSite.rawValue)") }
        return flags.joined(separator: ", ")
    }

    private var store: WKWebsiteDataStore { browser.dataStore(profileID: browser.tab(tabID)?.profileID) }

    private func refresh() async {
        guard let host else { cookies = []; entries = []; return }
        if section == .cookies {
            // The host's own cookies and those set for a domain it's in (`.example.com`).
            cookies = await store.httpCookieStore.allCookies().filter { cookie in
                let domain = cookie.domain.lowercased()
                guard domain.hasPrefix(".") else { return host == domain }
                return host == domain.dropFirst() || host.hasSuffix(domain)
            }
            .sorted { $0.name < $1.name }
            .map(Cookie.init)
        } else {
            let json = try? await page?.callJavaScript(Self.read, arguments: ["session": section == .session],
                                                       contentWorld: DevTools.world) as? String
            let pairs = json.flatMap { try? JSONDecoder().decode([[String]].self, from: Data($0.utf8)) } ?? []
            entries = pairs.filter { $0.count == 2 }.map { Entry(key: $0[0], value: $0[1]) }.sorted { $0.key < $1.key }
        }
    }

    private static let read = """
        try { return JSON.stringify(Object.entries(session ? sessionStorage : localStorage)); } catch { return '[]'; }
        """
    private static let remove = """
        const storage = session ? sessionStorage : localStorage;
        if (all) storage.clear(); else for (const key of keys) storage.removeItem(key);
        """

    private func copy(_ ids: Set<String>) {
        let values = section == .cookies ? cookies.filter { ids.contains($0.id) }.map(\.cookie.value)
            : entries.filter { ids.contains($0.id) }.map(\.value)
        guard !values.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values.joined(separator: "\n"), forType: .string)
    }

    /// Deletes the rows `ids` names, or all of them when nil.
    private func delete(_ ids: Set<String>?) async {
        if section == .cookies {
            for row in cookies where ids?.contains(row.id) ?? true { await store.httpCookieStore.deleteCookie(row.cookie) }
        } else {
            let keys = entries.filter { ids?.contains($0.id) ?? true }.map(\.key)
            _ = try? await page?.callJavaScript(Self.remove, arguments: ["session": section == .session, "all": ids == nil,
                                                                         "keys": keys], contentWorld: DevTools.world)
        }
        selection = []
        await refresh()
    }
}
