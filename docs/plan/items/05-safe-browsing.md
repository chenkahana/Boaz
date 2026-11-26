# PLAN-05: Phishing and malware protection

Wave: 1 Accuracy
Status: Ready
Depends on: nothing. **Chen decides** the provider if the design involves a third-party API key or any data
leaving the device — write the spike, set Status to Needs Chen with the recommendation, and pick up another item.

## Goal

Boaz warns before a user lands on a known phishing or malware site, on both engines, without leaking browsing
history. Every mainstream browser ships this; Boaz ships nothing.

## Why

Accuracy means the browser does the right thing, and letting a phishing page through silently is the wrong thing.
The parity ledger already notes the absence ("no Safe Browsing integration without a verified provider config").

## Scope

1. **Spike first, one PR**: options and recommendation. Chromium fork: enabling Chromium's own Safe Browsing
   components (hash-prefix lists, no full URLs sent). WKWebView app: a local hash-prefix list checked before
   navigation. Privacy analysis for each, measured against docs/privacy.md and must-have #12's spirit.
2. **Implement** the approved design on the Chromium DMG and the iPhone/Mac App Store app.
3. Settings toggle (default on), docs/privacy.md updated to say exactly what is checked and what never leaves
   the device.

## Non-goals

- Safe Browsing real-time/full-URL lookup modes. Hash-prefix only; stronger modes are a new Chen decision.

## Acceptance criteria

- [ ] Known-bad test pages (testsafebrowsing.appspot.com) show a warning interstitial on both engines; Proceed
  and Go Back both work.
- [ ] No full URLs leave the device (proxy-verified and noted in the log).
- [ ] Toggle in Settings; docs/privacy.md updated.

## Verification

Manual test-page evidence plus the proxy note; UI test for the interstitial if CI allows.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
