# Chromium parity ledger

Baseline: Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`. Every acceptance row below remains pending. Source implementation progress is recorded separately below; it does not establish runtime parity. Runtime uncertainty blocks only the acceptance or implementation that needs that finding. Verified pinned APIs and existing contracts permit independent implementation while the custom build runs.

Paths below are repository-relative. Existing behavior is a source reference, not proof that the requested enhancement already exists. Acceptance extends [the existing QA checklist](../qa.md) and [Develop menu inventory](../devtools.md).

| Packet | Engine | Feature | Existing implementation | Additional prerequisite | Required acceptance evidence |
|---|---|---|---|---|---|
| B1 | Both DMG engines | Navigation, history, modifier clicks, external links | `Apps/macOS/Model/BrowserState.swift`, `Apps/macOS/Views/WebPane.swift` | Navigation contract | Back/forward list, redirect, middle/Command click, target blank, external URL launch |
| B2 | Both DMG engines | Sign-in popups and opener | `Apps/Browser/PagePopups.swift`, `Apps/Browser/BackingWebView.swift` | Popup lifecycle | Google/Apple/Microsoft sign-in returns to opener; closure cleans up |
| B2 | Both DMG engines | JS dialogs and file chooser; before-unload requirement | `Apps/macOS/Model/PageServices.swift` | Async continuation contract | Alert/confirm/prompt, cancel, multi-file/directory input, quit during prompt |
| B3 | Both DMG engines | Downloads and download-manager additions | `Apps/Browser/Downloads.swift`, `Apps/macOS/Model/PageServices.swift` | Request-context cookies | Authenticated download, destination, progress, cancel, supported pause/resume |
| B4 | Both DMG engines | Find and zoom | `Apps/macOS/Views/WebPane.swift`, `Apps/Browser/PageZoom.swift` | Find callbacks | Match counts, direction, close, per-site zoom, reset and pinch |
| B4 | Both DMG engines | Gestures and history presentation | `Apps/macOS/Views/WebPane.swift` | Native host input | Swipe navigation with momentum; no accidental navigation while scrolling |
| B4 | Both DMG engines | Print, PDF, screenshots | `Apps/macOS/Model/BrowserState.swift`, `Apps/macOS/Model/DevTools.swift` | Capture/print API | Native print, cancel, PDF, visible/full-page capture |
| B5 | Both DMG engines | Residency and session/scroll restoration | `Apps/macOS/Model/BrowserState.swift`, `Apps/Browser/PageResidency.swift`, `Apps/Browser/PageState.swift` | Trusted scripts | Ten-live-page policy, 15-tab unload scenario, restored long page and ChatGPT position |
| B5 | Both DMG engines | Offline recovery and renderer failure | `Apps/Browser/PageReload.swift`, `Apps/macOS/Views/WebPane.swift` | Error mapping | Offline state, reconnect retry, crash recovery without retry loop |
| B6 | Both DMG engines | Favicons and theme reporting | `Apps/Browser/Favicons.swift`, `Apps/Browser/SiteColor.swift` | Page-state reporting | Correct icon and page theme without tinting sidebar contrary to design |
| B6 | Both DMG engines | Quick Window, split view, Peek | `Apps/macOS/Views/WebPane.swift`, `Apps/macOS/Views/BrowserWindow.swift`, `Apps/macOS/Model/BrowserState.swift` | Reparenting lifecycle | Two visible split pages; preview promotion preserves page state |
| B6 | Both DMG engines | Audio indicators and mute | `Apps/macOS/Views/Sidebar.swift` is integration point | Audio state API | Current audible/muted state and one-click mute; no duplicate indicators |
| B1 | Both DMG engines | Command bar and keyboard shortcuts | `Apps/macOS/Views/CommandBar.swift`, `Apps/macOS/Model/KeyBindings.swift`, `Apps/Browser/SearchSuggestions.swift` | Focus routing | Command-L/T/W/Shift-T, Command-1..9, Control-Tab inside page inputs |
| S1 | Both DMG engines | Pinned tabs, Today, Archive, spaces | `Apps/macOS/Model/BrowserState.swift`, `Apps/macOS/Model/MacModel.swift`, `Apps/Browser/PinnedAnchor.swift` | Navigation | Preserve pinned middle-click behavior, anchor return, archive and space isolation |
| P1 | Both DMG engines | Profiles and private windows | `Apps/macOS/Model/MacModel.swift`, `Apps/macOS/Model/BrowserState.swift` | Context lifetime | No cross-profile cookies; private context disposed on last window close; disk inspection |
| P1 | Both DMG engines | Persistent permissions and revocation | `Apps/macOS/Model/PageServices.swift` is existing page-service integration point | Verified CEF permission handlers | Camera/mic/location/notification/clipboard/device grants, deny, revoke; no unintended Chrome prompt |
| P2 | Both DMG engines | Content blocking | `Apps/Browser/ContentBlocking.swift`, `Apps/macOS/Model/MacModel.swift` | Verified library/FFI | Network and cosmetic blocking, site exception, rule refresh without blocking UI |
| P3 | Both DMG engines | Password fill, save, import, delete | `Apps/Browser/PasswordAutofill.swift`, `Apps/Browser/PasswordViews.swift`, `Packages/BoazKit/Sources/BoazKit/Passwords/` | F3 isolation | Origin/frame-safe fill after authentication, save/update, private fill without save, CSV import |
| P4 | Both DMG engines | WebKit migration | New migrator; `MacModel.dataStore(for:)` identifies current stores | Verified source-store access | Per-profile copy, flush, interrupt/retry, second launch, preserve source data |
| P4 | Both DMG engines | Arc import | `Apps/macOS/Import/ArcImportView.swift`, `Packages/BoazKit/Sources/BoazKit/Import/` | Cookie adapter | Existing consent honored, cookies transferred, no raw database-directory copy |
| E1 | Chromium DMG; WebKit App Store | Install, enable, uninstall, persistence | `Apps/macOS/Extensions/Extensions.swift` | F2 | Store, CRX, unpacked installs; profile isolation; state survives restart |
| E2 | Chromium DMG; WebKit App Store | Toolbar actions, popup, permissions, updates | `Apps/macOS/Extensions/ExtensionViews.swift`, `Apps/macOS/Extensions/ExtensionRefs.swift` | E1 and real visible-tab access | Action, badge, popup, content scripts, MV3 worker, supported update behavior |
| E1/E2 | Chromium DMG; WebKit App Store | Required extension cohort | Same extension subsystem | F2 | uBlock Origin Lite, 1Password, Bitwarden, Dark Reader, React DevTools, Vue DevTools, Grammarly, Wappalyzer |
| D1 | Both DMG engines | Docked/detached DevTools and inspect | `Apps/macOS/Model/DevTools.swift`, `Apps/macOS/Views/DevToolsViews.swift` | Verified DevTools hosting | Bottom/right/detached, remembered placement, inspected target matches selected tab |
| D2 | Both DMG engines | Responsive design, UA, media, vision | Same Develop subsystem | Typed pinned CDP | Rotation/DPR/custom size; UA metadata; light/dark/print/reduced-motion/contrast and vision settings |
| D3 | Both DMG engines | Console, source, storage, capture, caches | Same Develop subsystem | Pinned CDP and B4 | Existing menu shortcuts retained, correct tab/profile data, visible errors |
| D4 | Both DMG engines | Network/CPU throttling and sensors | New additions to Develop subsystem | Typed pinned CDP | Presets and custom values, geo/timezone/locale, reset and visible per-tab override badge |
| D5 | Both DMG engines | Automation, CLI, Lighthouse shortcut | New additions; `Apps/macOS/BoazMacApp.swift` URL entry point | Endpoint and panel feasibility | Loopback-only opt-in, origin restrictions, visible state, actual client connection, working panel route |
| S1 | Both DMG engines | Page text and AI summarize/ask/sort | `Apps/Browser/PageText.swift`, `Apps/Browser/Intelligence/`, `Apps/macOS/Intelligence/MacAI.swift` | F3 | Long article extraction and actions; navigation cancellation; unsupported-device behavior preserved |
| S2 | Both DMG engines | PiP, fullscreen, media keys | `Apps/Browser/PictureInPicture.swift`, `Apps/macOS/Model/BrowserState.swift` | F5 | Auto-float, return to tab, window close, fullscreen, media keys, Document PiP requirement |
| S2 | Both DMG engines | Codecs, hardware decode, DRM | Engine-dependent behavior; no current CEF code | F4/F7 | H.264/AAC/HEVC, hardware decode, 4K video, Netflix/Disney+ FairPlay in WebKit; routing, rule precedence, unsupported-stream fallback; Chromium DRM only after approval |
| S2 | Both DMG engines | Passkeys and security keys | Engine-dependent behavior | F5/F7 | Platform passkey and physical key flows; actual signed entitlement inspected |
| U1 | Both DMG engines | Native finish and accessibility | `docs/design.md`, `Apps/macOS/Views/Sidebar.swift`, `Apps/macOS/Views/WebPane.swift` | B/S packets | Hover previews, sleeping state, no blank transitions, no invented memory metrics |
| U1 | Both DMG engines | Input and native integration | Existing native app and WebKit view | F1/F5 | Hebrew/Japanese IME, dictation, emoji, Look Up, VoiceOver, contrast, Reduce Motion, focus and resize |
| U1 | Both DMG engines | Default browser and onboarding | `Apps/macOS/Onboarding/OnboardingView.swift` | Final app bundle | Default-browser setup and external links work after upgrade |
| R1 | Both DMG engines | App Store and iOS preservation | `project.yml`, shared `Apps/Browser/` sources | WebKit adapters | Both builds; iOS scroll/password/PiP/popup/blocking smoke checks |
| R2 | Both DMG engines | Signing, update, rollback | `Tools/release-mac.sh`, `project-dmg.yml`, `Apps/macOS/Updates/Updates.swift` | F7, final bundle | No-publish notarized DMG, signatures, clean-account launch, Sparkle upgrade/delta, WebKit rollback |
| R3 | Both DMG engines | Performance and dogfood | `docs/qa.md` baseline scenarios | Integrated application | Budgets in README, five samples/scenario, three days without P0/P1 |
| R4 | Both DMG engines | CEF security updates | New tooling | Pinned custom distribution | Update detection and reproducible rebuild/runbook; 72-hour shipping target |

Reader is conditional on inventory of an existing Mac reader; no new reader is authorized. Safe Browsing integration requires an explicit verified provider configuration before any claimed coverage. No feature gate can be marked passed by substituting a friendly unsupported message for required behavior.

## Dual-engine acceptance additions

| Packet | Engine | Required acceptance evidence |
|---|---|---|
| M1 | Both | Persist tab engine across relaunch; explicit page switch; badge; default picker and rule removal; before-unload and edited-form cancel leave page intact |
| M2 | Both | Per-profile engine data separated; WebKit source data retained; resumable cookie copy; private rules/data never persist |
| M3 | Both | Top-frame DRM request routes once per document; user rule wins; embedded cross-site DRM does not route; Move Back removes automatic rule; removed defaults stay removed |
| M4 | WebKit | Signed-in Netflix and Disney+ FairPlay playback; Shaka compatible FairPlay stream or friendly unsupported state |
| M5 | Chromium | YouTube stays Chromium; Widevine off by default; no activation toggle before approval; authorized CDM and signing verified before enablement |

All existing feature rows apply to both DMG engines except Chromium-only extensions and documented per-engine PiP behavior. Developer-tool requirements remain explicit; WebKit capability gaps must be resolved or reported, never silently omitted.

## Native passkey acceptance expansion

Passkeys remain mandatory in PR #70. [The passkey packet](passkeys.md) records pinned Chromium integration, native-window discovery, entitlement preparation and ten explicit runtime scenarios. Reuse Chromium WebAuthn; no JavaScript API replacement or independent authenticator. The real signed host is a prerequisite. Apple Passwords approval, physical security keys, phone interaction and test-account access remain separate dependencies; none count as passed by compilation.

## Shared page-text preparation

`PageText.swift` now contains the engine-neutral value and existing extraction script; `PageText+WebKit.swift` retains the unchanged WebKit adapter. Reader and PageAssistant call sites stay unchanged. Exact script/adapter comparison and Swift 6 typechecking passed for macOS 26 and the iOS 26 simulator using the project's MainActor default isolation. Both project specifications already include `Apps/Browser`, so no source-list changes are needed. This is preparation for Chromium page services, not a passed Chromium extraction or application-build gate.

Scroll-state values/storage and pinned-anchor comparisons are also separated from their WebKit adapters. Exact scroll script/adapter/store comparison passed; paired macOS and iOS Swift 6 typechecks passed. The subsequent App Store and DMG Debug application builds passed with all three extractions included. Chromium runtime parity remains pending.


## Real application implementation checkpoint, 2026-11-13

The ABI4 full Chromium build passed (`20261113T132348.491152Z.log`) and its unsigned and development-signed applications are preserved under `/Volumes/BoazBuild/cef/direct/artifacts/20261113-abi4-*`. The signed prototype rendered local content and HTTPS Example Domain through native controls. An earlier process sample showed an OSCrypt Keychain wait; it subsequently cleared without an agent ACL change. This is prototype evidence, not real-application runtime acceptance.

The real Boaz UI library built and staged successfully at `d1a4a29`, after fixing callback code generation and the product filename. The newer host at `ab93cfc` passed focused C++ compilation with ABI17 (`20261113T155745.143510Z.log`); its incremental full build is underway. Later Swift packets await the next application build. Builds remain serial, inputs frozen, compiled outputs preserved. PR #70 remains draft.

| Work | Integrated implementation | Verification actually passed | Remaining dependency |
|---|---|---|---|
| Engine facade | Observable facade, WebKit and Chromium adapters, typed JSON | Focused Swift 6 checks; real app library build at d1a4a29 | Updated app build and both-engine runtime acceptance |
| Real application | Real BrowserWindow/BrowserState, native page/address field, Quick Window, split layout | Real UI compile/link/staging; host objects compile | Bundled assets/frameworks, signed actual-app launch and focus/lifecycle checks |
| Profiles | Authoritative handles, regular/private contexts, concurrent preparation | Swift checks and native C++ compilation | Private disk acceptance; profile-aware space transitions still need implementation |
| Tabs and operations | History menus, stop/reload, zoom, find counts, native close cancellation, errors/reconnect | Earlier UI build; latest host objects | Rapid close, before-unload, renderer failure, split focus/fullscreen |
| Residency | Native ten-live-page accounting, actual media/capture/PiP/fullscreen protection, isolated scroll capture/restore | Script equivalence, focused Swift checks, native busy-query compile | Integrated app build and 15-tab/long-page/private restoration scenarios |
| External URLs/default browser | Ordered startup batches, existing handler detection/settings action | Native/Swift compilation; installed SDK API check | Signed registration, user-consented default change, cold/warm multiple-URL delivery |
| Page scripts and AI | Exact-document isolated execution; bounded long-page chunk transfer; visible extraction-limit errors | Focused Swift 6 checks; native isolated channel compilation | Long articles, concurrent extraction and navigation/cancellation runtime checks |
| Passwords | Origin-bearing captured token retained across authentication | C++ and focused Swift checks | User-initiated fill UI packet, hostile/navigation/private acceptance; submission/save integration still required |
| Audio/extensions | Native audio indicators/mute and toolbar actions on actual pages | Earlier real app build and host compilation | Playback/mute, complete extension cohort, badges/icons/install/update/permissions |
| Developer tools | Real native menu actions for detached DevTools, Console and inspect mode | Focused Swift checks and native C++ compilation | Detached frontend lifecycle/runtime; docking/emulation/throttling/capture/automation still required |
| Packaging | Bundled UI lookup, Boaz resource bundle, unpublished assembly command | Python syntax checks | Execute assembly with latest artifacts, nested signing, notarization and final branding |

No row is runtime-complete merely because its implementation or compilation passed. No new tests were added.

### Ready work

Continue native page operations, Quick Window/Peek, profile-aware space transitions, extension actions, developer tools, page services, migration, and dual-engine routing against verified source contracts. Adapter compile errors are implementation work, not reasons to wait for the full Chromium link. Root owns contracts, application entry, build configuration and security-sensitive integration; two workers own disjoint bounded packets.

### Dependencies requiring runtime or external evidence

- Native lifecycle, IME, accessibility, extension real-tab identity and passkeys require the signed linked host.
- Codec/hardware decode, complete extension cohort and protected playback require working application artifacts and appropriate test accounts/devices.
- Performance requires the finished app and a quiet reference machine; no measurement during the custom build.
- Developer ID/notarization, update/delta/rollback and distribution size require final packaged artifacts and signing access.
- Widevine enablement requires approval; mandatory protected playback follows the approved WebKit/FairPlay route.
- Three days of dogfooding requires the integrated candidate and elapsed use. No source check substitutes for it.


## Implementation checkpoint — 2026-11-13, native ABI 24 in source

Implementation is not parity acceptance. PR #70 remains draft; code complete has not been reached.

- Integrated native profile download observation, pause/resume/cancel, a real Downloads panel, and pending-download close confirmation. Downloads retain their original Chromium requests; no URLSession refetch. Native object compilation passed at ABI 21; live authenticated-download and cancellation acceptance remain pending.
- Integrated viewport/touch controls, actual runtime UA metadata, acknowledged custom-UA overrides/reset, cached hover/restoration previews, native Print, and bounded document-bound PDF export. Custom UA suppresses hints rather than fabricating metadata. PDF and latest UI require their queued build/runtime pass.
- Integrated per-profile local tab engine choices/site-rule tables, Chromium/WebKit routing, explicit switch warnings, native close/cancel barriers, engine badge/menu and Settings. These preferences do not sync. Mixed-window lifetime patches preserve Chromium's idle state when WebKit tabs remain. The combined ten-live-page policy is implemented; runtime retention, split, close, and unsaved-work acceptance are pending.
- Full native build at `5c35724` passed: `/Volumes/BoazBuild/cef/logs/20261113T164414.764923Z.log`. Focused objects, including both empty-tab lifetime hooks, passed in `20261113T164324.609012Z.log`.
- Real application UI at `02ade75` passed in run `20261113T163510Z-247a0710f2e643df8735dd730f3d8d6e`, resumed build log `xcodebuild-20261113T163735Z-73dca4c147e34285bdbaaa4d358bb69b.log`. This predates mixed routing and PDF. Newer application compilation is queued/running separately; no concurrent heavy builds or benchmarks.
- Earlier signed ABI 18 application reached Boaz onboarding/sidebar/command bar, then crashed in Chromium bookmark-menu construction after becoming main. `2630648` removes that Chrome-menu path for the native host. Native compilation passes; signed navigation remains unverified. Earlier prototype HTTPS rendering does not pass the real-application gate.
- Build failures resolved: non-public content-client API replaced by the actual public embedder UA provider; inherited `LIBRARY_PATH` removed from native build subprocesses; Swift viewport rotation avoids overlapping state writes. Failed logs and outputs remain preserved.

Required open dependencies include protected-media request routing and actual FairPlay playback, automatic password save/subframe workflows, extension cohort and store flows, migration, passkey/input/accessibility runtime checks, complete DevTools coverage, signed distribution/update/rollback, performance/size budgets, and three days of dogfooding. No new tests were added. Builds and source checks above do not establish those gates.

## Implementation checkpoint — 2026-11-13, native ABI 27 in source

- Real application UI at `5c35724` passed: run `20261113T164604Z-97c8e3257ef44518b699a75a6538089a`. Development-signed ABI23 app reached native Boaz controls and rendered DevTools. Performance and Lighthouse tab labels were visible; their workflows have not passed acceptance.
- Normal document requests remained pending. Process sampling found `os_crypt_async::GetKeyTask` waiting in `KeychainPassword::GetPassword`/`SecItemCopyMatching`. Computer Use refused access to SecurityAgent. No Keychain records, access rules, or encryption configuration were changed. User interaction with the system prompt remains necessary for this runtime check.
- Dedicated DevTools owners now use the authoritative native browser type, keeping inspector pages out of BrowserState/session tabs. Frontend focus, resizing, inspector-only close and private-profile lifetime still require the updated application build and runtime pass.
- Protected-media intent now travels from the renderer through a document-scoped Mojo service. Browser-owned page/profile/navigation identities are validated again in Swift before a confirmed engine switch. Private transitions do not save preferences. Successful WebKit page creation may save a protected-media rule; this is not proof of playback. Widevine remains disabled pending approval.
- Existing WebKit user-agent, media, vision and JavaScript menu actions are preserved in the mixed-engine application. Saved custom viewport presets and typed Chromium media/vision adapters are integrated; UI/typecheck/runtime acceptance remain pending.
- Focused native compilation at `905ef16` passed in `20261113T170728.716394Z.log`, including PDF, renderer EME sender and document-bound browser receiver. Full compilation subsequently found a protected `RenderFrameImpl::GetWeakPtr` call in the upstream EME patch (`20261113T170815.677867Z.log`); correction is underway. Compiled outputs and failed logs are preserved.

Code complete has not been reached. No production release, appcast change, acceptance waiver, new test, or benchmark was performed. The draft PR retains all earlier feature, DRM, distribution, performance and dogfooding gates.

### Subsequent verified build checkpoint

- Real UI at `969636e` passed in resumed run `20261113T171123Z-3affe4a7e8f24d01b2b24f8a2a038ad5`. This includes the dedicated DevTools shell, source viewer, protected routing, presets and media/vision controls. The first attempt exposed a Settings catch-variable assignment; fixed before the successful rerun.
- Focused native compilation at `81c25f6` passed (`20261113T171804.453205Z.log`), followed by the full native build (`20261113T171922.214644Z.log`). This includes the incremental EME callback-lifetime correction, native WebAuthn window adapter, cache-clear observer/profile retention, and bypass-cache reload. The matching UI build is queued separately.
- Cache clearing removes resource caches only, preserving cookies and Cache Storage. It retains a retiring private profile until completion; shutdown drains outstanding work. Reload targets the original active document only and preserves Chromium's form-resubmission confirmation.
- Source now includes acknowledged network/CPU and sensor overrides through typed internal protocol commands. Network uses the pinned rule-based and navigator-state commands. CPU, navigator state, timezone and locale can affect shared renderers; UI must not claim strict per-tab isolation. Worker coverage and cached-response throttling are not assumed.
- Locale/timezone require a trusted internal protocol client. That client exposes only typed application operations, retains owned HTTP(S) primary-frame attachment checks, and denies local file reads/writes and unsafe operations. No arbitrary protocol endpoint is introduced. Geolocation emulation does not grant site permission.

### Signed ABI28 runtime findings

The matching UI at `81c25f6` passed in run `20261113T172148Z-25920c03de0c4ab181d0d753f8392564`. The staged, development-signed candidate is preserved under `20261113-abi28-native-application-signed`.

Observed: native Boaz launch; existing test-profile tabs visible; dedicated DevTools window renders without Boaz sidebar/session UI; Lighthouse panel loads with its controls and correctly refuses to audit an uncommitted/non-HTTP document. Normal HTTPS loading still did not commit. Inspector Cmd-W failed: Chromium terminated at `ReadAnythingSidePanelController::TabWillDetach`, where a missing Chrome side-panel coordinator is permitted only for tests/WebUIBrowser. The native host has no Chrome side panel. A narrowly scoped native-host detach correction is required before inspector-close acceptance. This is a runtime failure, not a passed lifecycle gate.

The earlier ABI23 app exited after the native Quit action; the initial still-visible window was transitional. No force termination, Keychain reset or access-rule change was used.


### ABI30 runtime and subsequent source integration

Native and matching UI at `f2f166a` passed. Native logs: `20261113T173247.385494Z.log` and `20261113T173529.218570Z.log`; UI run: `20261113T173717Z-ea5d02f1038d46d08f8b13bb3ddb7e84`. Development signing completed for `20261113-abi30-native-application-signed`. This is not Developer ID notarization.

Inspector Cmd-W still failed, now with SIGSEGV rather than the earlier reading-mode assertion. Crash `Chromium-2026-11-13-194927.ips` identifies ContextualTasksCloseButtonController destruction after its observed dependencies. Source comparison found the native window omitted Chromium's required `TearDownPreBrowserWindowDestruction` hook. Commit `dc39799` adds it before native window teardown. Its focused native compile passed at frozen checkpoint `25726ab` (`20261113T175245.528436Z.log`); full build is underway. Inspector-close acceptance remains failed until the signed runtime retest passes.

Source integrated since that checkpoint:

- ABI32 authenticated loopback automation, default off, with private per-run connection records, Origin/fetch-metadata rejection, bearer authentication before HTTP/WebSocket routing, and enterprise-policy revocation. Settings distinguish next-launch configuration from actual running status. Browser-origin rejection, active-client shutdown and endpoint acceptance remain unverified.
- Bundled native `boaz` CLI, explicit owning-app routing, DevTools URL commands, restart-only automation launch, packaging/signing and a Settings installer that refuses conflicting user files. Compilation and installed-command acceptance are pending.
- ABI33 full-page PNG capture through the existing typed protocol owner, cancellation and shutdown accounting, bounded accepted output, and native save UI. Capture targets the currently laid-out document; it does not scroll to load more content. Preflight limits are not a guarantee of peak renderer memory on a changing page. Runtime output and cancellation checks remain pending.
- Site-engine choices now have an additive synced record migration, validated deterministic identity, encrypted host/path fields, deletion tombstones and database-driven cache invalidation. Seed defaults use an old modification timestamp so they cannot resurrect newer deletions. Local source tables remain preserved. CloudKit schema deployment and multi-device acceptance remain release dependencies.

Ready source implementation continues while frozen build inputs compile. At this earlier checkpoint normal navigation was unresolved; the observed Keychain wait did not establish its cause. Later runtime evidence appears below. No production engine switch, release, new tests or performance claim has been made.


### ABI32 verified lifecycle correction and ABI34 build

At frozen checkpoint `25726ab`, the full native build passed (`20261113T175434.274951Z.log`) and matching UI passed in run `20261113T175959Z-52ff19c06f9f4d229cb3a64f674961fd`. Development signing produced `20261113-abi32-native-application-signed`. Inspector Cmd-W now closes only the inspector and leaves the real Boaz window alive. The bundled CLI `--help` exits successfully. Whole-application Cmd-Q remained waiting; its bounded sample showed the main event loop and a worker blocked in the known Keychain request, without proving the quit blocker. The owned test process was subsequently stopped with SIGTERM; that is not a clean-quit pass. Nonsecret shutdown-state diagnostics are included for the next runtime check.

At `38c194c` the corrected docking container and full-page capture passed focused native compilation (`20261113T181455.730303Z.log`). The full native build at `ac5dfab` passed (`20261113T181645.098202Z.log`), and its matching application build passed in `20261113T182211Z-4ba6ec520bb04c1186554aa9c2b6bc96`. This compiles the synced-rule migration, full-page UI, explicit Storage/Performance/Lighthouse actions, native dock containers, CLI startup coordination and Boaz icon assembly. Runtime docking, capture, migration and shutdown verification are pending the signed ABI34 candidate.

Focused-frame password targets and exact-document clones are integrated after that frozen build. They validate the full frame ancestry, reject opaque/fenced targets, cancel on affected frame/ancestor navigation, and preserve unrelated sibling-frame operations. Manual fill now uses one captured frame throughout preparation, authentication, fill and cleanup. Native/Swift compilation and hostile-frame/auth-delay acceptance are still pending. Automatic save/update and focus-suggestion UI remain implementation gaps.

### ABI34 runtime and ABI36/37 implementation checkpoint

The development-signed ABI34 application at `ac5dfab` launched with the isolated `boaz-application-home`. Native Develop → Show Lighthouse opened the actual Lighthouse panel. DevTools transitioned from right docking to bottom docking to a detached native inspector; Cmd-W closed that inspector without crashing the Boaz window. This verifies those transitions and the panel entry point, not audits, page accessibility, split-view geometry or remembered per-window state. Lighthouse correctly refused an audit while the underlying HTTP navigation had not committed.

Cmd-Q diagnostics identified a separate lifecycle defect: `RegisterBrowserCloseCancelled` also reports `kDeniedUnloadHandlersNeedTime`. The bridge cleared its exit request for that temporary state, leaving zero windows but `requested=0` and `finished=0`. Commit `d2daa09` retains the request unless the status is an actual user/policy denial. Runtime acceptance of that correction remains pending. The owned ABI34 process was stopped with SIGTERM after recording the evidence, not counted as a successful quit.

Frozen ABI36 checkpoint `73aac98` passed focused compilation (`20261113T183502.590465Z.log`) and the full native build (`20261113T183748.933900Z.log`). This includes exact focused-frame targets, clone validity and native focus events. Its matching Swift application build is running separately. The integrated native password offer validates eligibility in the isolated document and accesses credentials only after the explicit fill button. It is not automatic account selection or save/update; those remain gaps.

ABI37 source adds per-window current/last DevTools docking state, snapshot restoration before tab activation, private in-memory state, native preference interception and matching layout state. The patch handles current frontend kebab-case preference names as well as legacy aliases. Restoring over an already open inspector returns an explicit unavailable result. Compilation and two-window/relaunch acceptance remain pending. Quick Window focus offers are connected to the same document-bound path.

WebKit release preparation now uses an exclusive per-run directory and retains earlier and failed artifacts. No production signing, notarization, update installation, delta acceptance or release publication was performed at this checkpoint. PR #70 remains open and draft.

### Native password and extension implementation, ABI40

The ABI37 checkpoint `9f907ea` passed focused/native builds (`20261113T184410.174816Z.log`, `20261113T184737.654684Z.log`) and the application build in `20261113T184936Z-9d165c83fb2942d389cc1eacc84a00f6`. Its development-signed candidate is `20261113-abi37-native-application-signed-v2`. An initial assembly used a directory name instead of `Chromium.app`; signing rejected it, the output was preserved, and the corrected assembly signed successfully. The assembly tool now rejects that mistake before copying.

Runtime Cmd-Q now drains windows with `requested=1`. It subsequently exits with Chromium's teardown watchdog status 2, not a clean quit. The timed sample in that candidate's `quit-sample.txt` shows the browser main thread reaching `BrowserProcessIOThread::ProcessHostCleanUp` and waiting for the NetworkService process. A concurrent browser worker is blocked in `GetKeyTask → KeychainPassword → SecItemCopyMatching`. The sample does not prove why the network process fails to exit. Chromium allows that child ten seconds while its Mac teardown watchdog allows ten seconds total. Neither deadline was weakened. Normal navigation and clean shutdown remain unresolved runtime gates.

Integrated source now includes:

- Browser-issued, single-use submission proofs with an immutable source origin, bounded credential payload and expiry; normal sign-in, SPA and confirmed change/reset detection pass through those proofs. Native Save requires explicit consent, device authentication, and a fresh exact-document check before synchronous Keychain save. Private submissions are discarded. This is implemented source, not successful password acceptance evidence.
- External password ownership suppresses Chrome password-store reads/writes, generation/filling and duplicate save prompts while retaining the existing parser and origin/certificate checks. Credential Management password-store calls acknowledge without persistence and password-get returns unavailable; WebAuthn remains separate.
- Installed Chromium extension listing, policy-aware Disable and re-enable only when the sole disable reason is user action and retained grants cover active permissions. No permission escalation is silently granted.
- Signed local CRX installation through Chromium's verifier and native localized permission consent, plus explicit developer-folder trust before unpacked loading. Unpacked file/private access remains disabled. Installation jobs are serialized per profile and retained through actual completion; quitting drains accepted jobs before Chromium teardown.
- Shared native standard store consent, native policy-block notices and Safe Browsing friction decisions. The existing Chromium policy and warning checks remain in place. Parent approval, remaining store-specific UI, actual Google store availability, updates and the full eight-extension cohort remain unresolved.

Compile correction evidence: ABI39's full build exposed an optional-result callback mismatch; the callback now returns `std::nullopt`. Earlier inline virtual defaults moved to the implementation file. ABI40's focused compile at `9c14e0e` compiled the new native password, management, unpacked-install and shared-consent sources, then found the CRX error header path. After correcting that path, the focused pass at `356d2be` succeeded (`20261113T191445.777248Z.log`). The complete build and matching Swift application pass for the combined implementation remain pending. No tests were added and no production release or appcast changed.

### Extension management and migration review, ABI43

Integrated policy-checked removal with native confirmation and actual registry refresh; native review of permission-increasing updates with exact extension-object revalidation and cancellable consent; suppression of Chrome post-install/disabled bubbles; per-tab titles, real badge values, and cached action icons with observer-driven refresh. Ordinary upstream automatic updates already start through the normal profile/ExtensionService initialization. Actual update delivery and the eight-extension cohort remain runtime gates.

The explicit previous-extension review reads a user-selected `installed.json`, bounds its size, rejects orphan/duplicate records, and keeps profile identities separate. Store entries open Chromium store tabs for fresh consent. Developer entries require choosing the original developer folder. This is a recovery/reinstallation interface, not completed automatic migration: installation receipts, prior enabled-state restoration, resumable stage journals and actual previous-store access remain outstanding. No original extension payload, cookies, passwords or user data are modified by inventory review.

Verification passed:
- ABI40 checkpoint `5ce0fa6`: complete native build `20261113T191615.751998Z.log`; matching Boaz UI run `20261113T192402Z-0fbd6570a020492b95b1565e70c3b74f`.
- ABI41 checkpoint `8922eda`: complete native build `20261113T192629.151746Z.log`.
- ABI42 checkpoint `94e4807`: complete native build `20261113T193151.816785Z.log`; matching Boaz UI run `20261113T193520Z-8d7144cdad9944e8beb28ef12f481e53`.
- Swift conditional parsing for new management/action/migration code passed. No tests added.

ABI43 combined verification is pending. The guarded build uses a frozen validation checkout; independent implementation continues in worker worktrees.

A bounded ABI37 shutdown recheck sampled its identified NetworkService child during quit. `network-quit-sample.txt` contains image metadata but no call graph; it cannot establish the child wait's cause. The app again exited with teardown-watchdog status 2. Neither Keychain access rules nor shutdown deadlines were changed. Normal HTTP navigation and clean quit remain unresolved; this failed runtime check does not invalidate the independent implementation/build progress.


### Native permissions and WebKit preservation, ABI44/45

ABI43 checkpoint `f3bab52` passed the complete native build (`20261113T193855.755881Z.log`) and matching Swift application build (`20261113T194113Z-f4f4122c38cf40239589ad3d80bf7c0b`). Its development-signed application displayed the native extension management sheet. Internal component extensions appeared there; `f615122` filters them from the user list. That correction still needs runtime verification. Ordinary HTTP loading and clean quit remain failed gates. The attempted `chrome://version` navigation went through the HTTP-only command bar's search path and provides no evidence about local Chrome-page rendering.

