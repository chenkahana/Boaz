import BoazKit
import SwiftUI
import WebKit

/// The rail's "…" panel: the page's address, Back / Forward / Reload / Share, then everything the page offers
/// (pin, find, reader, text size, desktop site…) and its website settings inline. Shown in a `BottomPanel`.
struct PageSettingsPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.chromeTint) private var tint
    let tab: SidebarItem
    let page: WebPage
    /// The address the page failed to load, which Reload retries as Try Again does.
    let failedURL: URL?
    let readableLength: Int
    let onReader: () -> Void
    let onDownloads: () -> Void
    let onFind: () -> Void
    let onTranslate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5).padding(.top, 8)
            addressRow.padding(.horizontal, 16).padding(.top, 8)
            navigationRow.padding(.horizontal, 12).padding(.vertical, 12)
            ScrollView {
                VStack(spacing: 12) {
                    group { pageActions }
                    group { PageAIMenuItems(tab: tab) }
                        .simultaneousGesture(TapGesture().onEnded(close))
                    group {
                        TextSizeRow(page: page, isPrivate: model.isPrivate(tab))
                        Divider().padding(.leading, 52)
                        DesktopSiteRow(page: page, host: settingsHost, isPrivate: model.isPrivate(tab))
                    }
                    if let settingsHost {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Website Settings · \(settingsHost)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                            group { WebsiteSettingsRows(host: settingsHost, isPrivate: model.isPrivate(tab)) }
                                .id(settingsHost)
                        }
                    }
                    group { tabActions }
                    group { HomeMenuItems() }
                        .simultaneousGesture(TapGesture().onEnded(close))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .buttonStyle(PanelRowStyle())
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Rows scrolling past the panel's rounded bottom corners stay inside them.
        .clipShape(.rect(cornerRadius: BottomPanelStyle.cornerRadius))
        // A named container: the label mustn't replace each row's own.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page Settings")
    }

    // MARK: Header

    /// The site and its title; tap to edit the address.
    private var addressRow: some View {
        Button {
            close()
            model.beginSearch(.currentTab)
        } label: {
            HStack(spacing: 12) {
                Monogram(url: page.url ?? tab.url, tint: Theme.brand, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        if page.url?.scheme == "https" { Image(systemName: "lock.fill").imageScale(.small) }
                        Text(host).lineLimit(1)
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "pencil").font(.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Address")
        .accessibilityValue(host)
        .accessibilityHint("Edit address or search")
    }

    private var navigationRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(backList.reversed()) { item in
                    Button(item.title?.isEmpty == false ? item.title! : item.url.host() ?? item.url.absoluteString) {
                        _ = page.load(item)
                    }
                }
            } label: {
                NavTile(symbol: "chevron.backward", title: "Back")
            } primaryAction: {
                if let previous = backList.last { _ = page.load(previous) }
            }
            .disabled(backList.isEmpty)
            Menu {
                ForEach(forwardList) { item in
                    Button(item.title?.isEmpty == false ? item.title! : item.url.host() ?? item.url.absoluteString) {
                        _ = page.load(item)
                    }
                }
            } label: {
                NavTile(symbol: "chevron.forward", title: "Forward")
            } primaryAction: {
                if let next = forwardList.first { _ = page.load(next) }
            }
            .disabled(forwardList.isEmpty)
            Button {
                if page.isLoading { page.stopLoading() } else { page.reload(tabURL: failedURL ?? tab.url) }
            } label: {
                NavTile(symbol: page.isLoading ? "xmark" : "arrow.clockwise", title: page.isLoading ? "Stop" : "Reload")
            }
            if let url = page.url {
                ShareLink(item: url) { NavTile(symbol: "square.and.arrow.up", title: "Share") }
            } else {
                NavTile(symbol: "square.and.arrow.up", title: "Share").disabled(true)
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Rows

    @ViewBuilder private var pageActions: some View {
        Button(model.isPinned(tab) ? "Unpin" : "Pin", systemImage: model.isPinned(tab) ? "pin.slash" : "pin") {
            model.togglePin(tab)
        }
        if !model.isPrivate(tab), !model.isFavorite(tab) {
            Button("Add to Favorites", systemImage: "star") { model.addToFavorites(tab) }
        }
        Button("Find on Page", systemImage: "text.magnifyingglass") { closeThen(onFind) }
        Button("Reader", systemImage: "doc.text.magnifyingglass") { closeThen(onReader) }
            .disabled(readableLength < Reader.minimumCharacters)
        Button(PageSpeech.shared.isSpeaking ? "Stop Listening" : "Listen to Page",
               systemImage: PageSpeech.shared.isSpeaking ? "stop.circle" : "speaker.wave.2", action: toggleListening)
            .disabled(!PageSpeech.shared.isSpeaking && readableLength < Reader.minimumCharacters)
        Button("Translate", systemImage: "translate") { closeThen(onTranslate) }
        Button("Print", systemImage: "printer") { closeThen { Task { await PagePrint.present(page) } } }
        if let url = page.url {
            Button("Copy Link", systemImage: "link") {
                UIPasteboard.general.url = url
                model.showToast("Link copied")
            }
        }
        Button("Downloads", systemImage: "arrow.down.circle") { closeThen(onDownloads) }
    }

    @ViewBuilder private var tabActions: some View {
        Button("Reopen Closed Tab", systemImage: "arrow.uturn.backward") { closeThen(model.undoClose) }
            .disabled(!model.canReopenClosedTab)
        Button("Archive Tab", systemImage: "archivebox") { closeThen { model.close(tab) } }
    }

    private func group(@ViewBuilder _ rows: () -> some View) -> some View {
        VStack(spacing: 0) { rows() }
            .background(.background.opacity(0.55), in: .rect(cornerRadius: 18))
    }

    // MARK: Actions

    private func close() {
        withAnimation(BottomPanelStyle.motion) { model.showsPageSettings = false }
    }

    private func closeThen(_ action: @escaping () -> Void) {
        close()
        action()
    }

    private func toggleListening() {
        if PageSpeech.shared.isSpeaking {
            PageSpeech.shared.stop()
        } else {
            Task {
                guard let article = await Reader.extract(from: page) else { return }
                PageSpeech.shared.speak(article)
            }
        }
    }

    private var backList: [WebPage.BackForwardList.Item] { page.backForwardList.backList }
    private var forwardList: [WebPage.BackForwardList.Item] { page.backForwardList.forwardList }
    /// The host `PageSettings` and `PageZoom` key choices by; nil for a page with no address yet.
    private var settingsHost: String? { page.url?.host() ?? tab.url?.host() }
    private var host: String { settingsHost ?? "New Tab" }
    private var title: String {
        if !page.title.isEmpty { return page.title }
        return tab.title ?? host
    }
}

/// One of the four navigation buttons across the top of the panel.
private struct NavTile: View {
    @Environment(\.isEnabled) private var isEnabled
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.body.weight(.semibold)).contentTransition(.symbolEffect(.replace))
            Text(title).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.background.opacity(0.55), in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// A full-width row: icon, then title. Dims when disabled.
private struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelRow(configuration: configuration)
    }

    private struct PanelRow: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration

        var body: some View {
            configuration.label
                .labelStyle(PanelLabelStyle())
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .contentShape(.rect)
                .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

private struct PanelLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
                .font(.body.weight(.medium))
                .frame(width: 22)
            configuration.title
                .font(.body)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
    }
}

