# Dual-engine migration revision

Effective 2026-11-13. This revision supersedes Chromium-only DMG and mandatory Chromium Widevine playback before release. Chromium becomes the default; system WebKit remains available at runtime for protected media and user-selected pages. Working protected playback in the selected engine remains a release gate. Google approval is required before enabling Widevine, but no longer blocks a release whose WebKit protected-media acceptance passes.

Apply this revision before further Wave 0 work. [S0](spikes/S0-crest.md) studied Crest read-only and selected an independently authored direct Chromium host. CEF-specific S2a/S2b are replaced by direct-host acceptance with unchanged native/extension gates. Existing CEF experiments and artifacts are retained as evidence, not production integration. The guarded baseline build was stopped normally with exit 130; source and outputs remain on the verified SSD image. CEF patch workers have paused.

All work remains in draft PR #70. No intermediate releases. Preserve the native UI, eight required Chromium extensions, password isolation, passkeys, performance/size budgets, signed updates and rollback, and three days of dogfooding. Routine architecture choices belong to the orchestrator. No main-world password fallback or JavaScript replacement of passkeys.

## Verification qualifications

The supplied Crest architecture, disk requirements, FairPlay compatibility, CEF CDM API, HEVC flags, and VMP-signing details are claims to verify, not established facts. An isolated-world script cannot be assumed to observe calls made against a different world's JavaScript objects. Prefer a browser/renderer EME observation hook with authoritative top-frame/document identity. If a minimal main-world observer is needed, it carries no secrets or privileged bridge and remains separate from the isolated password channel; untrusted page events alone cannot authorize an engine switch.

The Amazon default is path-specific. Model a normalized host plus optional path prefix, with `/gp/video` restricted to that path, rather than switching every Amazon page. Resolve this with the `SiteEngineRule` schema before migration. Private-session rules must remain ephemeral. Removing shipped defaults must persist so relaunch does not silently recreate them. Explicit user rules always win.

Moving between engines is a navigation with separate cookies/storage, not a lossless transfer of JavaScript state. Cancel the move when before-unload or edited-form protection is declined. Save an automatic rule only after a successful switch; suppress repeat requests by document identity. A Widevine-only stream does not become FairPlay by switching engines. Verify each service and show a friendly unsupported-media state when no compatible stream exists.

## Requested implementation scope

1. TWO ENGINES IN THE MAC DMG (replaces "Chromium only in the DMG")
- The DMG app contains BOTH engines at runtime. Chromium is the default for new pages. WebKit is the system framework, so it adds no size. The Mac App Store build stays WebKit-only, as planned.
- The Phase 1 engine layer (Apps/Engine) now serves both engines at once. Targets:
  - Boaz-macOS (App Store) compiles Apps/Engine/WebKit only.
  - Boaz-macOS-DMG compiles Apps/Engine/WebKit AND Apps/Engine/Chromium.
  - The condition ENGINE_CHROMIUM now means "Chromium is available". WebKit is always available.
  - The rule still holds: no `import WebKit` above Apps/Engine/WebKit, and no CEF/Chromium headers outside the bridge.
- Each tab carries an engine (`EngineKind: .chromium | .webkit`), stored on the tab so it survives a relaunch.
  - Per-site engine rules go in BoazKit, as a new GRDB table `SiteEngineRule(host, engine, reason: user | protectedMedia, createdAt)`, with a migration.
  - The rules sync like other library data, if that fits the existing sync model. Otherwise they stay local, and you note which.
- UI, in the existing design system:
  - Page menu items "Open Page in WebKit" and "Open Page in Chromium".
  - A small engine badge in the address field on WebKit pages, Chromium being the norm.
  - Settings › Websites › Engine lists the rules, with a default-engine picker and Remove.
  - Moving a page between engines checks for unsaved work first: `beforeunload`, or any edited form field.
- Each engine keeps its own website data (cookies and storage), per profile. Document this in the help text.
  - The Phase 4 one-time cookie copy from WebKit into Chromium stays, so current DMG users stay signed in.
  - The WebKit data is NOT deleted: WebKit pages keep using it.
- Extensions in the DMG are Chromium-only (Chrome Web Store), as in Crest. The WKWebExtension code stays for the App Store build. At the first Chromium launch, reinstall from the store the Web Store extensions listed in today's installed.json. List unpacked ones in a "reinstall these" sheet.
- Parity now means: every feature in parity.md works for BOTH engine kinds in the DMG, except extensions (Chromium) and Picture in Picture rules per engine. Add an "engine" column to parity.md.

2. PROTECTED MEDIA (DRM) ROUTING
- Add a `KeySystem` enum (widevine, playReady, fairPlay, clearKey) and a `ProtectedMediaService` in Apps/Engine.
- The Chromium page agent (the S3 isolated-world script) observes `navigator.requestMediaKeySystemAccess` calls with key system "com.widevine.alpha" or "com.microsoft.playready*", and reports each one to Swift. Only the key-system string is passed, never page data.
- Decision, made per request:
  - (a) Widevine available AND enabled → let Chromium play.
  - (b) Otherwise, if the site has no user-chosen rule → move the tab to WebKit and save a rule with reason `protectedMedia`. Then show a toast "Playing in WebKit for protected video", with a "Move Back" button. "Move Back" removes the rule and reloads in Chromium.
  - (c) A user-chosen rule always wins.
