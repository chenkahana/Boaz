import FolioKit
import SwiftUI
import WebKit

enum FeatureFlags {
    /// AI answer pages are parked; search goes straight to the web.
    static let aiAnswers = false
}

/// Single source of truth shared by every posture, so folding or unfolding never loses state.
@Observable
final class BrowserModel {
    var query = ""
    var answer: Answer?
    var isLoading = false
    var selectedSource: Answer.Source?
    var showsWebInCompact = false
    var hinge: DeviceHinge?

    let page = WebPage()
    private let provider: any AnswerProvider

    init(provider: any AnswerProvider = SampleAnswerProvider()) {
        self.provider = provider
    }

    func search() async {
        guard FeatureFlags.aiAnswers else {
            guard let url = SearchInput.url(for: query) else { return }
            page.load(URLRequest(url: url))
            showsWebInCompact = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        answer = try? await provider.answer(for: query)
        if let first = answer?.sources.first { open(first, quote: nil, revealInCompact: false) }
    }

    func open(_ source: Answer.Source, quote: String?, revealInCompact: Bool = true) {
        selectedSource = source
        page.load(URLRequest(url: source.url(highlighting: quote)))
        if revealInCompact { showsWebInCompact = true }
    }

    var isDeskPosture: Bool { hinge?.status == .partiallyOpen }
}
