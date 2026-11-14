# Native website passkeys

Status: required work in PR #70. The native-window adapter is implementation-ready; manifest integration and compilation remain pending. No WebAuthn runtime scenario has passed. This concerns third-party website authentication, not sign-in to Boaz.

Reuse Chromium 157.0.8103.51 WebAuthn, FIDO, origin/RP validation, secure-context checks, user verification and profile isolation. Do not replace navigator.credentials, add OAuth/Sign in with Apple, or build a separate Swift AuthenticationServices authenticator. Keep WebKit, extensions and isolated passwords intact.

## Verified source findings

`chrome/browser/webauthn/chrome_authenticator_request_delegate.cc:1402–1426` obtains the request's WebContents and browser, preserves the app-window exclusion, then discovers NSWindow through a top-level Views widget. Boaz's NSWindow/NSHostingView has no such widget. `device/fido/fido_discovery_factory.cc:212–213` requires that window for iCloud discovery outside testing. This identifies a missing adapter without assuming that the rest of WebAuthn is broken.

`Tools/chromium/patches/webauthn-native-window.patch` retains that lookup and adds a fallback only for a positively registered Boaz browser. It obtains the existing BrowserWindow's native window. No origin, RP, authentication, protocol or crypto checks change. The two-file patch passes applicability and application checks against copied pinned source. The delegate already includes the complete `BrowserWindow` type; the Mac target adds `//boaz:headers`. Append the patch to the manifest, apply at the next safe build checkpoint, and compile the affected object/application. The verified missing Views widget supports implementing this fallback now; runtime uncertainty blocks acceptance, not this adapter. No SSD source was changed during preparation.

The existing native window already supplies WebContentsModalDialogHost. Chromium's authenticator dialog uses that host; runtime evidence must establish whether a further presentation fix is needed. Conditional mediation reaches ChromeWebAuthnCredentialsDelegate and passkey autofill; Boaz's native address adapter does not establish a working conditional suggestion surface. Security-key, hybrid/phone, Touch ID and Apple Passwords flows need separate results.

## Apple capability and signing

Apple documents `com.apple.developer.web-browser.public-key-credential` as a managed browser capability. The request requires an organization's Account Holder. The browser must register HTTP/HTTPS and offer navigation controls. See [Apple's entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential), the [request form](https://developer.apple.com/contact/request/macos-browsers-passkeys/) and [managed provisioning](https://help.apple.com/developer-account/#/dev38c81d4cd).

Required account action: the eligible Account Holder requests the capability for Boaz's own identifier, obtains approval, enables the granted capability, and regenerates the corresponding signing/provisioning configuration. Boaz's account eligibility and grant are not verified. Do not use Wix or Google's identity or entitlements as substitutes.

The pinned `device/fido/mac/icloud_keychain_sys.mm:228–239,267` checks the process entitlement. `chrome/BUILD.gn:764–770` includes Google's browser entitlement template only for branded builds with branded entitlements enabled. The current unbranded build does not include it. This is source evidence, not inspection of a finished signed executable.

`Tools/chromium/entitlements/browser-passkeys.approval-required.plist` prepares only the browser-passkey key. It passes plist validation and is not referenced by the build or signer. Do not merge it into generated entitlements until authorization is verified. After approval, merge this key into Boaz's own browser-process entitlements using the existing Chromium signing pipeline and appropriate profile. Do not copy Google's keychain groups or disable library validation. Inspect the actual signed app and profile; an arbitrary locally signed entitlement is not approval. Chromium checks key presence here, so omitting the key is safer than inserting a false value while approval is absent.

Local Touch ID keychain-group authorization is distinct from iCloud browser authorization. USB/security-key and hybrid paths must be verified separately; missing Apple approval does not by itself prove those transports unavailable.

## Required runtime evidence

Use the real signed Boaz Chromium host with isolated test profiles and test accounts. Start at https://webauthn.io/, then Google and GitHub test accounts configured for passkeys. Never log credentials, assertions, authentication payloads or account details. Use existing affected tests/fixtures for source inspection; do not add new tests under the standing repository policy.

| Scenario | State | Required evidence |
|---|---|---|
| New passkey registration | Pending host | Site confirms successful creation, correct RP/profile |
| Existing passkey assertion | Pending host/account | Successful site sign-in without credential migration assumptions |
| Apple Passwords and Touch ID | Pending authorization/host | Actual signed entitlement/profile plus successful native authentication |
| External security key | Pending host/hardware | Real device creation/assertion and cancellation |
| Phone passkey | Pending host/phone | Real hybrid QR/phone completion and cancellation |
| Conditional passkey UI | Pending implementation/runtime | Native suggestion selection completes the site's conditional request |
| User cancellation | Pending host | Dismissal returns expected failure, no orphaned dialog |
| Navigation/close during authentication | Pending host | Original request cancels; no result delivered to a replacement document |
| Multiple windows/profiles | Pending host | Correct originating tab/window, isolated profile behavior |
| Relaunch | Pending host | Same signed identity/profile authenticates after restart |

Record version, procedure, result, and any hardware/account/approval dependency for each row. Full host build, native window focus/accessibility, signed app inspection and end-to-end site success are separate gates. Source compilation cannot mark any row passed. Apple approval blocks only dependent Apple Passwords work; continue unrelated migration work.