Optional extension permissions now use Chromium's requester-bound continuation with exact extension identity, document/worker lifetime, native consent and cancellation. The first native build exposed a factory include and C++ native-window type error. After `1a2f44c`, the complete native build passed (`20261113T195050.750671Z.log`).

ABI44 checkpoint `5b2d57a` passed the complete native build (`20261113T195527.698213Z.log`) and matching Swift application build (`20261113T195949Z-d0191f0754b446ecb8c2dfbd57a4d6a5`). It adds explicit video/Document PiP routing through the actual media session and native site-permission read/reset controls for camera, microphone and notifications. Decisions remain in Chromium; the UI reports stored/effective state and policy restrictions. These are build results, not runtime permission or PiP acceptance.

ABI45 source adds typed native location consent, approximate/precise saved-state reporting and scoped reset, plus the existing automatic-PiP preference at Chromium's eligibility check. Disabling the preference prevents future automatic triggers; it does not forcibly close existing PiP. ABI45 compilation and runtime acceptance remain pending.

Isolated WebKit generation is available through `Tools/generate-webkit-project.sh appstore` and `Tools/generate-webkit-project.sh dmg`. Generated plists, entitlements and Xcode projects occupy separate `build/webkit-appstore` and `build/webkit-dmg` directories. The prior preservation build failed because its relocated project referenced a nonexistent Info.plist. The corrected generator preserves the original target properties and gives the local package and generated files absolute paths. The WebKit release script uses the isolated DMG project without rewriting the main project. Shell syntax and diff checks passed; the corrected Mac preservation build is underway.

