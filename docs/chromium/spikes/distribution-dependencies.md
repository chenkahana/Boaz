> Current release policy: the [dual-engine revision](../dual-engine.md) supersedes Chromium-only DRM acceptance. Widevine approval gates enabling Chromium DRM; working protected playback in WebKit remains mandatory. The custom CEF build is paused with source and outputs preserved while S0 selects the host.

# Distribution dependencies

Recorded 2026-11-13. These are release gates, not reasons to stop independent engineering work.

## Widevine

The maintainer authorized an inquiry through Chrome and supplied the project contact address. The official General Questions form confirmed "Your email has been sent." The inquiry identifies Boaz as an independent macOS arm64 browser and asks about eligibility, CDM integration/distribution, VMP signing, validation, updates, and applicant requirements. No licensing agreement was accepted; no CDM or signing credentials were obtained. Approval and working playback remain blocked externally.

Google's [contact guidance](https://developers.google.com/widevine/contact/support) directs new inquiries to General Questions. Its [partner access requirements](https://developers.google.com/widevine/access) require a license agreement and approved account access, with corporate-email requirements for partner repositories. The inquiry asks how those requirements apply to an independent developer. Do not infer eligibility from the submitted form or the `enable_widevine` build flag.

After Google's response, record the approved integration route, distribution permissions, supported macOS arm64 CDM, signing requirements, and renewal/update process. Keep credentials outside the repository. Verify playback with the intended services in the signed distribution before the production switch.

## Apple distribution

The development-signed prototype passes nested static signature verification. This does not establish Developer ID distribution, notarization, or clean-account launch. Existing release tooling uses Xcode account/cloud signing and `--no-publish`; absence of a local Developer ID identity alone is not proof that export is unavailable.

The Chromium archive must include the verified framework layout and helpers, normalize plist metadata before signing, and sign nested components inside out. The final non-publishing archive/export must demonstrate the same properties before notarization and Gatekeeper acceptance are recorded.

## Custom CEF and codecs

The guarded SSD build uses the pinned CEF/Chromium revisions and a history-free checkout. Its first target is `cefsimple`, followed by distribution packaging and codec validation after that build passes. Full source history is not required for this pinned build. No source/output directory is automatically deleted to recover capacity or change versions.

H.264/AAC/HEVC playback and hardware decoding require runtime evidence from the resulting custom artifact. Codec flags do not establish distribution rights. Record the applicable distribution requirements alongside the selected codec configuration before release.
