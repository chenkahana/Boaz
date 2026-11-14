# Protected playback and dormant Widevine

Boaz's DMG will keep WebKit alongside Chromium. Protected playback through WebKit is required before release. Widevine stays disabled until Google authorizes the integration and the signed distribution passes playback verification. The public Mac App Store and iPhone builds remain WebKit-only.

## Current application status

An authorized inquiry for Boaz, an independently developed native Mac browser, was submitted through Google's Widevine contact form on 2026-11-13. The form confirmed submission. No license, partner access, CDM distribution authorization, VMP credentials, or approval has been received. No agreement was accepted.

Use [Widevine contact](https://widevine.com/contact) for the application and follow the [partner access process](https://developers.google.com/widevine/access). Google requires its license agreement and approves repository access separately. Public documentation gives no approval-time commitment; do not schedule release around an assumed wait. The inquiry asks which applicant account, macOS arm64 integration, CDM distribution, VMP signing, and validation requirements apply to Boaz.

Record the actual response and required artifacts when received. Do not assume Google will issue a conventional Apple signing certificate or that a CDM copied from Chrome is authorized for redistribution.

## Integration contract

- `BOAZ_WIDEVINE_ENABLED=NO` is the default build setting. No user-facing activation toggle appears before approval.
- `ProtectedMediaService.widevineAvailable` requires the approved build setting, a successfully registered compatible CDM, and completed release validation. A build flag alone is insufficient.
- Keep Chromium's Widevine build support available where supported by the selected host. Runtime CDM registration and downloads remain disabled until approved. H.264/AAC settings and HEVC/hardware-decoding support need separate runtime verification.
- The proposed `CefRegisterWidevineCdm(path)` is absent from the pinned CEF `57389f04a61ab0e9603d9f96602843d0e08bb11c` headers. Do not implement against that obsolete assumption. If CEF remains selected, verify its supported Chromium component-registration path. A direct host should expose only the approved Widevine component-updater path, without enabling unrelated services.
- Widevine availability suppresses automatic request-triggered fallback. Explicit user rules and existing protected-media defaults still select WebKit until each service is verified in Chromium. PlayReady requests require their own capability decision; Widevine availability does not establish PlayReady support.

## Signing and key material

The intended release hook follows code signing and precedes notarization, subject to Google's actual VMP instructions. `BOAZ_WIDEVINE_VMP_CERT` selects the approved signing credential. With no credential, the hook must print exactly `Widevine VMP signing skipped (no certificate)`. With a credential but missing approved tooling or invalid signing output, it must fail instead of silently skipping.

The existing release script performs cloud Developer ID signing and notarization together through `xcodebuild -exportArchive` with destination `upload`. There is no verified insertion point between them. The release packet must split export/signing and notarization using supported tooling before enabling VMP. Do not claim that a log message constitutes a signing implementation.

After access is granted, obtain Google's tool and credential format and verify the required order. If the credential is a keychain-compatible identity, import it into the dedicated release keychain with access limited to the approved signer, then record its non-secret identity reference. If Google uses another credential format, follow that storage procedure instead. Never commit credentials, print passwords, or widen unrelated Keychain access. Exact installation commands remain blocked on the issued format and partner documentation.

## Verification before enabling

1. Verify authorized CDM provenance, architecture, signature, installation, update behavior, and failure recovery.
2. Produce a non-publishing signed artifact. Verify VMP output using Google's procedure, notarization, and clean-account launch.
3. Run an actual Widevine Shaka demo, then signed-in Netflix HD playback in Chromium. Record service, stream, resolution, audio/video decoding, and license failures without account or license secrets.
4. Exercise absent/corrupt/outdated CDM, offline startup, private profiles, separate profiles, and CDM update. Failed availability returns to the normal WebKit-routing policy.
5. Verify each shipped protected-media rule individually before changing it. Keep user rules unchanged.

For the initial dual-engine release, verify Netflix and Disney+ in WebKit through FairPlay, the other shipped streaming defaults, top-level fallback, Move Back, unsaved-form cancellation, and YouTube remaining in Chromium. A Shaka stream with no FairPlay alternative may show Boaz's friendly unsupported state; that exception does not satisfy the streaming-service playback gates.
