import SwiftUI

/// "Add to Folio" sheet shown by the share extension — Arc-styled like the rest of the app.
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
                    .buttonStyle(.bordered)

                    Button { model.save(pinned: false) } label: {
                        Label("Add to Today", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .tint(Theme.brand)
                .disabled(model.pageURL == nil || model.selectedSpaceID == nil)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(20)
            .navigationTitle("Add to Folio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
            }
            .onChange(of: model.didSave) { _, saved in if saved { model.complete() } }
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
