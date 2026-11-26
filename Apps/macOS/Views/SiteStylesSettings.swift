import AppKit
import BoazKit
import SwiftUI
import WebKit

/// The page an editor previews on: the tab it was opened from. Held weakly, so a tab closed meanwhile just stops
/// previewing.
@MainActor
final class SiteStyleTarget {
    weak var webPage: WebPage?
    #if BOAZ_CHROMIUM
    weak var chromiumPage: ChromiumEnginePageAdapter?
    #endif

    var id: ObjectIdentifier? {
        #if BOAZ_CHROMIUM
        if let chromiumPage { return ObjectIdentifier(chromiumPage) }
        #endif
        return webPage.map(ObjectIdentifier.init)
    }

    var hostKey: String? {
        #if BOAZ_CHROMIUM
        if let chromiumPage { return chromiumPage.state.lifecycle == .active ? SiteStyles.hostKey(chromiumPage.state.url) : nil }
        #endif
        return SiteStyles.hostKey(webPage?.url)
    }

    /// Shows what `SiteStyles.effectiveCSS` now says for this page.
    func apply() async -> SiteStyles.Outcome? {
        #if BOAZ_CHROMIUM
        if let chromiumPage { return await SiteStyles.shared.apply(on: chromiumPage) }
        #endif
        guard let webPage, let host = hostKey, let id else { return nil }
        let styles = SiteStyles.shared
        return await SiteStyles.run(styles.effectiveCSS(page: id, profileID: profileID, host: host), on: webPage)
    }

    let profileID: String
    init(profileID: String) { self.profileID = profileID }
}

/// One site's style being edited: from View › Edit Site Style… with a live preview on the tab, or from Settings
/// without one (Settings never renders user CSS).
@MainActor @Observable
final class SiteStyleDraft: Identifiable {
    enum Notice: Equatable { case none, leftHost, blocked, tooLong, full }

    let host: String
    let profileID: String
    let profileName: String?
    @ObservationIgnored let target: SiteStyleTarget?
    private(set) var saved: String
    var text: String { didSet { if text != oldValue { textChanged() } } }
    private(set) var previewNotice: Notice = .none
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored weak var textView: NSTextView?

    init(host: String, profileID: String, profileName: String?, target: SiteStyleTarget?) {
        self.host = host
        self.profileID = profileID
        self.profileName = profileName
        self.target = target
        let saved = SiteStyles.shared.book.css(profileID: profileID, host: host) ?? ""
        self.saved = saved
        text = saved
    }

    var hasSavedStyle: Bool { !saved.isEmpty }
    var isTooLong: Bool { !SiteStyleBook.fits(text) }
    var isFull: Bool { !text.isEmpty && SiteStyles.shared.book.isFull(adding: host, profileID: profileID) }
    var canSave: Bool { text != saved && !isTooLong && !isFull }

    var notice: Notice {
        if isTooLong { return .tooLong }
        if isFull { return .full }
        return previewNotice
    }

    /// A preset's plain CSS goes at the end, so nothing typed is lost; ⌘Z takes it back off.
    func add(_ preset: SiteStylePreset) {
        let addition = preset.addition(to: text)
        if let textView {
            textView.window?.makeFirstResponder(textView)
            textView.insertText(addition, replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
        } else {
            text += addition
        }
        previewNow()
    }

    private func textChanged() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.previewNow()
        }
    }

    private func previewNow() {
        debounce?.cancel()
        guard let target, let id = target.id else { return }
        guard target.hostKey == host else {
            SiteStyles.shared.preview = nil
            previewNotice = .leftHost
            return
        }
        // Above the cap the page keeps the last text that fit.
        guard !isTooLong else { return }
        SiteStyles.shared.preview = .init(page: id, profileID: profileID, host: host, css: text)
        Task {
            let outcome = await target.apply()
            previewNotice = outcome == .blocked ? .blocked : .none
        }
    }

    /// The page goes back to the saved text (or none).
    func cancel() {
        debounce?.cancel()
        guard let target, SiteStyles.shared.preview?.page == target.id else { return }
        SiteStyles.shared.preview = nil
        if target.hostKey == host { Task { _ = await target.apply() } }
    }

    func save() {
        debounce?.cancel()
        SiteStyles.shared.preview = nil
        try? SiteStyles.shared.save(text, profileID: profileID, host: host)
    }

    func delete() {
        debounce?.cancel()
        SiteStyles.shared.preview = nil
        SiteStyles.shared.delete(profileID: profileID, host: host)
    }
}

/// View › Edit Site Style…: on for a regular window's tab showing an http(s) page.
enum SiteStyleEditorPresenter {
    static func canEdit(in browser: BrowserState?) -> Bool {
        guard let browser, !browser.isIncognito, browser.activeTab != nil else { return false }
        return SiteStyles.hostKey(browser.activeURL) != nil
    }

