import AppKit
import BoazKit
import SwiftUI

/// The GitHub mark, tinted like text.
struct GitHubMark: View {
    var size: CGFloat = 16

    var body: some View {
        Image("GitHubMark").renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// An emoji or SF Symbol name, as space and folder icons store them.
struct IconGlyph: View {
    let icon: String
    var size: CGFloat = 14

    static func isSymbol(_ icon: String) -> Bool {
        icon.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
    }

    var body: some View {
        if Self.isSymbol(icon) {
            Image(systemName: icon).font(.system(size: size * 0.9, weight: .medium))
        } else {
            Text(icon).font(.system(size: size))
        }
    }
}

/// A folder row's icon: its own, the GitHub mark for a Pull Requests folder, else the folder glyph (filled while open).
struct FolderGlyph: View {
    let folder: SidebarItem

    var body: some View {
        if let icon = folder.icon {
            IconGlyph(icon: icon, size: 14)
        } else if folder.liveSource?.provider == LiveSource.githubPulls {
            GitHubMark(size: 15)
        } else {
            Image(systemName: folder.isExpanded ? "folder.fill" : "folder").font(.system(size: 13, weight: .medium))
        }
    }
}

/// A live folder tab's icon: the GitHub mark with its checks' badge.
struct LivePullIcon: View {
    let status: LiveFolderState.ItemStatus?

    var body: some View {
        GitHubMark(size: 16)
            .overlay(alignment: .bottomTrailing) { badge.offset(x: 4, y: 4) }
            .accessibilityElement()
            .accessibilityLabel(Self.label(status))
            .accessibilityIdentifier(Self.identifier(status))
    }

    /// The row's button is what accessibility reaches (it takes in this icon), so it carries these as well.
    static func identifier(_ status: LiveFolderState.ItemStatus?) -> String {
        "sidebar.livePull.checks.\(status?.checks?.rawValue ?? "none")"
    }

    @ViewBuilder private var badge: some View {
        switch status?.checks {
        case .success:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 9, weight: .bold))
                .symbolRenderingMode(.palette).foregroundStyle(.white, .green)
        case .failure:
            Image(systemName: "xmark.circle.fill").font(.system(size: 9, weight: .bold))
                .symbolRenderingMode(.palette).foregroundStyle(.white, .red)
        case .pending:
            Circle().fill(.yellow).frame(width: 7, height: 7).overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        case nil:
            EmptyView()
        }
    }

    static func label(_ status: LiveFolderState.ItemStatus?) -> String {
        switch status?.checks {
        case .success: "Checks passed"
        case .failure: "Checks failed"
        case .pending: "Checks running"
        case nil: "Pull request"
        }
    }
}

/// The sidebar `+` menu's and the space menu's New Live Folder submenu.
struct NewLiveFolderMenu: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let space: Space

    var body: some View {
        Menu("New Live Folder") {
            Button("GitHub Pull Requests") { LiveFolders.newPullRequestsFolder(in: space, model: model, browser: browser) }
        }
    }
}

@MainActor
enum LiveFolders {
    /// Makes a Pull Requests folder in `space`'s Pinned, signing in to GitHub first if needed.
    static func newPullRequestsFolder(in space: Space, model: MacModel, browser: BrowserState) {
        let make = {
            guard let folder = withAnimation(SidebarStyle.motion, { model.newLiveFolder(in: space) }) else { return }
            if GitHubAuth.shared.isSignedIn { model.showToast("Added \(folder.title ?? "Pull Requests")") }
        }
        guard GitHubAuth.shared.isSignedIn else {
            GitHubAuth.shared.onNextSignIn = {
                make()
                model.showToast("Signed in to GitHub\(GitHubAuth.shared.viewer.map { " as @\($0.login)" } ?? "")")
            }
            browser.githubSignIn = .init(spaceID: space.id)
            return
        }
        make()
    }
}

/// A folder's context menu: for a live folder, Arc's (its source's submenu first); for any folder, Move to, Copy All
/// Links, Change Icon…, Rename… and Delete.
struct FolderMenu: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let folder: SidebarItem
    let changeIcon: () -> Void

    var body: some View {
        let live = folder.liveSource?.provider == LiveSource.githubPulls
        if live {
            Menu {
                PullRequestsMenu(folder: folder)
            } label: {
                Label { Text("Pull Requests") } icon: { Image("GitHubMark").renderingMode(.template) }
            }
            .accessibilityIdentifier("control.liveFolder.menu")
        } else {
            Button(folder.isExpanded ? "Collapse" : "Expand") { model.toggleExpanded(folder) }
            if model.container(of: folder)?.containerKind == .unpinned { Button("Ungroup") { model.ungroup(folder) } }
        }
        Divider()
        let otherSpaces = model.sidebar.spaces.filter { $0.id != folder.spaceID }
        Menu("Move to") {
            ForEach(otherSpaces) { space in
                Button { withAnimation { model.move(folder, to: space) } } label: {
                    Label { Text(space.title) } icon: { SpaceIcon(space: space) }
                }
            }
        }
        .disabled(otherSpaces.isEmpty || model.container(of: folder)?.containerKind == .favorites)
        Divider()
        Button("Copy All Links") { model.copyAllLinks(in: folder) }
        Divider()
        Button("Change Icon…", action: changeIcon)
        Button(live ? "Rename…" : "Rename Folder…") { browser.rename = .init(target: .item(folder), text: folder.title ?? "") }
        Divider()
        Button(live ? "Delete Live Folder" : "Delete Folder", role: .destructive) { browser.folderToDelete = folder }
    }
}

