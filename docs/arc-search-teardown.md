# Arc Search teardown → iPhone Duo app brief

Target: `~/Downloads/Arc Search - Find it, Faster.ipa` (SHA-256 `55f44569…f3a6`), bundle `company.thebrowser.ArcMobile2`, v1.46.1 (build 73469.2, built 15 Jan 2026), iOS 16+, iPhone + iPad. The binary was already decrypted (decrypt.day marker).
Method: static only. I unpacked the bundle and read Info.plist, entitlements, App Intents metadata, the embedded demo payloads, `package-list.json`, and strings from the 44 MB main binary, including 534 embedded `Module/File.swift` paths. Nothing was executed.

Labels: **[O]** observed in the bundle · **[I]** inferred · **[?]** unknown.

---

## 1. Architecture [O]

| Layer | What ships |
|---|---|
| UI | UIKit shell (TabContainer/TabStack view controllers) plus SwiftUI features, built with **The Composable Architecture**. Uses `swiftui-introspect`, Lottie, Pow, Motion and Metal (`default.metallib`, the glow/hologram effects). |
| Modules | `MobileSearch`, `MobileSpaces`, `MobileTabKit`, `MobileHome`, `MobileOnboarding`, `MobileThemes`, `MobileToasts`, `AskArc`, `LLM`, `WebSearch`, `Scraping`, `SidebarSyncCloudKit`, `FirebaseSidebarSync*` |
| Storage | GRDB (SQLite) for archive and history, LevelDB through Firestore, app group `group.company.thebrowser.ArcMobile2` |
| Sync | CloudKit **and** Firebase/Firestore sidebar sync with the desktop Arc app (Spaces, folders, pins). Sodium for encryption, with a recovery-phrase flow. |
| Web | WKWebView, Autoconsent (cookie banners), content blocking rule lists from `arc.net/api/adblock/{basic,cookies,privacy}`, the Reeeed reader view, `DarkModePlugin.js`, YouTubePlayerKit |
| AI | A `UniversalLLMClient` that goes through an Arc proxy: `/api/open-ai-chat-stream`, `/api/claude-stream`, `/api/open-ai-speech`, `/api/open-ai-transcriptions`. Model IDs found as strings: gpt-4.1, gpt-4o, o3-mini, o4-mini and others. `Tiktoken` for token budgeting. **No provider keys in the client [I].** |
| Ops | LaunchDarkly feature flags, Segment, Datadog, Sentry |

## 2. Feature inventory

