import Foundation

/// The readable text of a web page, for features that read it (reader mode, page summaries).
struct PageText {
    let title: String
    let host: String
    let text: String

    /// Picks the container holding the most article text, then serializes its readable children in order as
    /// `{ title, site, blocks: [{ tag, text, src }] }`.
    ///
    /// Text is the DOM's (`textContent`), counted once per element in one pass, so sections a page has collapsed
    /// still count, without the contents of `<style>` and `<script>`. Chrome that isn't the article (headers,
    /// navigation, reference lists, edit links, ads) is skipped by tag, role or class name, and so are paragraphs
    /// and list items that are only links. Images are kept, except icons and SVGs (which the reader can't draw).
    ///
    /// `page.callJavaScript` wraps this string as a function BODY and calls it — it is not an expression evaluator
    /// like `evaluateJavaScript`, so the value comes back only via an explicit top-level `return`. No outer
    /// `(function(){...})()` wrapper here (that would just make this function return `undefined`, since the inner
    /// IIFE's own `return` doesn't propagate out).
    static let extractionScript = """
      var skippedTags = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|SVG|CANVAS|IFRAME|OBJECT|FORM|BUTTON|INPUT|SELECT|TEXTAREA|NAV|ASIDE|HEADER|FOOTER|DIALOG)$/;
      var skippedRoles = /^(navigation|complementary|contentinfo|banner|search|dialog|note)$/;
      var skippedNames = /(^|[\\s_-])(references?|reflist|citation|cite|navbox|catlinks|editsection|toc|infobox|sidebar|side-box|metadata|hatnote|ambox|footnotes?|comments?|related|share|social|newsletter|promo|advert|ads?|cookie|breadcrumbs?|menu|banner|popup|modal)([\\s_-]|$)/i;
      var keptNames = /(^|[_-])(article|main|content|body|post|story|entry)([_-]|$)/i;
      function skipped(el) {
        if (skippedTags.test(el.tagName.toUpperCase())) { return true; }
        if (el.getAttribute('aria-hidden') === 'true') { return true; }
        var role = el.getAttribute('role');
        if (role && skippedRoles.test(role)) { return true; }
        // Each class name and the id on its own: one naming the article ("main-content", "post-body") keeps a wrapper
        // that another name ("with-sidebar") would skip. A name with a skip word in it ("comment-body",
        // "related-content") keeps nothing.
        var names = ((typeof el.className === 'string' ? el.className : '') + ' ' + (el.id || '')).split(/\\s+/);
        var skip = false, keep = false;
        for (var i = 0; i < names.length; i++) {
          if (!names[i]) { continue; }
          if (skippedNames.test(names[i])) { skip = true; } else if (keptNames.test(names[i])) { keep = true; }
        }
        return skip && !keep;
      }

      // Per element: its text length (without whitespace), the part in links, and its paragraphs. Skipped ones count none.
      var stats = new Map();
      function measure(el) {
        var s = { text: 0, links: 0, p: el.tagName === 'P' ? 1 : 0 };
        if (el !== document.body && skipped(el)) { stats.set(el, { text: 0, links: 0, p: 0 }); return stats.get(el); }
        for (var child = el.firstChild; child; child = child.nextSibling) {
          if (child.nodeType === 3) {
            s.text += child.data.replace(/\\s+/g, '').length;
          } else if (child.nodeType === 1) {
            var c = measure(child);
            s.text += c.text;
            s.links += child.tagName === 'A' ? c.text : c.links;
            s.p += c.p;
          }
        }
        stats.set(el, s);
        return s;
      }
      measure(document.body);

      var best = document.body;
      var bestScore = -Infinity;
      var candidates = document.body.querySelectorAll('article, main, [role="main"], section, div');
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        var s = stats.get(el);
        if (!s || s.text < 200) { continue; }
        var score = s.text * (1 + s.p * 0.1) * (1 - Math.min(s.links / s.text, 0.9));
        if (score > bestScore) { bestScore = score; best = el; }
      }

      function cleanText(el) {
        var out = '';
        for (var child = el.firstChild; child; child = child.nextSibling) {
          if (child.nodeType === 3) { out += child.data; }
          else if (child.nodeType === 1 && child.tagName === 'BR') { out += ' '; }
          else if (child.nodeType === 1 && !skipped(child)) { out += cleanText(child); }
        }
        return out;
      }

      var allowed = { P: 'p', H1: 'h2', H2: 'h2', H3: 'h3', H4: 'h3', BLOCKQUOTE: 'blockquote', LI: 'li', IMG: 'img', FIGCAPTION: 'figcaption' };
      var site = (document.querySelector('meta[property="og:site_name"]') || {}).content || location.hostname.replace(/^www\\./, '');
      var title = ((document.querySelector('h1') || {}).textContent || document.title).trim();
      var blocks = [];
      // The title shows above the blocks.
      var seenText = {};
      seenText[title] = true;
      function collect(el) {
        for (var node = el.firstElementChild; node; node = node.nextElementSibling) {
          if (skipped(node)) { continue; }
          var tag = allowed[node.tagName];
          if (tag === 'img') {
            var src = node.currentSrc || node.src;
            var width = node.naturalWidth || parseInt(node.getAttribute('width'), 10) || 0;
            if (src && (width === 0 || width >= 64) && !/\\.svg($|[?#])/i.test(src)) { blocks.push({ tag: tag, text: null, src: src }); }
          } else if ((tag === 'li' || tag === 'p') && stats.get(node).links >= stats.get(node).text * 0.9) {
            continue;
          } else if (tag) {
            var text = cleanText(node).replace(/\\s+/g, ' ').trim();
            if (text.length > 1 && !seenText[text]) {
              seenText[text] = true;
              blocks.push({ tag: tag, text: text, src: null });
            }
          } else {
            collect(node);
          }
        }
      }
      collect(best);

      return JSON.stringify({ title: title, site: site, blocks: blocks });
    """
}
