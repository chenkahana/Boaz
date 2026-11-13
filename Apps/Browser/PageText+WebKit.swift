import Foundation
import WebKit

extension PageText {
    /// Pages that aren't articles (apps, listings) have little in their best block; their visible text is used instead.
    private static let bodyTextScript = "return document.body ? document.body.innerText : '';"

    private struct Payload: Decodable {
        struct Block: Decodable { let text: String? }
        let title: String
        let blocks: [Block]
    }

    /// Reads the page's main text once it has finished loading (waits up to ten seconds). Nil when it has none.
    static func extract(from page: WebPage) async -> PageText? {
        for _ in 0..<50 where page.isLoading {
            try? await Task.sleep(for: .milliseconds(200))
        }
        var title = page.title
        var text = ""
        if let raw = try? await page.callJavaScript(extractionScript) as? String,
           let payload = try? JSONDecoder().decode(Payload.self, from: Data(raw.utf8)) {
            text = payload.blocks.compactMap(\.text).joined(separator: "\n")
            if title.isEmpty { title = payload.title }
        }
        if text.count < 400, let body = try? await page.callJavaScript(bodyTextScript) as? String, body.count > text.count {
            text = body
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let host = page.url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        return PageText(title: title.trimmingCharacters(in: .whitespacesAndNewlines), host: host, text: text)
    }
}