/// The "Pull Requests ▸" submenu: status, Refresh, the filters, Repositories, Single Sign-On and the account.
private struct PullRequestsMenu: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let folder: SidebarItem

    var body: some View {
        let refresher = LiveFolderRefresher.shared
        let source = folder.liveSource ?? LiveSource(provider: LiveSource.githubPulls)
        let state = refresher.state(of: folder)
        Button(refresher.statusLine(for: folder)) {}.disabled(true)
        Button("Refresh") { refresher.refreshNow() }
            .disabled(!GitHubAuth.shared.isSignedIn)
        Divider()
        ForEach(GitHubPullFilter.allCases, id: \.self) { filter in
            Toggle(filter.title, isOn: Binding {
                source.has(filter.rawValue)
            } set: { enabled in
                model.updateLiveSource(folder) { $0.set(filter.rawValue, enabled: enabled) }
            })
        }
        Divider()
        Menu("Repositories") {
            Toggle("All Repositories", isOn: Binding {
                source.repositories.isEmpty
            } set: { all in
                if all { model.updateLiveSource(folder) { $0.setRepositories([]) } }
            })
            let known = state?.repositories ?? source.repositories
            if !known.isEmpty { Divider() }
            ForEach(known, id: \.self) { repository in
                Toggle(repository, isOn: Binding {
                    source.repositories.contains(repository)
                } set: { selected in
                    model.updateLiveSource(folder) { source in
                        var chosen = Set(source.repositories)
                        if selected { chosen.insert(repository) } else { chosen.remove(repository) }
                        source.setRepositories(Array(chosen))
                    }
                })
            }
        }
        if let organizations = state?.singleSignOn, !organizations.isEmpty {
            Menu("Single Sign-On") {
                ForEach(organizations, id: \.self) { sso in
                    Button("Authorize \(sso.organization)…") { browser.openTab(sso.url) }
                }
            }
        }
        Divider()
        if GitHubAuth.shared.isSignedIn {
            Button("Sign Out of GitHub") { GitHubAuth.shared.signOut() }
        } else {
            Button("Sign In to GitHub…") { browser.githubSignIn = .init() }
        }
    }
}

/// Change Icon…: SF Symbols and emoji for a folder, or one typed in.
struct FolderIconPicker: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let folder: SidebarItem
    @State private var custom = ""

    private static let symbols = [
        "folder", "star", "heart", "bolt", "flag", "bookmark", "tag", "book", "briefcase", "cart",
        "hammer", "wrench.and.screwdriver", "paintbrush", "music.note", "film", "gamecontroller",
        "graduationcap", "airplane", "house", "leaf", "flame", "globe", "terminal", "doc.text",
        "newspaper", "person.2", "calendar", "envelope", "bubble.left", "checkmark.seal",
    ]
    private static let emoji = [
        "📁", "⭐️", "🔥", "🚀", "💡", "📌", "🎯", "🧪", "🛠️", "📚", "🎨", "🎵",
        "🎮", "✈️", "🏠", "🌱", "💼", "🧾", "🐙", "❤️", "✅", "🐛", "📦", "🔒",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change Icon").font(.headline)
            grid(Self.symbols, named: "Symbols") { Image(systemName: $0).font(.system(size: 14)) }
            Divider()
            grid(Self.emoji, named: "Emoji") { Text($0).font(.system(size: 16)) }
            Divider()
            HStack {
                TextField("Emoji or symbol name", text: $custom).textFieldStyle(.roundedBorder).onSubmit(useCustom)
                Button("Use", action: useCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Button("Reset") { set(nil) }.disabled(folder.icon == nil)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.iconPicker")
    }

    private func grid(_ icons: [String], named name: String,
                      @ViewBuilder label: @escaping (String) -> some View) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8), spacing: 6) {
            ForEach(icons, id: \.self) { icon in
                Button { set(icon) } label: {
                    label(icon).frame(width: 28, height: 28)
                        .background(folder.icon == icon ? SidebarStyle.selection() : .clear, in: .rect(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A symbol's name read as words ("wrench and screwdriver"), not "wrench.and.screwdriver".
                .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }

    private func useCustom() {
        let icon = custom.trimmingCharacters(in: .whitespaces)
        guard !icon.isEmpty else { return }
        // A name SF Symbols doesn't have would draw nothing.
        if IconGlyph.isSymbol(icon), NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil { return }
        set(icon)
    }

    private func set(_ icon: String?) {
        model.setIcon(folder, to: icon)
        if icon != nil { dismiss() }
    }
}

/// The sign-in sheet and the folder deletion confirmation, on the sidebar.
struct LiveFolderPresentations: ViewModifier {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser

    func body(content: Content) -> some View {
        @Bindable var browser = browser
        content
            .sheet(item: $browser.githubSignIn) { request in
                GitHubSignInView(request: request) { browser.openTab($0) }
            }
            .confirmationDialog("Delete \"\(browser.folderToDelete?.title ?? "Folder")\"?",
                                isPresented: Binding { browser.folderToDelete != nil } set: { if !$0 { browser.folderToDelete = nil } },
                                titleVisibility: .visible, presenting: browser.folderToDelete) { folder in
                Button(folder.liveSource != nil ? "Delete Live Folder" : "Delete Folder", role: .destructive) {
                    withAnimation(SidebarStyle.motion) { model.deleteFolder(folder) }
                }
            } message: { folder in
                Text(folder.liveSource != nil
                     ? "Its tabs go with it, on all your devices. Your pull requests stay on GitHub."
                     : "Its tabs move to the Archive, on all your devices.")
            }
    }
}
