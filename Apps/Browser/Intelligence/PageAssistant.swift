import Foundation
import FoundationModels
import Observation
import WebKit

/// A summary read from the model's plain-text reply: the first line is the gist, "- " lines are the points.
/// Plain text rather than guided generation, because only text replies get the guardrails meant for summarizing.
struct PageSummary {
    var gist: String?
    var points: [String]?

    init(parsing reply: String) {
        let lines = reply.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let bullets = ["- ", "• ", "* "]
        func point(_ line: String) -> String? {
            bullets.first { line.hasPrefix($0) }.map { String(line.dropFirst($0.count)) }
        }
        gist = lines.first(where: { point($0) == nil })
        let points = lines.compactMap(point)
        self.points = points.isEmpty ? nil : points
    }
}

/// Summarizes one page and answers questions about it. One instance per page conversation: questions reuse a
/// single `LanguageModelSession`, so follow-ups can refer to earlier answers.
@Observable
final class PageAssistant {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer = ""
        var error: String?
    }

    private(set) var title: String
    private(set) var host: String
    private(set) var summary: PageSummary?
    private(set) var summaryError: String?
    private(set) var isSummarizing = false
    private(set) var turns: [Turn] = []
    private(set) var isAnswering = false
    /// The page was longer than the model can read, so answers and the summary cover only its start.
    private(set) var coversStartOnly = false
    /// Set when the conversation had to start over to make room.
    private(set) var notice: String?

    @ObservationIgnored private let extractText: @MainActor () async -> PageText?
    @ObservationIgnored private var text: PageText?
    @ObservationIgnored private var askSession: LanguageModelSession?
    /// Whether `askSession` has already read the page (its first question carried it).
    @ObservationIgnored private var askSessionHasPage = false

    convenience init(page: WebPage) {
        self.init(title: page.title, host: page.url?.host() ?? "") {
            await PageText.extract(from: page)
        }
    }

    init(title: String, host: String, extractText: @escaping @MainActor () async -> PageText?) {
        self.title = title
        self.host = host
        self.extractText = extractText
    }

    private static let summaryInstructions = """
        You summarize web pages for a reader in a browser. Write plain, neutral language. Use only facts stated in the \
        content; don't add opinions or outside knowledge.
        \(AIFeatures.untrustedContentRule)
        """

    private static let askInstructions = """
        You answer questions about one web page for a reader in a browser. Answer from the page content only. If the \
        page doesn't say, reply that the page doesn't cover it. Answer in at most three sentences unless the reader \
        asks for more detail. Don't use Markdown headings.
        \(AIFeatures.untrustedContentRule)
        """

    // MARK: Summary

    func summarize() async {
        guard !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil
        summary = nil
        defer { isSummarizing = false }
        // Instructions, schema and a few hundred tokens of output share the window with the page.
        guard let content = await pageContent(tokens: AIFeatures.contextSize - 1200) else {
            summaryError = "This page has no text to summarize."
            return
        }
        let session = LanguageModelSession(model: AIFeatures.pageModel, instructions: Self.summaryInstructions)
        let prompt = """
            \(AIFeatures.delimited(content))

            Summarize the page above. On the first line, write one sentence of at most 25 words saying what the page \
            is about. Then write its three to five most important points, each on its own line starting with "- ", \
            each one short sentence of at most 20 words.
            """
        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                summary = PageSummary(parsing: snapshot.content)
            }
        } catch {
            summaryError = AIFeatures.message(for: error)
        }
    }

    // MARK: Questions

    /// Loads the question session ahead of the first question.
    func prepareToAsk() {
        guard askSession == nil else { return }
        let session = LanguageModelSession(model: AIFeatures.pageModel, instructions: Self.askInstructions)
        session.prewarm()
        askSession = session
        askSessionHasPage = false
    }

    func ask(_ question: String) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        isAnswering = true
        defer { isAnswering = false }
        turns.append(Turn(question: question))
        let index = turns.count - 1
        do {
            try await answer(question, at: index, restarting: false)
        } catch where AIFeatures.isContextOverflow(error) && turns.count > 1 {
            // The conversation outgrew the window: start over with the page and just this question.
            notice = "Earlier questions were cleared to make room."
            do {
                try await answer(question, at: index, restarting: true)
            } catch {
                fail(index, error)
            }
        } catch {
            fail(index, error)
        }
    }

    /// A failed exchange may or may not have reached the transcript, so the next question starts a clean session.
    private func fail(_ index: Int, _ error: any Error) {
        turns[index].error = AIFeatures.message(for: error)
        askSession = nil
    }

    private func answer(_ question: String, at index: Int, restarting: Bool) async throws {
        if restarting { askSession = nil }
        prepareToAsk()
        guard let session = askSession else { return }
        let prompt: String
        if askSessionHasPage {
            prompt = question
        } else {
            // Half the window for the page leaves room for a few questions and answers.
            guard let content = await pageContent(tokens: AIFeatures.contextSize / 2) else {
                turns[index].error = "This page has no text to answer from."
                return
            }
            prompt = """
                \(AIFeatures.delimited(content))

                Question about the page above: \(question)
                """
        }
        turns[index].answer = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            turns[index].answer = snapshot.content
        }
        askSessionHasPage = true
    }

    // MARK: Page text

    private func pageContent(tokens budget: Int) async -> String? {
        if text == nil { text = await extractText() }
        guard let text else { return nil }
        if !text.title.isEmpty { title = text.title }
        if !text.host.isEmpty { host = text.host }
        let header = text.title.isEmpty ? "" : "Title: \(text.title)\n\n"
        let fitted = await AIFeatures.fit(text.text, tokens: budget - 60)
        if fitted.truncated { coversStartOnly = true }
        return header + fitted.text
    }
}
