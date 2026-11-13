#if BOAZ_CHROMIUM
import Foundation

extension PageText {
    private struct ChromiumPayload: Decodable {
        struct Block: Decodable { let text: String? }
        let title: String
        let blocks: [Block]
    }

    @MainActor
    static func extract(from page: ChromiumEnginePageAdapter) async -> PageText? {
        do {
            for _ in 0..<50 {
                try Task.checkCancellation()
                guard page.state.isLoading else { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            try Task.checkCancellation()
            let original = page.state
            guard original.lifecycle == .active else { return nil }
            func unchanged() -> Bool {
                !Task.isCancelled && page.state.lifecycle == .active &&
                    page.state.navigationID == original.navigationID && page.state.url == original.url
            }
            var title = original.title
            var text = ""
            let raw = try await page.executeTrusted(function: "function() {\n" + extractionScript + "\n}", arguments: [:])
            guard unchanged() else { return nil }
            if case .string(let json) = raw,
               let payload = try? JSONDecoder().decode(ChromiumPayload.self, from: Data(json.utf8)) {
                text = payload.blocks.compactMap(\.text).joined(separator: "\n")
                if title.isEmpty { title = payload.title }
            }
            if text.count < 400 {
                guard unchanged() else { return nil }
                let body = try await page.executeTrusted(
                    function: "function() { return document.body ? document.body.innerText : ''; }", arguments: [:])
                guard unchanged() else { return nil }
                if case .string(let value) = body, value.count > text.count { text = value }
            }
            text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard unchanged(), !text.isEmpty else { return nil }
            let host = original.url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
            return PageText(title: title.trimmingCharacters(in: .whitespacesAndNewlines), host: host, text: text)
        } catch {
            // Navigation/cancellation and the bridge's 64-KiB result limit fail
            // extraction; do not truncate or fall back into a different document.
            return nil
        }
    }
}
#endif
