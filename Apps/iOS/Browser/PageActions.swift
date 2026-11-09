import AVFoundation
import UIKit
import WebKit

/// Plain text of the whole visible page, for Translate: unlike `Reader`, this isn't limited to
/// article-shaped pages, since any page should be translatable.
enum PageText {
    private static let maxCharacters = 8000

    @MainActor
    static func extract(from page: WebPage) async -> String? {
        guard let raw = try? await page.callJavaScript(extractionScript) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxCharacters))
    }

    private static let extractionScript = "return (document.body ? document.body.innerText : '').trim();"
}

/// Prints the page through its exported PDF: `WebPage` has no print formatter of its own (that's a
/// `WKWebView` API), but a PDF prints just as well.
enum PagePrint {
    @MainActor
    static func present(_ page: WebPage) async {
        guard let data = try? await page.exported(as: .pdf()) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = page.title.isEmpty ? (page.url?.host() ?? "Boaz") : page.title
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }
}

/// Reads the Reader-extracted text aloud; one utterance at a time, shared across tabs. Observable, so the
/// menu's Listen to Page / Stop Listening follows the speech as it starts and ends.
@MainActor @Observable
final class PageSpeech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = PageSpeech()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// The utterance being read; a cancelled one finishing late mustn't clear its successor.
    @ObservationIgnored private var current: ObjectIdentifier?
    private(set) var isSpeaking = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ article: ReaderArticle) {
        synthesizer.stopSpeaking(at: .immediate)
        let text = article.blocks.compactMap(\.text).joined(separator: ". ")
        guard !text.isEmpty else { return stop() }
        let utterance = AVSpeechUtterance(string: text)
        current = ObjectIdentifier(utterance)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    private func ended(_ id: ObjectIdentifier) {
        guard id == current else { return }
        current = nil
        isSpeaking = false
    }
}
