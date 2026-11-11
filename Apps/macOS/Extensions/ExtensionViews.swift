import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The extension sheets a window shows.
enum ExtensionSheet: Identifiable {
    case manage, webStore(String = ""), confirm(Extensions.PendingInstall)

    var id: String {
        switch self {
        case .manage: "manage"
        case .webStore: "webStore"
        case .confirm(let pending): pending.id.uuidString
        }
    }
}

extension BrowserState {
    /// Load Unpacked… (a folder) or a `.crx`/`.zip` file, into the current space's profile.
    func chooseExtension(folder: Bool) {
        guard let profileID = currentSpace?.profileID else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowedContentTypes = folder ? [] : [.zip, UTType(filenameExtension: "crx") ?? .data]
        panel.message = folder ? "Choose an unpacked extension's folder (the one with manifest.json)"
            : "Choose a Chrome extension (.crx or .zip)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                extensionSheet = .confirm(try await Extensions.shared.prepare(file: url, profileID: profileID))
            } catch {
                model.showToast("Couldn't open the extension: \(error.localizedDescription)")
            }
        }
    }
}

/// Lists what an extension asks for before it's added.
struct ConfirmExtensionView: View {
    @Environment(\.dismiss) private var dismiss
    let pending: Extensions.PendingInstall

    var body: some View {
        let webExtension = pending.webExtension
        let items = webExtension.requestedPermissions.map(Extensions.describe)
            + webExtension.requestedPermissionMatchPatterns.map(Extensions.describe)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let icon = webExtension.icon(for: CGSize(width: 48, height: 48)) {
                    Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \"\(webExtension.displayName ?? "Extension")\"?").font(.headline)
                    if let version = webExtension.displayVersion { Text("Version \(version)").foregroundStyle(.secondary) }
                }
            }
            if let description = webExtension.displayDescription { Text(description).fixedSize(horizontal: false, vertical: true) }
            if !items.isEmpty {
                Text("It can:").font(.subheadline.weight(.semibold))
                ForEach(Array(Set(items)).sorted(), id: \.self) { Label($0, systemImage: "checkmark.shield") }
            }
            if !webExtension.errors.isEmpty {
                Text("Some of its features aren't supported in Boaz and won't work.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Extension") {
                    Task { await Extensions.shared.install(pending) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

#if DIRECT_DISTRIBUTION
/// Install Extension…: a Chrome Web Store address or extension ID.
struct WebStoreInstallView: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Extension").font(.headline)
            Text("Paste the extension's Chrome Web Store address or its ID.")
            TextField("chromewebstore.google.com/detail/…", text: $text).textFieldStyle(.roundedBorder).onSubmit(install)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install", action: install).keyboardShortcut(.defaultAction)
                    .disabled(working || Extensions.webStoreID(in: text) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func install() {
        guard let id = Extensions.webStoreID(in: text), let profileID = browser.currentSpace?.profileID else {
            error = Extensions.InstallError.notAnExtensionID.localizedDescription
            return
        }
        working = true
        Task {
            do {
                let pending = try await Extensions.shared.prepare(webStoreID: id, profileID: profileID)
                // Replaces this sheet with the permission prompt.
                browser.extensionSheet = .confirm(pending)
            } catch {
                self.error = "Couldn't download it: \(error.localizedDescription)"
                working = false
            }
        }
    }
}

/// On an extension's Chrome Web Store page: a native Add to Boaz button over the page.
struct WebStoreBanner: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        if let url = browser.activeURL, url.host() == "chromewebstore.google.com", let id = Extensions.webStoreID(in: url.absoluteString),
           !Extensions.shared.installed.contains(where: { $0.extensionID == id && $0.profileID == browser.currentSpace?.profileID }) {
            Button { browser.extensionSheet = .webStore(id) } label: {
                Label("Add to Boaz", systemImage: "puzzlepiece.extension")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(12)
        }
    }
}
#endif

/// Manage Extensions…: what's installed in this profile, with its switches.
struct ExtensionsManagerView: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    private let extensions = Extensions.shared

    var body: some View {
        let items = extensions.installed.filter { $0.profileID == browser.currentSpace?.profileID }
        VStack(alignment: .leading, spacing: 0) {
            List {
                if items.isEmpty {
                    Text("No extensions in this profile. Add one from the Extensions menu.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        if let icon = extensions.context(item)?.webExtension.icon(for: CGSize(width: 24, height: 24)) {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "puzzlepiece.extension").frame(width: 24, height: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text((item.permissions + item.matchPatterns).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if extensions.context(item)?.optionsPageURL != nil {
                            Button("Options") { extensions.openOptions(item); dismiss() }
                        }
                        Toggle("Enabled", isOn: Binding { item.enabled } set: { extensions.setEnabled($0, for: item) })
                            .labelsHidden().toggleStyle(.switch)
                        Button(role: .destructive) { extensions.remove(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Remove")
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 380)
    }
}

/// The enabled extensions' toolbar buttons, under the address field: icon and badge; a click opens the popup.
struct ExtensionActionsBar: View {
    @Environment(BrowserState.self) private var browser
    private let extensions = Extensions.shared

    var body: some View {
        let _ = extensions.actionsVersion
        let actions = browser.isIncognito ? [] : extensions.actions(profileID: browser.currentSpace?.profileID)
        if !actions.isEmpty {
            HStack(spacing: 4) {
                ForEach(actions, id: \.installed.id) { installed, context in
                    let action = context.action(for: browser.activeTabID.map { extensions.tabRef($0, in: browser) })
                    Button { extensions.performAction(context, in: browser) } label: {
                        Group {
                            if let icon = action?.icon(for: CGSize(width: 16, height: 16)) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "puzzlepiece.extension")
                            }
                        }
                        .frame(width: 28, height: 28)
                        .overlay(alignment: .topTrailing) {
                            if let badge = action?.badgeText, !badge.isEmpty {
                                Text(badge).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 3).background(.red, in: .capsule)
                            }
                        }
                        .background { ActionAnchor(key: context.uniqueIdentifier) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(action?.isEnabled == false)
                    .help(action?.label ?? installed.name)
                    .accessibilityLabel(action?.label ?? installed.name)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Registers the toolbar button's view, which the extension's popup points at.
private struct ActionAnchor: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Extensions.shared.actionAnchors[key] = .init(view: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { Extensions.shared.actionAnchors[key] = .init(view: view) }
}
