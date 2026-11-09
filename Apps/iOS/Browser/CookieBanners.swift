import WebKit

/// Auto-consent: hides and, where possible, auto-rejects common cookie/consent banners (OneTrust,
/// Cookiebot, Didomi, Quantcast/InMobi (TCF), TrustArc, Usercentrics, Sourcepoint, Osano, Complianz,
/// plus a conservative generic fallback). Runs in an isolated content world so it never collides with
/// page globals. Gated by `Preferences.hideCookieBanners`.
enum CookieBanners {
    @MainActor
    static func userScript() -> WKUserScript {
        WKUserScript(source: javaScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)
    }

    private static let javaScript = """
    (function () {
      if (window.__boazCookieBannerRan) { return; }
      window.__boazCookieBannerRan = true;

      // Selectors for known CMP banner containers.
      var containerSelectors = [
        '#onetrust-banner-sdk', '#onetrust-consent-sdk', '.onetrust-pc-dark-filter',
        '#CybotCookiebotDialog', '#CybotCookiebotDialogBodyUnderlay',
        '#didomi-host', '.didomi-consent-popup-backdrop', '.didomi-popup-container',
        '#qc-cmp2-container', '.qc-cmp2-container', '#qc-cmp2-main',
        '#truste-consent-track', '#trustarc-banner-overlay', '.truste_overlay', '.truste_box_overlay',
        '#usercentrics-root', '#uc-center-container', '.uc-banner-overlay',
        '.sp_choice_type_11', '.message-container.sp-message-open', '#sp_message_container',
        '.cmplz-cookiebanner', '.cmplz-manage-consent', '#cmplz-cookiebanner-container',
        '#osano-cm-window', '.osano-cm-dialog', '.osano-cm-window',
        '#consent_blackbar', '.evidon-banner', '#evidon-barrier',
        '[id*="cookie-law-info"]', '.cli-modal-backdrop',
      ];

      // Reject / "necessary only" buttons to click when present, tried in order.
      var rejectSelectors = [
        '#onetrust-reject-all-handler', '.onetrust-close-btn-handler[aria-label*="Close"]',
        '#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll', '#CybotCookiebotDialogBodyButtonDecline',
        'button[id*="didomi-notice-disagree"]', '.didomi-continue-without-agreeing',
        '.qc-cmp2-summary-buttons button[mode="secondary"]',
        '#truste-consent-required', '.truste-button2',
        '#uc-btn-deny-banner', '.uc-btn-deny',
        '.sp_choice_type_REJECT_ALL', 'button[title="Reject All"]',
        '.cmplz-deny', '.cmplz-btn.cmplz-deny',
        '.osano-cm-denyAll', '.osano-cm-button--type_denyAll',
        'button[aria-label="Reject all"]', 'button[aria-label="Reject All"]',
        'button[aria-label="Necessary only"]', 'button[aria-label*="reject" i]',
      ];

      function textLooksLikeReject(el) {
        var text = (el.innerText || el.textContent || '').trim().toLowerCase();
        if (!text || text.length > 40) { return false; }
        return /^(reject all|decline all|necessary only|reject|disagree|only necessary|use necessary cookies only)$/.test(text);
      }

      function findGenericReject(root) {
        var candidates = (root || document).querySelectorAll('button, a[role="button"], [role="button"]');
        for (var i = 0; i < candidates.length; i++) {
          if (textLooksLikeReject(candidates[i])) { return candidates[i]; }
        }
        return null;
      }

      function hide(el) {
        if (!el || el.__boazHidden) { return; }
        el.__boazHidden = true;
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
      }

      function restoreScroll() {
        document.documentElement.style.removeProperty('overflow');
        document.body.style.removeProperty('overflow');
        document.documentElement.style.removeProperty('position');
        document.body.style.removeProperty('position');
      }

      function sweep() {
        var acted = false;
        for (var i = 0; i < rejectSelectors.length; i++) {
          var btn = document.querySelector(rejectSelectors[i]);
          if (btn) { try { btn.click(); acted = true; } catch (e) {} }
        }
        for (var j = 0; j < containerSelectors.length; j++) {
          var nodes = document.querySelectorAll(containerSelectors[j]);
          for (var k = 0; k < nodes.length; k++) { hide(nodes[k]); acted = true; }
        }
        // Conservative generic fallback: a fixed/sticky full-width bar near a viewport edge whose
        // id/class mentions "cookie" together with "consent"/"banner"/"gdpr".
        var generic = document.querySelectorAll('[id*="cookie" i][class*="consent" i], ' +
          '[class*="cookie" i][class*="consent" i], [id*="cookie" i][id*="banner" i], ' +
          '[class*="cookie" i][class*="banner" i], [id*="gdpr" i], [class*="gdpr" i]');
        for (var m = 0; m < generic.length; m++) {
          var el = generic[m];
          var style = window.getComputedStyle(el);
          var rect = el.getBoundingClientRect();
          var looksLikeOverlay = (style.position === 'fixed' || style.position === 'sticky') &&
            rect.width > window.innerWidth * 0.5;
          if (looksLikeOverlay) {
            var reject = findGenericReject(el);
            if (reject) { try { reject.click(); } catch (e) {} }
            hide(el);
            acted = true;
          }
        }
        if (acted) { restoreScroll(); }
        return acted;
      }

      sweep();
      var observer = new MutationObserver(function () { sweep(); });
      observer.observe(document.documentElement, { childList: true, subtree: true });
      setTimeout(function () { observer.disconnect(); restoreScroll(); }, 10000);
    })();
    """
}
