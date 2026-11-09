import Foundation
import WebKit

/// The readable text of a web page, for features that read it (reader mode, page summaries).
struct PageText {
    let title: String
    let host: String
    let text: String

    /// Scores every container with a reasonable amount of direct paragraph/heading text, picks the highest scorer,
    /// then serializes its readable children in order as `{ title, site, blocks: [{ tag, text, src }] }`.
    ///
    /// `page.callJavaScript` wraps this string as a function BODY and calls it — it is not an expression evaluator
    /// like `evaluateJavaScript`, so the value comes back only via an explicit top-level `return`. No outer
    /// `(function(){...})()` wrapper here (that would just make this function return `undefined`, since the inner
    /// IIFE's own `return` doesn't propagate out).
    static let extractionScript = """
      function textLength(el) {
        return (el.innerText || el.textContent || '').trim().length;
      }

      function score(el) {
        var p = el.querySelectorAll('p').length;
        var text = textLength(el);
        var links = el.querySelectorAll('a').length;
        var linkDensity = text > 0 ? (el.querySelectorAll('a').length * 20) / text : 0;
        return text * (1 + p * 0.1) * (1 - Math.min(linkDensity, 0.9)) - links * 2;
      }

      var candidates = document.querySelectorAll('article, main, [role="main"], section, div');
      var best = document.body;
      var bestScore = -Infinity;
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (textLength(el) < 200) { continue; }
        var s = score(el);
        if (s > bestScore) { bestScore = s; best = el; }
      }

      var allowed = { P: 'p', H2: 'h2', H3: 'h3', H1: 'h2', BLOCKQUOTE: 'blockquote', LI: 'li', IMG: 'img', FIGCAPTION: 'figcaption' };
      var blocks = [];
      var seenText = {};
      var walker = document.createTreeWalker(best, NodeFilter.SHOW_ELEMENT, null);
      var node = walker.currentNode;
      while (node) {
        var tag = allowed[node.tagName];
        if (tag) {
          if (tag === 'img') {
            var src = node.currentSrc || node.src;
            if (src) { blocks.push({ tag: tag, text: null, src: src }); }
          } else {
            var text = (node.innerText || node.textContent || '').trim();
            if (text.length > 1 && !seenText[text]) {
              seenText[text] = true;
              blocks.push({ tag: tag, text: text, src: null });
            }
          }
        }
        node = walker.nextNode();
      }

      var site = (document.querySelector('meta[property="og:site_name"]') || {}).content || location.hostname.replace(/^www\\./, '');
      var title = (document.querySelector('h1') || {}).innerText || document.title;

      return JSON.stringify({ title: title, site: site, blocks: blocks });
    """

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
