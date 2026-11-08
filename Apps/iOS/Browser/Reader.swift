import Foundation
import WebKit

/// A reader-mode block: one paragraph, heading, quote, list item or image, in document order.
struct ReaderBlock: Decodable, Identifiable, Hashable {
    enum Tag: String, Decodable { case h2, h3, p, blockquote, li, img, figcaption }
    var id: Int
    let tag: Tag
    let text: String?
    let src: String?
}

struct ReaderArticle: Identifiable {
    let id = UUID()
    let title: String
    let site: String
    let blocks: [ReaderBlock]
    let readingMinutes: Int

    var characterCount: Int { blocks.reduce(0) { $0 + ($1.text?.count ?? 0) } }
}

enum ReaderError: Error { case tooShort, decodeFailed }

/// Own extractor, no external libraries: scores block-level containers by text density and keeps the
/// readable tags inside the best one.
enum Reader {
    static let minimumCharacters = 500

    @MainActor
    static func extract(from page: WebPage) async -> ReaderArticle? {
        guard let raw = try? await page.callJavaScript(extractionScript) as? String,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        let blocks = decoded.blocks.enumerated().map { ReaderBlock(id: $0.offset, tag: $0.element.tag, text: $0.element.text, src: $0.element.src) }
        let article = ReaderArticle(title: decoded.title, site: decoded.site, blocks: blocks,
                                    readingMinutes: max(1, decoded.blocks.reduce(0) { $0 + ($1.text?.split(separator: " ").count ?? 0) } / 200))
        return article.characterCount >= minimumCharacters ? article : nil
    }

    /// Cheap pre-check (no full extraction) used to enable/disable the Reader button.
    @MainActor
    static func estimatedReadableLength(of page: WebPage) async -> Int {
        (try? await page.callJavaScript(lengthEstimateScript) as? Int) ?? 0
    }

    private struct Payload: Decodable {
        struct Block: Decodable { let tag: ReaderBlock.Tag; let text: String?; let src: String? }
        let title: String
        let site: String
        let blocks: [Block]
    }

    // `page.callJavaScript` wraps this string as a function BODY and calls it — it is not an
    // expression evaluator like `evaluateJavaScript`, so the value comes back only via an explicit
    // top-level `return`. No outer `(function(){...})()` wrapper here (that would just make this
    // function return `undefined`, since the inner IIFE's own `return` doesn't propagate out).
    private static let lengthEstimateScript = """
    var tags = ['p', 'h2', 'h3', 'blockquote', 'li'];
    var total = 0;
    for (var i = 0; i < tags.length; i++) {
      var nodes = document.getElementsByTagName(tags[i]);
      for (var j = 0; j < nodes.length; j++) { total += (nodes[j].innerText || '').length; }
    }
    return total;
    """

    /// Scores every container with a reasonable amount of direct paragraph/heading text, picks the
    /// highest scorer, then serializes its readable children in order. See the note on
    /// `lengthEstimateScript`: no outer IIFE, a top-level `return` instead.
    private static let extractionScript = """
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
}