| Feature | Evidence [O] | How it works [I] |
|---|---|---|
| **Browse for Me** (AI results page) | `SearchIntent(query, browseForMe)`, `BrowseForMeResultViewModel`, `AskArcGenerator`, `AskArcGeneratedPage`, `WebSearch/{Google,Brave,GoogleImage}SearchEngine`, `WebSearchWithFallback`, `Scraping/HTMLScrapingRulesProvider`, `WebViewHTMLFetcher` | Runs the query on a search engine (Google scraped in a hidden WebKit view, with fallbacks) → fetches and scrapes the top pages → the LLM writes a structured page → the page streams in section by section |
| Generated-page schema | `paris_to_do.json` and similar files | `{title, category, imageSearchQuery, prohibited, answer, sections[]: {sectionId, title, emojiBullets[], citedSubstring, followUpQuestions[], properEntitiesWithContext[]{namedEntity, qualifier}}}`, plus `allResults[]` (sources) and `quoteCache` (citation → source) |
| OneBox instant answers | `AskArcOneBox{Weather,Time,Currency,UnitConversion,Translation,Definition,Age,Info}View` | Typed cards rendered above or in place of the generated page |
| **Pinch to Summarize** | `TabContainerViewController+PinchToSummarize`, `TabSummarizer`, `TabSummaryViewController`, `jfk-p2s.json` | A pinch on the tab triggers an LLM summary. Schema: `{quickSummary, details[]{icon, label, info}, pageFractionRead}` |
| **Ask on Page** | `AskInPage{View,ViewModel,QuestionView,SuggestionsView}` | Q&A over the current page, with suggested questions |
| **Call Arc** | `CallArcViewModel`. Motion-state fields `accelerationThreshold`, `portraitOrientationZBounds`, `ProximityMonitoringEnabled`, `CallActive`. Speech-recognition purpose string mentions "lift your phone to your ear". About 40 filler clips (`Let_me_check.aac`, `One_sec.aac`, `Hmm.aac`). `UIBackgroundModes: audio` | Raising the phone to your ear (accelerometer + proximity sensor) starts a voice call. Speech is transcribed, sent to the LLM, and answered with streamed TTS. **Filler clips play while the answer is pending, to hide latency.** |
| Voice Search | `VoiceSearchIntent`, `VoiceSearchViewModel`, `WaveformView` | Dictation into search |
| Tabs | `TabStack*`, `TabPagingGestureInteractionController`, `TabPanSelectionGestureInteractionController`, `WebContentGestureCoordinator` | A tab stack with swipe paging and gesture navigation |
| Auto-archive | `TabArchiveController`, `ArchiveStore` (GRDB), "Archive Inactive Tabs", `ArchivedReason` | Inactive tabs expire into a searchable archive |
| Spaces / Pins / Favorites | `MobileSpaces`, `SpacePagingControl`, `PinURLCoordinator`, `FavoritesStore` | Synced from desktop Arc. Spaces are paged horizontally. |
| Content modifiers | `WebContentModifier{Manager,ReportView,RemediationFlowController}`, Autoconsent | Ad, tracker and cookie blocking, with a "site broke" report and fix flow |
| Reader / dark mode | `ReaderWebView`, Reeeed, `WKUserScript+DarkModePlugin` | |
| Incognito, Downloads, History, Site settings | matching views and stores | |
| Themes, alternate icons | `MobileThemes`, 12 alternate icons | |
| LLM page categorization | `WebContentControllerImpl+LLMCategorization`, a "determine what kind of website" prompt | Classifies the page type to adapt the UI [I] |
| System hooks | URL schemes `http`, `https`, `arc`, `arcmobile2`. Default-browser entitlement. App Intents: Search, Voice Search, Call Arc. Quick actions. Home- and lock-screen search widgets. Share and Action extensions. | |

## 3. iPhone Duo constraints (sourced; not checked on a device)

- Book-style fold. Outer screen 5.4" (1398×2034). Inner screen 7.6" (2670×1878). Both are 1.41:1, 120 Hz.
- Estimated logical sizes: **outer ≈ 466×678 pt** (portrait, compact width) and **inner ≈ 890×626 pt** (landscape-shaped, roughly iPad-mini width). The Dynamic Island appears on both screens.
- iOS 27.1 adds side-by-side multitasking, layouts that adapt to orientation and **hinge angle**, and a keyboard on one half when partly folded. Apps built with older SDKs are pillarboxed.
- On the iPhone Duo simulator the cover screen measured **466×678 pt**, which matches the estimate.

### iOS 27.1 foldable APIs (read from the local Xcode 27.2 SDK)

| SwiftUI | UIKit | Use for |
|---|---|---|
| `ArrangementView(primary:secondary:)` + `.arrangementViewStyle(.automatic / .split / .overlay)`. `SplitArrangementViewStyle.axes(_:)` | `UIArrangementViewController` with `UISplitArrangement` / `UIOverlayArrangement` (placements `.primary` / `.secondary`, min/preferred/max dimensions) | Two-pane layout that adapts as the device folds |
| `.onHingeChange { old, new in }` → `DeviceHingeContext.hinge: DeviceHinge?` with `status` (`.closed`, `.partiallyOpen`, `.fullyOpen`) and `angle: Angle` | `UIHingeInteraction(updateHandler:)` → `UIHinge.status`, `UIHinge.angle` (CGFloat) | Posture, and effects driven by the angle |
| `GeometryProxy.reservedRegions(kind: .division / .occlusion, options: .includeInactive)` → `ReservedRegion{frame, margins, isActive}` | `UIView.reservedRegions(ofKind:options:)` | Keeping content out of the crease and the camera area |

Apple's guidance, as the third-party docs quote it: drive **layout** from posture and size class, and use the raw **angle** only for interaction and effects. Sources: [iPhone Duo by Examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples), [slekens.dev](https://slekens.dev/en/blog/iphone-duo-xcode-27-1-six-foldable-apis/), [ecorpit](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/).