    static func present(in browser: BrowserState?) {
        guard let browser, canEdit(in: browser), let window = browser.window, window.attachedSheet == nil,
              let host = SiteStyles.hostKey(browser.activeURL) else { return }
        let target: SiteStyleTarget
        #if BOAZ_CHROMIUM
        if let page = browser.activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
            target = SiteStyleTarget(profileID: page.profile.id)
            target.chromiumPage = page
        } else {
            target = SiteStyleTarget(profileID: SiteStyles.profileKey(browser.activeTab?.profileID))
            target.webPage = browser.activePage
        }
        #else
        target = SiteStyleTarget(profileID: SiteStyles.profileKey(browser.activeTab?.profileID))
        target.webPage = browser.activePage
        #endif
        let model = MacModel.shared
        let profiles = model.sidebar.profiles
        let name = profiles.count > 1 ? profiles.first { $0.id == target.profileID }?.name : nil
        let draft = SiteStyleDraft(host: host, profileID: target.profileID, profileName: name, target: target)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentViewController = NSHostingController(rootView: SiteStyleEditor(draft: draft) { [weak window, weak sheet] in
            if let sheet { window?.endSheet(sheet) }
        })
        sheet.setContentSize(NSSize(width: 560, height: 440))
        window.beginSheet(sheet)
    }
}

/// The editor sheet: three presets that add to the text, the CSS, and Save, Cancel and Delete Style.
struct SiteStyleEditor: View {
    @Bindable var draft: SiteStyleDraft
    let close: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Site Style").font(.headline)
                Text(draft.profileName.map { "\(draft.host) · \($0)" } ?? draft.host)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.m) {
                ForEach(SiteStylePreset.allCases) { preset in
                    Button(preset.title) { draft.add(preset) }
                        .buttonStyle(.bordered)
                        .disabled(preset.isApplied(in: draft.text))
                }
            }
            CSSTextView(draft: draft, onCancel: cancel)
                .frame(minHeight: 200)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("Type CSS, or start from a preset above")
                            .font(.system(.body, design: .monospaced)).foregroundStyle(.tertiary)
                            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            Text(caption).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("siteStyle.caption")
            HStack {
                if draft.hasSavedStyle {
                    Button("Delete Style", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                // ⌘S, not Return: Return types a newline in the CSS.
                Button("Save") {
                    draft.save()
                    close()
                }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 560, height: 440)
        .alert("Delete the style for \(draft.host)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                draft.delete()
                close()
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.siteStyleEditor")
    }

    private var caption: String {
        switch draft.notice {
        case .tooLong: "Too long to save (32 KB max)"
        case .full: "You have \(SiteStyleBook.maxSites) site styles. Delete one in Settings to add another."
        case .leftHost: "This tab left \(draft.host). Save still applies to the site."
        case .blocked: "This site blocks added styles, so this one can't show here."
        case .none:
            draft.target == nil ? "Saved changes apply to open pages of this site."
                : "Changes show on this page as you type. Rules the browser can't read are skipped."
        }
    }

    private func cancel() {
        draft.cancel()
        close()
    }
}

/// A plain monospaced text view: no spelling, autocorrect, smart quotes or dashes, which would break CSS.
private struct CSSTextView: NSViewRepresentable {
    let draft: SiteStyleDraft
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(draft: draft, onCancel: onCancel) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: Spacing.xs, height: Spacing.s)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.string = draft.text
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("siteStyle.css")
        textView.setAccessibilityLabel("CSS")
        draft.textView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let draft: SiteStyleDraft
        let onCancel: () -> Void
        init(draft: SiteStyleDraft, onCancel: @escaping () -> Void) {
            self.draft = draft
            self.onCancel = onCancel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            draft.text = textView.string
        }

        /// Esc in a text view would offer completions; here it cancels, like the sheet's Cancel.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            onCancel()
            return true
        }
    }
}

/// Settings › Site Styles: every saved style, with Edit (no preview) and Delete. The escape hatch for a page a
/// style made unreadable.
struct SiteStylesSettings: View {
    @Environment(MacModel.self) private var model
    @State private var editing: SiteStyleDraft?
    @State private var deleting: SiteStyle?

    private var styles: [SiteStyle] {
        let profiles = Set(model.sidebar.profiles.map(\.id))
        return SiteStyles.shared.book.styles
            .filter { profiles.isEmpty || profiles.contains($0.profileID) || $0.profileID == "default" }
            .sorted { ($0.host, $0.profileID) < ($1.host, $1.profileID) }
    }

    private func profileName(_ id: String) -> String? {
        model.sidebar.profiles.count > 1 ? model.sidebar.profiles.first { $0.id == id }?.name : nil
    }

    var body: some View {
        Form {
            Section {
                Text("Your CSS for a site, applied every time it loads. To add one, open the site and choose View › Edit Site Style….")
                    .font(.caption).foregroundStyle(.secondary)
                if styles.isEmpty {
                    Text("No site styles").foregroundStyle(.secondary)
                }
                ForEach(styles, id: \.self) { style in
                    LabeledContent {
                        Button {
                            editing = SiteStyleDraft(host: style.host, profileID: style.profileID,
                                                     profileName: profileName(style.profileID), target: nil)
                        } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit \(style.host)")
                        .accessibilityIdentifier("siteStyles.edit.\(style.host)")
                        Button(role: .destructive) { deleting = style } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(style.host)")
                            .accessibilityIdentifier("siteStyles.delete.\(style.host)")
                    } label: {
                        Text(style.host)
                        Text([profileName(style.profileID),
                              "Edited \(style.updatedAt.formatted(.relative(presentation: .named)))"]
                            .compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { SiteStyles.shared.keepProfiles(Set(model.sidebar.profiles.map(\.id))) }
        .sheet(item: $editing) { draft in SiteStyleEditor(draft: draft) { editing = nil } }
        .alert("Delete the style for \(deleting?.host ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { SiteStyles.shared.delete(profileID: deleting.profileID, host: deleting.host) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }
}
