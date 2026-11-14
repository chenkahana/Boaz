# Native website passkeys

Status (2026-11-14): WebAuthn works in the Chromium DMG for security keys and phone passkeys, and through Chromium's own checks end to end. Apple Passwords / iCloud Keychain passkeys wait on Apple's grant of the browser passkey entitlement (request Z6525VUX9T, "Submitted" in the developer portal). This concerns third-party website authentication, not sign-in to Boaz.

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

## What changed on 2026-11-14

- `native-modal-dialog-position.patch`: Chromium positions web-modal dialogs only for hosts backed by a Views widget, and Boaz's native window isn't one. The passkey dialog opened wherever AppKit put it, on another display in testing. `ModalDialogHost::ReportsScreenDialogPosition()` lets Boaz's window report a screen position. It now centers WebAuthn, HTTP sign-in and other web-modal dialogs over the page.
- `NSBluetoothAlwaysUsageDescription` in the Mac app. Without it macOS refuses Bluetooth ("the responsible app for the process does not…"), and Chromium hides phone passkeys (hybrid) and Bluetooth security keys.
- `release-mac.sh --passkeys` (cloud signing only) adds `com.apple.developer.web-browser.public-key-credential` to the browser entitlements. `export-cloud-application.py --finish` then fails unless both the signed app and Apple's provisioning profile carry it, because Xcode drops an ungranted entitlement without failing.
- `Tools/chromium/webauthn-check.py` runs WebAuthn checks in a running Boaz through Chromium's DevTools virtual authenticator. They go through Boaz's real origin, RP ID and secure-context checks and never touch the user's passkeys.

## Required runtime evidence

Use the real signed Boaz Chromium host with isolated test profiles and test accounts. Start at https://webauthn.io/, then Google and GitHub test accounts configured for passkeys. Never log credentials, assertions, authentication payloads or account details. Use existing affected tests/fixtures for source inspection; do not add new tests under the standing repository policy.

| Scenario | State | Evidence (development-signed build, arm64) |
|---|---|---|
| API and secure context | Passed | `PublicKeyCredential` present on HTTPS, absent on HTTP (`http://neverssl.com`) |
| Platform authenticator | Reports unavailable | `isUserVerifyingPlatformAuthenticatorAvailable()` is false until Apple grants the entitlement; Chromium's own Touch ID store stays off (no Chrome keychain group, by design) |
| Registration and sign-in | Passed (virtual authenticator) | Discoverable create, discoverable get and allow-list get; webauthn.io's own Register and Authenticate succeed |
| RP ID validation | Passed | `create` and `get` for a foreign RP ID raise `SecurityError` |
| Cancellation | Passed | Aborting a modal or conditional request raises `AbortError`; Escape on the real dialog returns `NotAllowedError` to webauthn.io |
| Focus rule | Passed | A request from an unfocused page fails ("the page does not have focus") |
| Native dialog | Passed | "Passkeys & Security Keys" chooser opens centered over the page; it takes focus when Boaz is active |
| Phone passkey | QR shown | After the Bluetooth fix the "Use your phone or tablet" QR appears; completing it needs a phone |
| Navigation during authentication | Passed | Navigating the tab closes the dialog and cancels the request |
| Conditional passkey UI | Partly | webauthn.io's conditional request completes with a saved passkey (signs in); the autofill suggestion list itself isn't verified (DevTools completes conditional requests without it) |
| Apple Passwords and Touch ID | Blocked | Needs Apple's entitlement grant |
| External security key | Needs hardware | Dialog offers it; no key was attached |
| Signed production build | Not run | `--passkeys` export refuses until the grant appears in provisioning |
| Relaunch, multiple tabs | Not run | Depends on Apple Passwords |

Record version, procedure, result, and any hardware/account/approval dependency for each row. Full host build, native window focus/accessibility, signed app inspection and end-to-end site success are separate gates. Source compilation cannot mark any row passed. Apple approval blocks only dependent Apple Passwords work; continue unrelated migration work.