## 4. Design: one app, three postures

**Folded (outer, compact)**: keep Arc Search's single-column model. Search-first home, the tab stack, and Browse for Me as one scrolling page. Raise-to-ear calling works best in this posture.

**Unfolded (inner, ~890 pt wide)**: two panes by default, which is the main difference from Arc.
- *Browse for Me*: generated answer on the left, **live source pane** on the right. Tapping a citation (`citedSubstring` → `quoteCache`) loads the source on the right and scrolls to the quote. Arc has to navigate away for this; with two panes the reader stays on the answer.
- *Reading a page*: page on the left, the Pinch-to-Summarize card plus Ask-on-Page chat as a persistent right rail (instead of Arc's overlay sheet). `pageFractionRead` can drive a progress marker in the rail.
- *Tabs*: a Spaces/pinned sidebar (as in desktop Arc) next to the web view. Drag a tab across the fold to split it.
- Pinch-to-close on the fold can turn the summary pane on or off.

**Half-folded (laptop/tent)**: content or video on the top half; voice orb, Ask input and keyboard on the bottom half. "Call Arc" becomes a hands-free desk mode with the waveform at the bottom and the generated page at the top.

**Continuity**: unfolding must keep the same tab, scroll position and AI session. Model the state once (TCA or `@Observable`), keep both layouts as pure views, and choose the layout from horizontal size class plus posture.

## 5. Suggested build stack

- SwiftUI-first. `NavigationSplitView` / column layouts chosen by size class, wrapping `WKWebView`. Arc's TCA is optional and plain `@Observable` is enough at this scale.
- **Your own backend proxy for LLM, STT and TTS.** Never ship provider keys; Arc proxies through arc.net. Use structured JSON output with a schema like §2's, streamed section by section.
- Search: a paid search API (Brave Search, Bing, or Kagi) **instead of scraping Google**, which is brittle and against Google's terms.
- GRDB for history and archive. CloudKit for sync. Autoconsent plus WKContentRuleList for blocking.
- App Intents (Search, Ask, Call), widgets, and a Share extension, matching Arc's set.

## 6. Don't copy

The feature *ideas* are fine to build on. Arc's names ("Browse for Me", "Call Arc", "Pinch to Summarize"), icons, audio clips, Lottie/Metal assets, prompts and its `arc.net` endpoints are not. Use original assets and your own backend.

## 7. Limits / unknowns

- Static analysis only. No runtime or traffic capture, so request and response bodies for the `/api/*` proxy and the server-side prompts are **[?]**. I saw only fragments of the client-side prompts.
- I found the Call Arc trigger thresholds as field names, not values.
- The inner screen size (≈890×626 pt) is a third-party estimate. The headless simulator has no hinge control, so the unfolded and half-open layouts compile but have not been checked at runtime.

## 8. Prototype: `Folio/` (working name)

- Run `xcodegen generate` in `Folio/`, then build the `Folio` scheme. It targets iOS 27.1 on iPhone.
- Folded: one column. Citations push the source page, opened with a `#:~:text=` link so the quote is highlighted.
- Unfolded: `ArrangementView` shows the answer on the left and the live source on the right. Half-open: the page on top, ask/summarize/voice controls on the bottom.
- `FoldGlow` places a gradient line on the `.division` region, with brightness driven by hinge angle.
- `Assets.xcassets/Palette`: Arc's brand blue, a 12-step indigo scale (light and dark), peach/electric/violet gradient stops, and text and card tokens. `Theme.swift` exposes them.
- The icon is an original open-book-plus-sparkle mark with light, dark and tinted variants, regenerated by `swift Tools/make-icon.swift <appiconset>`.
- `SampleAnswerProvider` returns bundled JSON. Swap it for a provider that calls your own backend.

Sources for Duo specs: [Wikipedia](https://en.wikipedia.org/wiki/IPhone_Duo), [Mac Observer](https://www.macobserver.com/tips/round-ups/iphone-duo-displays-explained-7-6-inch-inner-5-4-inch-outer-120hz-3000-nits/), [screensize.io](https://www.screensize.io/blog/iphone-duo.html).
