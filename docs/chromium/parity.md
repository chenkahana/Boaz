# Chromium parity ledger

Baseline: Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`. Every row below is **pending**, with source-inventory evidence only. No Chromium runtime behavior is verified. Owners are task packets, not currently running agents. All feature packets depend on the approved host, contracts, and bridge; additional prerequisites are listed where important.

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