/// Text size as an inline stepper: smaller, the current size (tap to reset), larger.
private struct TextSizeRow: View {
    let page: WebPage
    let isPrivate: Bool
    @State private var level: Double = 1

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "textformat.size").font(.body.weight(.medium)).frame(width: 22)
            Text("Text Size")
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                step("textformat.size.smaller", label: "Make Text Smaller", .out)
                Button { zoom(.reset) } label: {
                    Text(level, format: .percent.precision(.fractionLength(0)))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .frame(minWidth: 56, minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset Text Size")
                .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
                step("textformat.size.larger", label: "Make Text Larger", .in)
            }
            .background(.primary.opacity(0.07), in: .capsule)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 50)
        .onAppear(perform: refresh)
        .onChange(of: page.url) { refresh() }
    }

    private func step(_ symbol: String, label: String, _ change: PageZoom.Change) -> some View {
        Button { zoom(change) } label: {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 36).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func zoom(_ change: PageZoom.Change) {
        PageZoom.change(change, for: page, isPrivate: isPrivate)
        refresh()
    }

    private func refresh() { level = PageZoom.level(for: page.url, isPrivate: isPrivate) }
}

/// Desktop or mobile site for this host. The reload goes through `BoazNavigationDecider`, which picks the
/// user agent and content mode.
private struct DesktopSiteRow: View {
    let page: WebPage
    let host: String?
    let isPrivate: Bool
    @State private var desktop = false

    var body: some View {
        Toggle(isOn: Binding(get: { desktop }, set: set)) {
            Label("Desktop Website", systemImage: "desktopcomputer").labelStyle(PanelLabelStyle())
        }
        .disabled(host == nil)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: 50)
        .onAppear { desktop = PageSettings.settings(forHost: host, isPrivate: isPrivate).desktopSite }
        .onChange(of: host) { desktop = PageSettings.settings(forHost: host, isPrivate: isPrivate).desktopSite }
    }

    private func set(_ on: Bool) {
        desktop = on
        PageSettings.update(forHost: host, isPrivate: isPrivate) { $0.desktopSite = on }
        _ = page.reload()
    }
}

/// Permissions, pop-ups and content blocking for the current host.
private struct WebsiteSettingsRows: View {
    let host: String
    let isPrivate: Bool
    @State private var settings: PageSettings.HostSettings

    init(host: String, isPrivate: Bool) {
        self.host = host
        self.isPrivate = isPrivate
        _settings = State(initialValue: PageSettings.settings(forHost: host, isPrivate: isPrivate))
    }

    var body: some View {
        VStack(spacing: 0) {
            picker("Camera", systemImage: "camera", selection: $settings.camera, PageSettings.Permission.allCases)
            divider
            picker("Microphone", systemImage: "mic", selection: $settings.microphone, PageSettings.Permission.allCases)
            divider
            picker("Pop-ups", systemImage: "macwindow.on.rectangle", selection: $settings.popups,
                   PageSettings.PopupPolicy.allCases)
            divider
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: $settings.contentBlocking) {
                    Label("Content Blocking", systemImage: "shield.lefthalf.filled").labelStyle(PanelLabelStyle())
                }
                Text("Applies the next time this site opens in a new tab.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 36)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        .onChange(of: settings) { _, new in
            PageSettings.update(forHost: host, isPrivate: isPrivate) { $0 = new }
        }
    }

    private var divider: some View { Divider().padding(.leading, 52) }

    private func picker<Option: Hashable & Identifiable>(_ title: String, systemImage: String, selection: Binding<Option>,
                                                         _ options: [Option]) -> some View
        where Option: PageSettingsOption {
        HStack(spacing: 14) {
            Label(title, systemImage: systemImage).labelStyle(PanelLabelStyle())
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                ForEach(options) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
    }
}

/// A website setting's choices, as the panel's pickers list them.
private protocol PageSettingsOption { var label: String { get } }
extension PageSettings.Permission: PageSettingsOption {}
extension PageSettings.PopupPolicy: PageSettingsOption {}
