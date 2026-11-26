import BoazKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The saved sign-ins for the focused login field, under it (above it when there's no room below). Lay it over the
/// web view, in the web view's own coordinates.
struct PasswordSuggestions: View {
    let tabID: String
    let page: WebPage

    private static let rowHeight = 40.0

    var body: some View {
        GeometryReader { proxy in
            if let field = PasswordAutofill.shared.field, field.tabID == tabID {
                let scale = proxy.size.width / field.viewportWidth
                let rows = Array(field.suggestions.prefix(5))
                let width = min(max(field.rect.width * scale, 260), proxy.size.width - 16)
                let height = Double(rows.count) * Self.rowHeight + 8
                let below = field.rect.maxY * scale + 4
                let y = below + height <= proxy.size.height ? below : max(8, field.rect.minY * scale - 4 - height)
                VStack(spacing: 0) {
                    ForEach(rows) { entry in
                        SuggestionRow(entry: entry, height: Self.rowHeight) {
                            Task { await PasswordAutofill.shared.fill(entry, on: page) }
                        }
                    }
                }
                .padding(4)
                .frame(width: width)
                .background(.regularMaterial, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .offset(x: min(max(field.rect.minX * scale, 8), proxy.size.width - width - 8), y: y)
            }
        }
    }
}

private struct SuggestionRow: View {
    let entry: SavedPassword
    let height: Double
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.username.isEmpty ? "No username" : entry.username).lineLimit(1)
                    Text(entry.site).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(hovered ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Fill \(entry.username) for \(entry.site)")
    }
}

/// Asks to keep a sign-in the user just made, or to update the password Boaz has for it.
struct SavePasswordPrompt: View {
    let tabID: String

    var body: some View {
        if let offer = PasswordAutofill.shared.offer, offer.tabID == tabID {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.isUpdate ? "Update the password for \(offer.entry.site)?"
                                            : "Save the password for \(offer.entry.site)?")
                            .font(.headline)
                        if !offer.entry.username.isEmpty {
                            Text(offer.entry.username).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text("Boaz keeps it in your iCloud Keychain and offers it when you sign in again.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(.tint)
                }
                HStack {
                    Spacer()
                    Button("Not Now") { PasswordAutofill.shared.offer = nil }
                    Button(offer.isUpdate ? "Update" : "Save") { PasswordAutofill.shared.save(offer) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(maxWidth: 380)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .padding(12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Settings › Passwords: the saved sign-ins, shown once the user authenticates, with import from another browser.
struct PasswordsSettings: View {
    /// Signed out of iCloud on this device, so new passwords can't sync (`LibrarySync.Status.signedOut`).
    var signedOutOfICloud = false

    @State private var unlocked = false
    @State private var search = ""
    @State private var revealed: (id: SavedPassword.ID, password: String)?
    @State private var importing = false
    @State private var message: String?
    /// Kept after the alert closes, so its title doesn't change while it animates away.
    @State private var deleting: SavedPassword?
    @State private var confirmingDelete = false

    private var autofill: PasswordAutofill { .shared }

    private var shown: [SavedPassword] { autofill.saved.matching(search) }

    var body: some View {
        Form {
            #if AUTOFILL_EXTENSION
            AutoFillSection()
            #endif
            if unlocked {
                Section {
                    Button("Import Passwords from a CSV File…") { importing = true }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    Text("Export your passwords as a CSV file from Chrome, Edge, Brave, Arc, Firefox, Safari or the Passwords app, then choose it here. The file isn't encrypted: delete it once it's imported.")
                }
                Section {
                    #if os(macOS)
                    TextField("Search", text: $search)
                    #endif
                    if shown.isEmpty {
                        Text(search.isEmpty ? "No saved passwords" : "No matches").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { entry in row(entry) }
                        .onDelete { offsets in if let first = offsets.first { confirmDelete(shown[first]) } }
                } header: {
                    Text("Saved Passwords")
                } footer: {
                    syncFooter
                }
            } else {
                Section {
                    Label("Passwords are locked", systemImage: "lock.fill")
                    Button("Unlock…") { Task { await unlock() } }
                } footer: {
                    #if AUTOFILL_EXTENSION
                    Text("Boaz offers saved passwords on the sites they belong to. To use them in other apps, turn on Use Boaz Passwords in Other Apps.")
                    #else
                    Text("Boaz offers saved passwords on the sites they belong to.")
                    #endif
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .searchable(text: $search)
        .navigationTitle("Passwords")
        #endif
        // Deleting reaches every device through iCloud Keychain, and can't be undone: ask once.
        .alert("Delete the password for \(deleting?.site ?? "")?", isPresented: $confirmingDelete,
               presenting: deleting) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from Boaz on all your devices.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            Task { await importFile(result) }
        }
        // Not under UI tests (`-BoazUITest YES`): a system authentication prompt would wait for whoever is at the Mac.
        .task { if !UserDefaults.standard.bool(forKey: "BoazUITest") { await unlock() } }
        .onDisappear {
            unlocked = false
            revealed = nil
        }
    }

    /// Boaz can't see whether iCloud Keychain is on, so it states the rule instead of a status.
    @ViewBuilder private var syncFooter: some View {
        #if os(iOS)
        if signedOutOfICloud {
            Text("Boaz keeps your passwords in your iCloud Keychain. With iCloud Keychain on, they reach Boaz on your other devices; with it off, they stay on this iPhone.\n\nYou're signed out of iCloud, so new passwords stay on this iPhone.")
        } else {
            Text("Boaz keeps your passwords in your iCloud Keychain. With iCloud Keychain on, they reach Boaz on your other devices; with it off, they stay on this iPhone.")
        }
        #else
        if signedOutOfICloud {
            Text("Boaz keeps your passwords in your iCloud Keychain. With iCloud Keychain on, they reach Boaz on your other devices; with it off, they stay on this Mac.\n\nYou're signed out of iCloud, so new passwords stay on this Mac.")
        } else {
            Text("Boaz keeps your passwords in your iCloud Keychain. With iCloud Keychain on, they reach Boaz on your other devices; with it off, they stay on this Mac.")
        }
        #endif
    }

    private func row(_ entry: SavedPassword) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.site)
                Text(entry.username.isEmpty ? "No username" : entry.username)
                    .font(.caption).foregroundStyle(.secondary)
                if let revealed, revealed.id == entry.id {
                    Text(revealed.password).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            Spacer()
            Button {
                if revealed?.id == entry.id {
                    revealed = nil
                } else if let password = try? SavedPasswords.password(for: entry) {
                    revealed = (entry.id, password)
                }
            } label: {
                Image(systemName: revealed?.id == entry.id ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(revealed?.id == entry.id ? "Hide Password" : "Show Password")
            #if os(macOS)
            Button(role: .destructive) { confirmDelete(entry) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete")
            #endif
        }
    }

    private func unlock() async {
        guard !unlocked else { return }
        unlocked = await PasswordAutofill.authenticate("show your saved passwords")
        if unlocked { autofill.reload() }
    }

    private func confirmDelete(_ entry: SavedPassword) {
        deleting = entry
        confirmingDelete = true
    }

    private func delete(_ entry: SavedPassword) {
        do {
            try autofill.delete(entry)
            if revealed?.id == entry.id { revealed = nil }
        } catch {
            message = error.localizedDescription
        }
    }

    private func importFile(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let items = try PasswordCSV.read(String(contentsOf: url, encoding: .utf8))
            let (added, updated) = try await Task.detached { try SavedPasswords.save(items) }.value
            autofill.reload()
            let count = added + updated
            message = items.isEmpty ? "The file has no website passwords."
                : count == 0 ? "Boaz already has all \(items.count) of these passwords."
                : String(inflecting: "Imported ^[\(count) password](inflect: true)") + (updated > 0 ? ", \(updated) of them updated." : ".")
        } catch {
            message = error.localizedDescription
        }
    }
}
