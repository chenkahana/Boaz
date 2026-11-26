import BoazKit
import SwiftUI

/// What the extension shows, and what it hands back to iOS.
@Observable final class AutoFillModel {
    enum Screen { case blank, list, configuration }
    enum Passwords { case locked, unlocked([SavedPassword]), unreadable }

    /// Blank while iOS asks for Face ID on the way to filling a suggestion: there's nothing else to show.
    var screen = Screen.blank
    var passwords = Passwords.locked
    /// The app or site asking, most specific first.
    var urls: [URL] = []
    var search = ""
    private(set) var authenticating = false

    @ObservationIgnored var fill: (SavedPassword, String) -> Void = { _, _ in }
    @ObservationIgnored var cancel: () -> Void = {}
    @ObservationIgnored var finishConfiguration: () -> Void = {}

    func showList(for urls: [URL]) {
        self.urls = urls
        screen = .list
    }

    func unlock() async {
        guard !authenticating, case .locked = passwords else { return }
        authenticating = true
        defer { authenticating = false }
        guard await DeviceOwner.authenticate("show your saved passwords") else { return }
        do {
            let all = try SavedPasswords.all()
            passwords = .unlocked(all)
            await AutoFillIdentities.replace(with: all)
        } catch {
            passwords = .unreadable
        }
    }

    func pick(_ entry: SavedPassword) {
        guard let password = try? SavedPasswords.password(for: entry) else {
            passwords = .unreadable
            return
        }
        fill(entry, password)
    }
}

struct AutoFillRootView: View {
    let model: AutoFillModel

    var body: some View {
        switch model.screen {
        case .blank: Color.clear
        case .list: PasswordList(model: model)
        case .configuration: ConfigurationDone(done: model.finishConfiguration)
        }
    }
}

/// The key above the keyboard, then Boaz: the site's sign-ins first, then every one, behind Face ID.
private struct PasswordList: View {
    @Bindable var model: AutoFillModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Boaz Passwords")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: model.cancel) }
                }
        }
        .task { await model.unlock() }
    }

    @ViewBuilder private var content: some View {
        switch model.passwords {
        case .locked:
            ContentUnavailableView {
                Label("Boaz Passwords Are Locked", systemImage: "lock.fill")
            } actions: {
                Button("Unlock…") { Task { await model.unlock() } }
                    .disabled(model.authenticating)
            }
        case .unreadable:
            ContentUnavailableView {
                Label("Can't Read Passwords", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Boaz couldn't read your passwords. Open Boaz and try again.")
            }
        case .unlocked(let all) where all.isEmpty:
            ContentUnavailableView("No Saved Passwords", systemImage: "key",
                                   description: Text("Passwords you save in Boaz on your iPhone or Mac show up here."))
        case .unlocked(let all):
            let shown = all.matching(model.search)
            let found = Set(shown.map(\.id))
            let forSite = all.offered(at: model.urls).filter { found.contains($0.id) }
            List {
                if !forSite.isEmpty, let host = model.urls.first?.host() {
                    Section("For \(host)") { rows(forSite) }
                }
                if !shown.isEmpty {
                    Section("All Passwords") { rows(shown) }
                }
            }
            .searchable(text: $model.search, placement: .navigationBarDrawer(displayMode: .always))
            .overlay {
                if shown.isEmpty { ContentUnavailableView("No Matches", systemImage: "magnifyingglass") }
            }
        }
    }

    private func rows(_ entries: [SavedPassword]) -> some View {
        ForEach(entries) { entry in
            Button { model.pick(entry) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.username.isEmpty ? "No username" : entry.username).lineLimit(1)
                        Text(entry.site).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Fill \(entry.username) for \(entry.site)")
        }
    }
}

/// Shown once, when the user turns Boaz on for AutoFill in Settings.
private struct ConfigurationDone: View {
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Boaz Passwords Are On", systemImage: "key.fill")
            } description: {
                Text("Pick Boaz from the key above the keyboard to fill a password.")
            } actions: {
                Button("Done", action: done).buttonStyle(.borderedProminent)
            }
        }
    }
}
