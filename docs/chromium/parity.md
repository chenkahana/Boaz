# Chromium parity ledger

Baseline: Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`. Every row below is **pending**, with source-inventory evidence only. No Chromium runtime behavior is verified. Owners are task packets, not currently running agents. All feature packets depend on the approved host, contracts, and bridge; additional prerequisites are listed where important.

Paths below are repository-relative. Existing behavior is a source reference, not proof that the requested enhancement already exists. Acceptance extends [the existing QA checklist](../qa.md) and [Develop menu inventory](../devtools.md).

| Packet | Feature | Existing implementation | Additional prerequisite | Required acceptance evidence |
|---|---|---|---|---|
| B1 | Navigation, history, modifier clicks, external links | `Apps/macOS/Model/BrowserState.swift`, `Apps/macOS/Views/WebPane.swift` | Navigation contract | Back/forward list, redirect, middle/Command click, target blank, external URL launch |
| B2 | Sign-in popups and opener | `Apps/Browser/PagePopups.swift`, `Apps/Browser/BackingWebView.swift` | Popup lifecycle | Google/Apple/Microsoft sign-in returns to opener; closure cleans up |
| B2 | JS dialogs and file chooser; before-unload requirement | `Apps/macOS/Model/PageServices.swift` | Async continuation contract | Alert/confirm/prompt, cancel, multi-file/directory input, quit during prompt |
| B3 | Downloads and download-manager additions | `Apps/Browser/Downloads.swift`, `Apps/macOS/Model/PageServices.swift` | Request-context cookies | Authenticated download, destination, progress, cancel, supported pause/resume |
| B4 | Find and zoom | `Apps/macOS/Views/WebPane.swift`, `Apps/Browser/PageZoom.swift` | Find callbacks | Match counts, direction, close, per-site zoom, reset and pinch |
| B4 | Gestures and history presentation | `Apps/macOS/Views/WebPane.swift` | Native host input | Swipe navigation with momentum; no accidental navigation while scrolling |
| B4 | Print, PDF, screenshots | `Apps/macOS/Model/BrowserState.swift`, `Apps/macOS/Model/DevTools.swift` | Capture/print API | Native print, cancel, PDF, visible/full-page capture |
| B5 | Residency and session/scroll restoration | `Apps/macOS/Model/BrowserState.swift`, `Apps/Browser/PageResidency.swift`, `Apps/Browser/PageState.swift` | Trusted scripts | Ten-live-page policy, 15-tab unload scenario, restored long page and ChatGPT position |
| B5 | Offline recovery and renderer failure | `Apps/Browser/PageReload.swift`, `Apps/macOS/Views/WebPane.swift` | Error mapping | Offline state, reconnect retry, crash recovery without retry loop |
| B6 | Favicons and theme reporting | `Apps/Browser/Favicons.swift`, `Apps/Browser/SiteColor.swift` | Page-state reporting | Correct icon and page theme without tinting sidebar contrary to design |
| B6 | Quick Window, split view, Peek | `Apps/macOS/Views/WebPane.swift`, `Apps/macOS/Views/BrowserWindow.swift`, `Apps/macOS/Model/BrowserState.swift` | Reparenting lifecycle | Two visible split pages; preview promotion preserves page state |
| B6 | Audio indicators and mute | `Apps/macOS/Views/Sidebar.swift` is integration point | Audio state API | Current audible/muted state and one-click mute; no duplicate indicators |
| B1 | Command bar and keyboard shortcuts | `Apps/macOS/Views/CommandBar.swift`, `Apps/macOS/Model/KeyBindings.swift`, `Apps/Browser/SearchSuggestions.swift` | Focus routing | Command-L/T/W/Shift-T, Command-1..9, Control-Tab inside page inputs |
| S1 | Pinned tabs, Today, Archive, spaces | `Apps/macOS/Model/BrowserState.swift`, `Apps/macOS/Model/MacModel.swift`, `Apps/Browser/PinnedAnchor.swift` | Navigation | Preserve pinned middle-click behavior, anchor return, archive and space isolation |
| P1 | Profiles and private windows | `Apps/macOS/Model/MacModel.swift`, `Apps/macOS/Model/BrowserState.swift` | Context lifetime | No cross-profile cookies; private context disposed on last window close; disk inspection |
| P1 | Persistent permissions and revocation | `Apps/macOS/Model/PageServices.swift` is existing page-service integration point | Verified CEF permission handlers | Camera/mic/location/notification/clipboard/device grants, deny, revoke; no unintended Chrome prompt |
| P2 | Content blocking | `Apps/Browser/ContentBlocking.swift`, `Apps/macOS/Model/MacModel.swift` | Verified library/FFI | Network and cosmetic blocking, site exception, rule refresh without blocking UI |
| P3 | Password fill, save, import, delete | `Apps/Browser/PasswordAutofill.swift`, `Apps/Browser/PasswordViews.swift`, `Packages/BoazKit/Sources/BoazKit/Passwords/` | F3 isolation | Origin/frame-safe fill after authentication, save/update, private fill without save, CSV import |
| P4 | WebKit migration | New migrator; `MacModel.dataStore(for:)` identifies current stores | Verified source-store access | Per-profile copy, flush, interrupt/retry, second launch, preserve source data |
| P4 | Arc import | `Apps/macOS/Import/ArcImportView.swift`, `Packages/BoazKit/Sources/BoazKit/Import/` | Cookie adapter | Existing consent honored, cookies transferred, no raw database-directory copy |
| E1 | Install, enable, uninstall, persistence | `Apps/macOS/Extensions/Extensions.swift` | F2 | Store, CRX, unpacked installs; profile isolation; state survives restart |
| E2 | Toolbar actions, popup, permissions, updates | `Apps/macOS/Extensions/ExtensionViews.swift`, `Apps/macOS/Extensions/ExtensionRefs.swift` | E1 and real visible-tab access | Action, badge, popup, content scripts, MV3 worker, supported update behavior |
| E1/E2 | Required extension cohort | Same extension subsystem | F2 | uBlock Origin Lite, 1Password, Bitwarden, Dark Reader, React DevTools, Vue DevTools, Grammarly, Wappalyzer |
| D1 | Docked/detached DevTools and inspect | `Apps/macOS/Model/DevTools.swift`, `Apps/macOS/Views/DevToolsViews.swift` | Verified DevTools hosting | Bottom/right/detached, remembered placement, inspected target matches selected tab |
| D2 | Responsive design, UA, media, vision | Same Develop subsystem | Typed pinned CDP | Rotation/DPR/custom size; UA metadata; light/dark/print/reduced-motion/contrast and vision settings |
| D3 | Console, source, storage, capture, caches | Same Develop subsystem | Pinned CDP and B4 | Existing menu shortcuts retained, correct tab/profile data, visible errors |
| D4 | Network/CPU throttling and sensors | New additions to Develop subsystem | Typed pinned CDP | Presets and custom values, geo/timezone/locale, reset and visible per-tab override badge |
| D5 | Automation, CLI, Lighthouse shortcut | New additions; `Apps/macOS/BoazMacApp.swift` URL entry point | Endpoint and panel feasibility | Loopback-only opt-in, origin restrictions, visible state, actual client connection, working panel route |
| S1 | Page text and AI summarize/ask/sort | `Apps/Browser/PageText.swift`, `Apps/Browser/Intelligence/`, `Apps/macOS/Intelligence/MacAI.swift` | F3 | Long article extraction and actions; navigation cancellation; unsupported-device behavior preserved |
| S2 | PiP, fullscreen, media keys | `Apps/Browser/PictureInPicture.swift`, `Apps/macOS/Model/BrowserState.swift` | F5 | Auto-float, return to tab, window close, fullscreen, media keys, Document PiP requirement |
| S2 | Codecs, hardware decode, DRM | Engine-dependent behavior; no current CEF code | F4/F7 | H.264/AAC/HEVC, hardware decode, 4K video, working DRM with required approval |
| S2 | Passkeys and security keys | Engine-dependent behavior | F5/F7 | Platform passkey and physical key flows; actual signed entitlement inspected |
| U1 | Native finish and accessibility | `docs/design.md`, `Apps/macOS/Views/Sidebar.swift`, `Apps/macOS/Views/WebPane.swift` | B/S packets | Hover previews, sleeping state, no blank transitions, no invented memory metrics |
| U1 | Input and native integration | Existing native app and WebKit view | F1/F5 | Hebrew/Japanese IME, dictation, emoji, Look Up, VoiceOver, contrast, Reduce Motion, focus and resize |
| U1 | Default browser and onboarding | `Apps/macOS/Onboarding/OnboardingView.swift` | Final app bundle | Default-browser setup and external links work after upgrade |
| R1 | App Store and iOS preservation | `project.yml`, shared `Apps/Browser/` sources | WebKit adapters | Both builds; iOS scroll/password/PiP/popup/blocking smoke checks |
| R2 | Signing, update, rollback | `Tools/release-mac.sh`, `project-dmg.yml`, `Apps/macOS/Updates/Updates.swift` | F7, final bundle | No-publish notarized DMG, signatures, clean-account launch, Sparkle upgrade/delta, WebKit rollback |
| R3 | Performance and dogfood | `docs/qa.md` baseline scenarios | Integrated application | Budgets in README, five samples/scenario, three days without P0/P1 |
| R4 | CEF security updates | New tooling | Pinned custom distribution | Update detection and reproducible rebuild/runbook; 72-hour shipping target |

Reader is conditional on inventory of an existing Mac reader; no new reader is authorized. Safe Browsing integration requires an explicit verified provider configuration before any claimed coverage. No feature gate can be marked passed by substituting a friendly unsupported message for required behavior.
