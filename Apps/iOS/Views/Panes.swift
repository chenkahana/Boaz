import SwiftUI
import WebKit

struct SearchBar: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
            TextField("Search or enter address", text: $model.query)
                .submitLabel(.search)
                .onSubmit { Task { await model.search() } }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().stroke(Theme.cardStroke))
    }
}

struct WebPane: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        WebView(model.page)
            .overlay {
                if model.page.url == nil {
                    ContentUnavailableView("No page open", systemImage: "book.pages",
                                           description: Text("Search or open a link to read it here."))
                }
            }
            .navigationTitle(model.page.title.isEmpty ? (model.selectedSource?.site ?? "") : model.page.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Half-open "laptop" posture: page on top, ask controls on the bottom half.
struct DeskControls: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            SearchBar()
            HStack(spacing: 12) {
                ControlButton(title: "Summarize", symbol: "text.append")
                ControlButton(title: "Ask page", symbol: "bubble.left.and.text.bubble.right")
                ControlButton(title: "Voice", symbol: "waveform")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.indigo(2))
    }
}

private struct ControlButton: View {
    let title: String
    let symbol: String

    var body: some View {
        Button {} label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }
}
