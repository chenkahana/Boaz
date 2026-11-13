#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumFindBar: View {
    let adapter: ChromiumEnginePageAdapter
    let close: () -> Void
    @State private var query = ""
    @State private var error: String?
    @State private var searching = false
    @State private var submitted = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Find in page", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Find in page")
                    .focused($focused)
                    .onKeyPress(keys: [.return], phases: .down) { event in
                        find(forward: !event.modifiers.contains(.shift))
                        return .handled
                    }
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(status)
                Button { find(forward: false) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Previous match").help("Previous match")
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(query.isEmpty || adapter.state.lifecycle != .active)
                Button { find(forward: true) } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Next match").help("Next match")
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(query.isEmpty || adapter.state.lifecycle != .active)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .accessibilityLabel("Close find bar").help("Close find bar")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityLabel(error) }
        }
        .padding(8)
        .background(.regularMaterial)
        .onExitCommand(perform: dismiss)
        .onAppear { focused = true }
        .task(id: query) {
            guard query != submitted else { return }
            error = nil
            searching = !query.isEmpty
            do {
                try adapter.stopFinding()
                guard !query.isEmpty else { submitted = ""; searching = false; return }
                try await Task.sleep(for: .milliseconds(150))
                try Task.checkCancellation()
                find(forward: true)
            } catch is CancellationError {
                return
            } catch {
                self.error = "The page could not be searched."
                searching = false
            }
        }
        .onChange(of: adapter.state.findFinal) { _, final in
            if final { searching = false }
        }
        .onChange(of: adapter.state.navigationID) { _, _ in
            query = ""
            submitted = ""
            searching = false
            do { try adapter.stopFinding() } catch { self.error = "The previous search could not be cleared." }
        }
        .onChange(of: adapter.state.lifecycle) { _, lifecycle in
            if lifecycle == .closed || lifecycle == .closing { close() }
        }
        .onDisappear { try? adapter.stopFinding() }
    }

    private var status: String {
        if query.isEmpty { return "" }
        if searching || submitted != query || !adapter.state.findFinal { return "Searching…" }
        if adapter.state.findMatchCount == 0 { return "No matches" }
        guard adapter.state.findMatchCount > 0 else { return "Searching…" }
        if adapter.state.findActiveMatch > 0 {
            return "\(adapter.state.findActiveMatch) of \(adapter.state.findMatchCount)"
        }
        return "\(adapter.state.findMatchCount) matches"
    }
    private func find(forward: Bool) {
        guard !query.isEmpty else { return }
        do {
            searching = true
            try adapter.find(text: query, forward: forward)
            submitted = query
            error = nil
        } catch {
            self.error = "The page could not be searched."
            searching = false
        }
    }
    private func dismiss() {
        do { try adapter.stopFinding() }
        catch { self.error = "The search could not be cleared." }
        close()
    }
}
#endif