- Only the top-level page triggers a move. A DRM player embedded from another site doesn't move the page; the user can use "Open Page in WebKit". The same document asking again doesn't prompt again.
- Default WebKit rules, shipped as protectedMedia rules the user can remove: netflix.com, disneyplus.com, max.com, primevideo.com, amazon.com/gp/video, tv.apple.com, open.spotify.com, hulu.com, peacocktv.com, paramountplus.com.
- Acceptance: Netflix and Disney+ (sign in as a test) play in WebKit through FairPlay. A Shaka Player Widevine demo page, while Widevine is off, moves to WebKit and plays its FairPlay stream, or shows our friendly page if it has none. YouTube stays in Chromium.

3. WIDEVINE GROUNDWORK (dormant until Google approves)
- Build Chromium with `enable_widevine=true`, plus `proprietary_codecs=true ffmpeg_branding=Chrome`, for H.264/AAC/HEVC.
- Wire CDM loading behind `ProtectedMediaService.widevineAvailable`:
  - with CEF: `CefRegisterWidevineCdm(path)`;
  - with our own Chromium host: Chromium's component updater for the Widevine CDM.
  - It defaults to OFF through a build setting, `BOAZ_WIDEVINE_ENABLED=NO`, and no user-facing toggle exists until approval.
- release-mac.sh gets a VMP-signing step.
  - It runs only when `BOAZ_WIDEVINE_VMP_CERT` is set; otherwise it prints "Widevine VMP signing skipped (no certificate)".
  - It goes AFTER codesign and BEFORE notarization; check this order against Google's VMP docs once we have access.
- Write docs/chromium/widevine.md covering: how to apply (widevine.com/contact, product name, expected wait), what Google sends, how to install the certificate into the release keychain, how to flip the build setting, and the verification steps (Shaka Widevine demo, then Netflix in Chromium at HD).
- Once enabled, rule (2a) applies, and the shipped protectedMedia rules for Netflix and the rest stay on WebKit until verified one by one.

4. CHROMIUM HOST: STUDY CREST BEFORE THE S2 SPIKES (new spike S0)
- Crest does NOT use CEF. It builds plain Chromium from Google's official source archive (pinned by SHA-256 in CrestEngines/Chromium/source.lock.json), with an overlay ("host") and a small C ABI to Swift. That may sidestep the CEF limit Wave 0 found (a parent NSView forces Alloy style, so no Chrome-style extensions).
- Read (read-only, don't copy yet): CrestEngines/Chromium/{README.md, ForkMaintenance.md, fork.json, host-inputs.json, source.lock.json, Overlay/, Patches/}, Documentation/Architecture/*, CrestCore/.../Engines/*, and how CrestMac hosts the Chromium view and its extensions.
- Write docs/chromium/spikes/S0-crest.md covering:
  - how their host embeds Chromium in a native NSView;
  - how extensions and the Web Store work;
  - patch count and size;
  - build disk and RAM needs (their docs say 50 GiB free to prepare and a 15 GiB reserve to compile);
  - update cadence;
  - whether their approach fits our sparse APFS volume on the existing external SSD.
- Verdict: CEF (continue S2a/S2b) or a Crest-style own Chromium host. If Crest-style wins:
  - replace the CEF-specific parts of Phases 2 and 10 (BoazChromium stays the only native bridge, but over our host's C ABI);
  - drop S2a/S2b if the host already gives Chrome-style features in our view.
- License: Crest is MPL-2.0, which is file-level copyleft. Prefer reimplementing from what we learn. If any file is copied, it keeps its MPL header, stays MPL, and gets credited in THIRD_PARTY_NOTICES/About. Obtain explicit approval before copying any Crest source file.

5. UNCHANGED
Everything else in the plan stands: Phase 0 prerequisites, the external-SSD sparse image, the performance budgets, dev tools, the UI rules and agent rules. Update the CHANGELOG/help text later: "Mac: Boaz now browses with Chromium, and plays protected video (Netflix, Disney+, Max, Prime Video) in WebKit."
## Persistence and sync decision

BoazKit already supports versioned record types, field merges, and deletion tombstones through CloudKit and folder sync. Site-engine rules fit that model. Add `SiteEngineRule` as a syncable record with stable identity, normalized host, optional path prefix, engine, reason, creation/modification timestamps, and deletion state. Migrate existing stores additively and extend both transports. Keep a deleted shipped-default tombstone so it is not re-seeded. Older clients already skip unknown record types; WebKit-only clients preserve Chromium preferences without trying to instantiate Chromium.

Persist each tab's requested engine with backward-compatible decoding. On a WebKit-only device, use WebKit without overwriting that requested engine in synced library data. Private tabs and private rules remain memory-only. Website data-store identifiers and cookies remain device-local, as the current profile sync contract requires.

Source evidence: `Packages/BoazKit/Sources/BoazKit/Sync/SyncMapping.swift`, `Sync/FolderSync.swift`, and `Store/BoazStore.swift`. This is an implementation decision; no migration or sync code has been changed yet.

## Widevine implementation qualification

See [widevine.md](widevine.md). The pinned CEF headers do not declare `CefRegisterWidevineCdm`; select a supported registration path after S0. Existing cloud signing and notarization are combined, so the VMP insertion point requires release-flow work and Google's actual instructions. No placeholder signing success is acceptable.