Content blocking remains incomplete in Chromium. The existing WebKit rules cannot be losslessly reduced to extension DNR rules because of regex quotas, top-URL conditions, ordered exceptions and cosmetics. A pinned adblock-rust boundary is being implemented, with production hooks investigated separately. No subset is counted as parity. Cookie migration is also blocked on verified preservation of partition and SameSite metadata through the actual previous-store export path; source cookies are not copied or broadened.


Preservation checkpoint `7232d4a`: the isolated Mac App Store WebKit configuration compiled, linked and reported `BUILD SUCCEEDED` in `20261113T201214.214393Z.log`. Its LaunchServices registration subprocess stalled in bookmark creation at `getxattr` on the image-backed volume; the captured stack is `direct/verification/20261113-webkit-preservation/lsregister-sample.txt`. Only that verified owned subprocess was stopped. Xcode completed successfully afterward, so compilation is passed but OS registration is explicitly unverified. The iOS configuration, including BoazKit and extensions, reported `BUILD SUCCEEDED` without intervention in `20261113T201625.911392Z.log`. These unsigned Debug builds do not verify installation, entitlements or runtime behavior. WebKit DMG verification remains queued.

Content-blocking source now has a pinned immutable Rust FFI and a sequenced Chromium request proxy. The library boundary rejects unsupported rules/resources with bounded diagnostics instead of silently dropping them. Cargo's 60-package graph is locked; registry checksums and the exact adblock-rust commit were checked. The proxy preserves native request/redirect forwarding and can block before network delivery. Document factories use browser-owned isolation origins; unavailable worker/navigation contexts remain explicit. Neither component is connected to production filtering yet. Library compilation, complete decision semantics, pinned lists, site exceptions, live profile preference updates, all-frame cosmetics and coverage gaps must pass before this becomes a working blocker.


