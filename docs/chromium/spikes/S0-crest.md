# S0: Crest source study and host decision

Recorded 2026-11-13. Read-only checkout of [Crest](https://github.com/pauljoda/Crest) at `4110ef03ed71cf2480a613faf43290839e712703`. No Crest scripts, build, or application were executed. No Crest source was copied into Boaz production files. The clone is an ignored research artifact.

## Verdict

**Select a direct Chromium host for Boaz.** Keep the CEF prototype, source and interrupted build outputs for reference. Freeze CEF-specific S2a/S2b implementation; replace those route experiments with a direct-host proof carrying the same native UI, extension, lifecycle, accessibility, and split-view acceptance requirements. This passes the source-study decision only. It does not pass any runtime architecture gate.

Judgment: CEF currently requires new public native-view, tab-host, extension-action, and isolated-script interfaces. A direct Chromium host exposes the underlying native page, real browser/tab model, action runner, and isolated-world APIs already needed by Boaz. It avoids maintaining those additional CEF adaptation layers. The tradeoff is direct ownership of Chromium lifecycle and upstream integration changes. Crest's full implementation is substantial and must not be described as a tiny ready-made bridge.

## Deterministic source evidence

Paths below are relative to the pinned Crest tree. [Browse the inspected revision](https://github.com/pauljoda/Crest/tree/4110ef03ed71cf2480a613faf43290839e712703).

| Requirement | Source evidence | Limit for Boaz |
|---|---|---|
| Native page hosting | `CrestEngines/Chromium/Overlay/chrome/browser/ui/crest/crest_chrome_host.mm:782` returns the WebContents native NSView; `CrestMac/Infrastructure/Pages/BrowserWebHostView.swift:560` installs it into a native container | Demonstrates a direct host implementation, not our focus/VoiceOver/fullscreen acceptance |
| Native window | `Overlay/chrome/browser/ui/crest/crest_browser_window.mm` implements Chromium BrowserWindow while SwiftUI supplies browser controls | Some interfaces are deliberately inert, including accelerator-provider and toolbar-update paths around line 839; do not assume complete Boaz parity |
| Real tabs | `crest_engine_browsers.cc:132` inserts WebContents into TabStripModel; line 169 transfers a TabModel; line 186 activates the actual tab | Preserve stable page IDs, extension IDs, ownership and cancellation during transfer |
| Browser/window identity | `crest_engine_browsers.cc:259` keys Browser ownership by profile and native window; lines 105 and 148 preserve separate extension-popup Browser identity | Multiple Chromium window identities may correspond to one visible native window. Boaz must explicitly resolve profile and popup mapping instead of claiming one-to-one parity |
| Split view | `BrowserPagePool.swift:36` separates presented pages from focused page; `crest_engine_page.cc:718` updates Chromium activation on focus | Implement Boaz's two visible pages and native focus behavior; verify extension activation |
| Extension actions | `crest_chrome_host.mm:789` validates profile/browser/anchor/extension and calls ExtensionActionRunner; lines 213–269 host ExtensionViewHost contents in a native popup | Real permission/action machinery, not an extension popup URL. Native popup close/focus/position still require acceptance |
| Store installation | `crest_engine_store.cc:329`, 379, 436 and 679 implement validated store requests, update URLs, permission prompts, and CrxInstaller | This is a store-package route. No unpacked installer was found in the scoped overlay/core search; arbitrary local CRX and unpacked installation remain mandatory Boaz work |
| Isolated scripts | `crest_engine_content.cc:92` and 104 execute in an isolated world; line 127 uses RenderFrameHost committed origin; lines 145–179 target documents and supply dropped-callback completion | Sensitive fills must target exact frame/document identity, not the special current-main-document shorthand; private fill/save and hostile-page cases remain unverified |
| Shutdown | `crest_engine_binding.cc:265` disposes work, closes pages/Browsers and releases profiles; `crest_engine_browsers.cc:34` defines a renderer-departure bound | Review before-unload, callback completion and data flushing for Boaz; do not inherit a timeout unquestioned |
| Protected-media observation | `Patches/native-host.patch:2207` routes unsupported key-system events through renderer/browser Mojo; `crest_engine_page.cc:758` filters key system and frame | Crest permits same-site subframes. Boaz's requested rule is stricter: only the primary top-level frame may trigger a switch |
| Fallback policy | `CrestCore/src/CrestCore/Application/Pages/Events/ProtectedMediaUnavailable.cs:12` respects user choices and avoids repeated moves; `Application/Engines/ProtectedMediaService.cs:13` names streaming defaults | Existing recording-engine fixtures prove policy expectations, not Netflix/Disney+ playback. Boaz needs real signed-app playback evidence |

## Maintained scope

Measured from the pinned files with `git apply --numstat` and file/line counts:

- 14 active host patches in `Patches/series`, totaling 1,749 added and 448 removed lines across 131 upstream files.
- Two additional source-preparation unwind patches add 12 lines. All 16 patch files total 1,761 additions and 448 deletions.
- 51 overlay files, 16,929 lines, 696,266 bytes.
- `host-inputs.json` records 131 upstream file entries with input/output hashes.

Patch counts alone omit most of the custom host implementation. Boaz will implement a smaller, independently authored bridge for its own contracts and record its actual maintained scope. Do not import Crest's application/core, default privacy changes, or Manifest V2 support merely because they are available.

## Build recipe and SSD fit

`source.lock.json` pins Chromium `157.0.8103.51` from Google's official lite source archive, SHA-256 `c66efa0eb499713d018493e1973155a057576435a7e5d5ed0e5ca131b2ae3019`. It also pins toolchains, CIPD inputs, GN configurations and performance inputs. The lock labels itself source preparation; it is not a verified released artifact.

`README.md:38` requires Apple Silicon, matching Xcode/Metal, Python 3.11+, Ninja and Go. It describes approximately 13 GB for expanded source. `ForkMaintenance.md:30` requires 50 GiB for preparation and a 15 GiB compilation reserve. These are minimum free-space checks, not measured peak storage. No measured peak RAM, peak disk, or build-duration result was found in the scoped build documentation.

The development preset omits PGO and ThinLTO. The performance preset uses official-build optimizations, PGO, ThinLTO/LLD and SDK 26.5 with a pinned profile. Four jobs are the wrapper default; twelve appear in the performance example. The final ThinLTO link may require more memory than compilation. These settings must be verified against Boaz's selected Chromium revision and installed SDK, not copied blindly.

The existing 500 GiB APFS sparse image, 36 GiB RAM and 12-core Mac are a plausible experiment environment. This is a capacity judgment, not proof of a finished build fitting. At pause, the image had about 462 GiB free and the external volume about 614 GiB free. Keep source, configurable caches/temp, logs and outputs under `/Volumes/BoazBuild/cef` for this migration, including a separately named direct-host workspace. Preserve the existing CEF tree. Inventory estimated current-plus-candidate storage before downloading another source tree.

Keep Boaz's stronger 20 GiB external and 30 GiB image floors, process-group ownership, sleep prevention and no-automatic-deletion rule. Start the first direct-host build at four jobs, increasing only from observed memory pressure up to twelve. Keep benchmarks separate from builds. Do not adopt Crest's cleanup policy for old preparations.

## Update cadence

`fork.json` selects Chrome Stable on Mac and disables automatic major-version updates. `.github/workflows/chromium.yml:8` checks every six hours. The maintenance procedure verifies checksums and patch input/output hashes, refuses fuzz, and stops publication on patch, toolchain, build or smoke failures. Repository variables gate automation; the checked-in workflow does not establish that those variables are enabled or that a shipping SLA is achieved.

Boaz retains its 72-hour security-update shipping target, named maintainer and escalation path. Track the selected upstream revision directly, with explicit Chromium source, patch, bridge and packaged-artifact hashes. A CEF release checker is insufficient once the direct host is selected.

## License and implementation boundary

Crest's root license is MPL-2.0. Its BrowserWindow notes Mori provenance with a retained MIT license, and some Chromium patches retain other third-party licenses. That does not make all Crest modifications MIT. This study extracts architectural facts only. No Crest file will be copied without explicit approval; any approved copied file retains its license and attribution in third-party notices and About. Independently written Boaz code still needs Chromium's required bundled notices.

## Next acceptance packet

1. Pin and verify a direct Chromium build recipe and toolchain on the existing image. Preserve prior outputs; no concurrent builds.
2. Implement an independently authored native host behind BoazChromium's narrow ABI. Prove one page, native/page accessibility together, input, focus, resize, close and orderly shutdown with an isolated profile.
3. Add real tabs and split view with explicit profile/window identity, then native extension actions and all installation modes. Keep all eight extension products mandatory.
4. Prove exact-document isolated password execution and trusted messaging. Observe unsupported EME in the renderer/browser boundary rather than assuming isolated JavaScript can intercept main-world navigator calls.
5. Run the architecture gates and dual-engine WebKit/FairPlay acceptance before production integration or release claims.

The earlier CEF build stopped normally at approximately 7,070 of 58,952 Ninja steps. No completed custom engine artifact or measured performance result is claimed.
