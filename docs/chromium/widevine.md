# Protected playback and Widevine

Boaz's DMG will keep WebKit alongside Chromium. Protected playback through WebKit is required before release. Widevine stays disabled until Google authorizes the integration and the signed distribution passes playback verification. The public iPhone build remains WebKit-only (the Mac App Store build was retired 2026-11-27).

## Current application status

An authorized inquiry for Boaz, an independently developed native Mac browser, was submitted through Google's Widevine contact form on 2026-11-13. The form confirmed submission. No license, partner access, CDM distribution authorization, VMP credentials, or approval has been received. No agreement was accepted.

Use [Widevine contact](https://widevine.com/contact) for the application and follow the [partner access process](https://developers.google.com/widevine/access). Google requires its license agreement and approves repository access separately. Public documentation gives no approval-time commitment; do not schedule release around an assumed wait. The inquiry asks which applicant account, macOS arm64 integration, CDM distribution, VMP signing, and validation requirements apply to Boaz.

Record the actual response and required artifacts when received. Do not assume Google will issue a conventional Apple signing certificate or that a CDM copied from Chrome is authorized for redistribution.

## Integration contract

- `boaz_widevine_enabled` in `Tools/chromium/development.json` stays `false` until Google authorizes distribution. It controls one thing: whether Chromium's Widevine component updater registers, which downloads Google's CDM into `<user data>/WidevineCdm`. No user-facing toggle exists.
- The host reports the CDM through `widevine_status` (ABI 49): `DISABLED` (flag off), `NOT_INSTALLED` (no CDM yet, or the installed CDM failed its check), `READY` (installed and verified). `NOT_INSTALLED` covers a CDM that isn't signed by Google's team (`EQHXZ8M8AV`) or fails strict code-signature validation. The check runs off the UI thread, three seconds after launch and again whenever the installed version changes.
- `ProtectedMediaService.widevineAvailable` is `true` only for `READY`. While it's false, a page that requests Widevine takes the existing WebKit route; while it's true, the page stays in Chromium. Seeded protected-media rules (Netflix, Disney+, Max and the rest) still route those services to WebKit until each is verified in Chromium. PlayReady requests are unaffected.
- The CDM runs in its own helper, `Chromium Helper (CDM).app` (patch `widevine-cdm-helper.patch`). macOS library validation refuses to map a library signed by another team, so Google's CDM can't load into our other helpers ("mapping process and mapped file (non-platform) have different Team IDs"). The CDM helper alone carries `com.apple.security.cs.disable-library-validation` (`Tools/chromium/host/helper-cdm-entitlements.plist`). It keeps the hardened runtime and Chromium's CDM sandbox. Every other helper keeps library validation.
- H.264, AAC, VP9, Opus, HEVC and AV1 come from `proprietary_codecs` and `ffmpeg_branding = "Chrome"`, which were already set.

## Verified on 2026-11-14 (development build, arm64)

Development-signed build with `boaz_widevine_enabled = true` and the CDM helper, run in an isolated home. Command: `Tools/chromium/eme-check.py --records "<user data>/Automation" --require-widevine --playback`, with automation on (`--boaz-automation`) and one web page open.

| Check | Result |
| --- | --- |
| Component updater downloads the CDM | Widevine CDM 4.10.3112.0, signed by Google (`EQHXZ8M8AV`) |
| MSE `isTypeSupported` | H.264, AAC, VP9, Opus, HEVC and AV1 all true |
| Clear Key | Full local license exchange; key status `usable` |
| `requestMediaKeySystemAccess("com.widevine.alpha")` | `SW_SECURE_CRYPTO` and `SW_SECURE_DECODE` granted; `HW_SECURE_ALL` refused (no hardware-secure Widevine on macOS) |
| MediaKeys and license challenge | CDM loads in `Chromium Helper (CDM)` and returns a 1,702-byte `license-request` |
| Protected playback | Shaka Player, `angel-one-widevine` DASH against Google's test proxy: licensed, 203 frames decoded in 8 s, up to 768×576 |
| Without the CDM helper | `createMediaKeys` fails: library validation refuses the CDM (the reason for the helper) |
| Corrupted CDM | Signature check rejects it (`-67062`); Boaz offers the WebKit route; the browser keeps running and Clear Key still works |
| Component updates off | Widevine not registered; access refused cleanly |
| Flag off (`false`) | Builds; status reports `DISABLED` |

Not verified: Netflix, Disney+, Max, Prime Video, Spotify or Hulu in Chromium (they need VMP, and some need browser approval); persistent licenses and storage IDs (`enable_cdm_storage_id` needs a Google-issued key); Intel (x64) builds; a cloud-signed production build with the CDM helper.

## Signing and key material

Widevine checks the Chromium framework executable against `Chromium Framework.framework/Versions/<version>/Resources/Chromium Framework.sig` (`chrome/common/media/cdm_host_file_path.cc`), and only in builds with `enable_cdm_host_verification`. Chrome writes that signature before Apple code signing (`sign_chrome_framework_for_widevine` in `chrome/BUILD.gn`). So `Tools/release-mac.sh` runs `Tools/chromium/vmp-sign.py` on the assembled app, before cloud or local signing. With `BOAZ_WIDEVINE_VMP_CERT` unset it prints exactly `Widevine VMP signing skipped (no certificate)`. With it set, `BOAZ_WIDEVINE_VMP_TOOL` must name Google's `signature_generator.py`; a missing tool, a failed run or an empty signature stops the release.

`enable_cdm_host_verification` stays off: the GN signing action calls `third_party/widevine/scripts/signature_generator.py`, which Google supplies with partner access and which isn't in the Chromium source.

After access is granted, obtain Google's tool and credential format and verify the required order. If the credential is a keychain-compatible identity, import it into the dedicated release keychain with access limited to the approved signer, then record its non-secret identity reference. If Google uses another credential format, follow that storage procedure instead. Never commit credentials, print passwords, or widen unrelated Keychain access. Exact installation commands remain blocked on the issued format and partner documentation.

## Verification before enabling

1. Verify authorized CDM provenance, architecture, signature, installation, update behavior, and failure recovery.
2. Produce a non-publishing signed artifact. Verify VMP output using Google's procedure, notarization, and clean-account launch.
3. Run an actual Widevine Shaka demo, then signed-in Netflix HD playback in Chromium. Record service, stream, resolution, audio/video decoding, and license failures without account or license secrets.
4. Exercise absent/corrupt/outdated CDM, offline startup, private profiles, separate profiles, and CDM update. Failed availability returns to the normal WebKit-routing policy.
5. Verify each shipped protected-media rule individually before changing it. Keep user rules unchanged.

For the initial dual-engine release, verify Netflix and Disney+ in WebKit through FairPlay, the other shipped streaming defaults, top-level fallback, Move Back, unsaved-form cancellation, and YouTube remaining in Chromium. A Shaka stream with no FairPlay alternative may show Boaz's friendly unsupported state; that exception does not satisfy the streaming-service playback gates.