### Navigation and shutdown checkpoint, 2026-11-13

Status: **Boaz running Chromium locally**, with required parity and release acceptance still pending.

- Frozen ABI45 `624c8d2` passed native and matching application builds. The signed application uses team `DPF8459C2J` and the preserved `boaz-application-home` profile. Native build log: `20261113T203616.971157Z.log`; UI run: `20261113T204014Z-e7d2d097d99c43b8a7697733a5259c99`.
- The earlier HTTP failure now has a concrete crash path: HTTPS fallback reaches `AskBeforeHttpDialogController`, whose Views tab-dialog host is absent in Boaz. The native warning patch preserves Chromium's reason-specific text, decision callbacks, metrics, safe focus, and cancellation. It does not bypass the warning or change HTTPS/security policy.
- Frozen `df6b21e` compiled and passed development signature verification. Build `20261113T210849.642360Z.log`; signing `20261113T211130.384663Z.log`. Runtime visibly rendered Example Domain and Wikipedia. The accessibility tree exposed their page content. A typed Wikipedia search value survived switching to Example Domain and back. Closing Wikipedia returned to the existing page.
- Plain HTTP `http://neverssl.com` displayed the native warning with Go back focused. Escape exposed another real failure: Chromium's no-history back action loaded its own New Tab Page, which crashed at `new_tab_page_handler.cc:1215`, `CHECK(footer_controller)`. The follow-up patch selects `about:blank` for this native-host safe fallback. Compilation and runtime verification of that correction remain pending. Continue-to-HTTP has not been exercised; no security warning was bypassed.
- One normal native-menu Quit on the preserved-profile ABI45 process completed with exit code 0. Log records shutdown accepted and windows draining to zero; subsequent process inventory found no owned browser, helper, or crashpad processes. Reopening with the same development identity and profile restored Example Domain. This is one clean-quit pass, not acceptance of all crash/loading/dialog teardown scenarios.
- Earlier live browser samples contained a Keychain encryption-key wait while NetworkService remained responsive. Later samples no longer contained that wait and navigation completed. This correlation does not establish the cause or permanent resolution of the earlier stall. No Keychain item, access rule, security flag, or shutdown deadline changed.

Runtime logs and bounded samples are under `/Volumes/BoazBuild/cef/direct/verification/20261113-navigation-shutdown`. Runtime acceptance must continue with the safe-back correction, repeated HTTP/HTTPS loads, warning cancellation/navigation, and quit/reopen. Development signing is not notarization.

Independent implementation integrated: exact blocker asset hashes and licenses with seven explicit optional exclusions; schemeful-site popup exception matching; explicit verified frozen blocker-receipt selection for builds. Parser/packaging evidence does not establish production request blocking. ABI46 blocking preparation is still unfinished and excluded from the ABI45 runtime candidate.
