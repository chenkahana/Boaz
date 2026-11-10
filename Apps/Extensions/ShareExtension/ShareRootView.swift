import SwiftUI

/// "Add to Boaz" sheet shown by the share extension, styled like the rest of the app.
struct ShareRootView: View {
    @State private var model: ShareModel

    init(context: NSExtensionContext?) {
        _model = State(initialValue: ShareModel(context: context))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                pageSummary

                if !model.spaces.isEmpty {
                    Picker("Space", selection: Binding(
                        get: { model.selectedSpaceID ?? "" },
                        set: { model.selectedSpaceID = $0 }
                    )) {
                        ForEach(model.spaces) { space in Text(space.title).tag(space.id) }
                    }
                    .pickerStyle(.menu)
                    .card()
                }

                Spacer()

                HStack(spacing: 12) {
                    Button { model.save(pinned: true) } label: {
                        Label("Pin", systemImage: "pin.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button { model.save(pinned: false) } label: {
                        Label("Add to Today", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                .tint(Theme.brand)
                .disabled(model.pageURL == nil || model.selectedSpaceID == nil || model.didSave)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(20)
            .navigationTitle("Add to Boaz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
            }
            .overlay {
                if model.didSave {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white, Theme.brand)
                        .symbolEffect(.bounce, options: .nonRepeating, value: model.didSave)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Added to Boaz")
                }
            }
            .animation(.snappy, value: model.didSave)
            .sensoryFeedback(.success, trigger: model.didSave) { _, saved in saved }
            // Hold the checkmark briefly so the save reads as done before the sheet closes.
            .task(id: model.didSave) {
                guard model.didSave else { return }
                try? await Task.sleep(for: .milliseconds(600))
                model.complete()
            }
        }
    }

    private var pageSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.pageTitle.isEmpty ? (model.pageURL?.host() ?? "Loading…") : model.pageTitle)
                .font(.headline)
                .lineLimit(2)
            if let url = model.pageURL {
                Text(url.absoluteString).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
