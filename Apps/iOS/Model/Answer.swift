import Foundation

/// A generated answer page. Each bullet can cite a quote from a source,
/// so a tap can open the source beside the answer and scroll to that quote.
struct Answer: Codable, Hashable {
    var title: String
    var sections: [Section]
    var sources: [Source]

    struct Section: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var bullets: [Bullet]
        var followUps: [String]
    }

    struct Bullet: Codable, Hashable, Identifiable {
        var id: String { emoji + text }
        var emoji: String
        var text: String
        var sourceID: String?
        var quote: String?
    }

    struct Source: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var site: String
        var url: URL
    }

    func source(for bullet: Bullet) -> Source? {
        sources.first { $0.id == bullet.sourceID }
    }
}

extension Answer.Source {
    /// Scroll-to-Text Fragment URL, so WebKit highlights the cited quote.
    func url(highlighting quote: String?) -> URL {
        guard let quote, !quote.isEmpty,
              let encoded = quote.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return url }
        return URL(string: url.absoluteString + "#:~:text=" + encoded) ?? url
    }
}

protocol AnswerProvider {
    func answer(for query: String) async throws -> Answer
}

/// Offline provider backed by a bundled sample. Swap for a provider that calls your own backend.
struct SampleAnswerProvider: AnswerProvider {
    func answer(for query: String) async throws -> Answer {
        try await Task.sleep(for: .milliseconds(600))
        let url = Bundle.main.url(forResource: "sample-answer", withExtension: "json")!
        var answer = try JSONDecoder().decode(Answer.self, from: Data(contentsOf: url))
        if !query.isEmpty { answer.title = query }
        return answer
    }
}
