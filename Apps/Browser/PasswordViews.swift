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
    @State private var unlocked = false
    @State private var search = ""
    @State private var revealed: (id: SavedPassword.ID, password: String)?
    @State private var importing = false
    @State private var message: String?

    private var autofill: PasswordAutofill { .shared }

    private var shown: [SavedPassword] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return autofill.saved
            .filter { query.isEmpty || $0.site.contains(query) || $0.username.lowercased().contains(query) }
            .sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    var body: some View {
        Form {
            if unlocked {
                Section {
                    Button("Import Passwords from a CSV File…") { importing = true }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    Text("Export your passwords as a CSV file from Chrome, Edge, Brave, Arc, Firefox, Safari or the Passwords app, then choose it here. The file isn't encrypted: delete it once it's imported.")
                }
                Section("Saved Passwords") {
                    #if os(macOS)
                    TextField("Search", text: $search)
                    #endif
                    if shown.isEmpty {
                        Text(search.isEmpty ? "No saved passwords" : "No matches").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { entry in row(entry) }
                        .onDelete { offsets in offsets.map { shown[$0] }.forEach(delete) }
                }
            } else {
                Section {
                    Label("Passwords are locked", systemImage: "lock.fill")
                    Button("Unlock…") { Task { await unlock() } }
                } footer: {
                    Text("Boaz offers saved passwords on the sites they belong to. On iPhone, the key above the keyboard also opens the passwords in Apple's Passwords.")
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .searchable(text: $search)
        .navigationTitle("Passwords")
        #endif
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            Task { await importFile(result) }
        }
        .task { await unlock() }
        .onDisappear {
            unlocked = false
            revealed = nil
        }
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
            Button(role: .destructive) { delete(entry) } label: { Image(systemName: "trash") }
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
                : "Imported \(count) password\(count == 1 ? "" : "s")\(updated > 0 ? ", \(updated) of them updated" : "")."
        } catch {
            message = error.localizedDescription
        }
    }
}
