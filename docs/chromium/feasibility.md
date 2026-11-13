# Chromium feasibility evidence

Recorded 2026-11-13 against Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`, fetched from `origin/master`. The original `feat/phone-toolbar` checkout was left unchanged. Worktree: `~/.worktrees/Boaz/codex/chromium-migration`.

## Current prerequisite

The dual-engine revision requires S0 Crest source inspection before further Wave 0 implementation. [S0](spikes/S0-crest.md) now selects an independently authored direct Chromium host; CEF-specific S2a/S2b are frozen and their acceptance moves to the direct-host proof. The current full build is running at six jobs, with prior outputs preserved. New real-application source is queued separately from its unchanged installed inputs. Earlier CEF architecture selection is superseded by the S0 verdict. See [dual-engine revision](dual-engine.md). Widevine approval now gates dormant Chromium DRM enablement; release instead requires working protected playback in WebKit.

## Gate status

| Gate | Status | Evidence or missing prerequisite |
|---|---|---|
| F1 native host and lifecycle | Direct host pending; earlier CEF evidence only | Development signatures verify; two signed-profile runs load HTTPS and exit 0. Earlier ad-hoc profile still stalls. Notarization, IME, accessibility and performance remain pending |
| F2 native embedding and extensions | Direct-host proof pending; CEF route frozen | S0 selected a direct Chromium host from source evidence. Real native window/tab identity, split view, actions, and all eight extensions remain unverified in Boaz |
| F3 trusted scripts | Direct-host implementation pending | Crest demonstrates isolated-world APIs; Boaz must independently implement exact-document identity and cancellation and pass hostile-page/password acceptance |
| F4 custom distribution | Direct source/toolchains, GN and initial adapter objects passed | Official Chromium 157.0.8103.51 checksum and extraction passed; ten pinned Mac toolchain packages installed. Native-host GN graph passed. Four adapter translation units compiled under the SSD guard after ownership/type fixes. Bootstrap/link/runtime and later changes remain pending. CEF output preserved. No complete custom artifact or codec pass |
| F5 platform behavior | Source findings; runtime pending | Native passkey window-discovery adapter prepared; Apple entitlement grant unverified. Working signed host remains prerequisite; see [passkeys](passkeys.md) |
| F6 performance baseline | Not executed | Direct host not runnable yet; no benchmark numbers claimed. Do not benchmark during the custom build |
| F7 external dependencies | Partly inspected; unresolved | Widevine inquiry submitted; approval gates dormant Chromium DRM only. WebKit/FairPlay playback, Developer ID/notarization and codec distribution remain unverified; see [dependencies](spikes/distribution-dependencies.md) |

No complete S1–S7 gate has a GO verdict. SSD filesystem acceptance passed separately. The original upstream source revision below is an inspection reference, not the selected stable distribution.

## Original checkpoint evidence

The CEF repository is absent from Boaz, so official upstream source was needed. GitHub reported CEF master revision `e6035cfb35235e19ea5d5eae62c989b9ef0818dc` during inspection.

The [macOS window-info header at that revision](https://github.com/chromiumembedded/cef/blob/e6035cfb35235e19ea5d5eae62c989b9ef0818dc/include/internal/cef_types_mac.h#L140-L145) documents that a non-null `parent_view` forces Alloy style. Thus requesting Chrome style while parenting directly into an NSView does not establish the planned Chrome-style host.

This is a source-contract finding, not a runtime experiment. Recheck the header in the eventual pinned binary distribution and verify the actual runtime style when running F2.

Local checks:

| Check | Observed result |
|---|---|
| `git fetch origin master` | Completed; remote base remained `045132d7bd3b7a191730031a018554ad1f0bcfbe` |
| `git status --short` | Original checkout and new worktree clean before these documentation changes |
| `xcodebuild -version` | Xcode 27.2, build 27B52 |
| `command -v xcodegen` | `/opt/homebrew/bin/xcodegen` |
| `command -v cmake` | No executable on PATH |
| `sysctl -n hw.memsize` | 38,654,705,664 bytes, or 36 GiB |
| `df -h .` | About 37 GiB available on the workspace volume |
| `security find-identity -v -p codesigning` | Two Apple Development identities; no local Developer ID identity listed |
| Release script inspection | Developer ID export uses Xcode account/cloud signing; absence of a local identity does not prove cloud signing unavailable |
| Selected worker invocation | Failed before completing inventory: provider requested usage credits or subscription |
| BoazKit package manifest | No test target declared; no package test files found by file inventory |

At the original checkpoint, no custom CEF build, application build, runtime spike, performance run, or release had been attempted. Later spike results appear below and in the linked reports. No secrets, cookies, passwords, or signing-key material were read by the inspection tools.

## Earlier CEF execution decision, superseded by S0

The APFS image at `/Volumes/Chen's SSD/BoazBuild.sparsebundle` preserves the exFAT drive and its existing files. It passed permissions, executable, symlink, hard-link, ownership, and detach/reattach checks. See [storage.md](spikes/storage.md).

Use the default model for workers. Build prerequisites and custom-build capacity do not block independent prebuilt experiments. CMake 4.5.0, Ninja 1.13.2, Python 3.9.6, Xcode 27.2, and macOS SDK 27.2 are available.

Selected prebuilt: CEF `156.0.28+g57389f0+chromium-156.0.8078.88`, macosarm64 standard distribution, source commit `57389f04a61ab0e9603d9f96602843d0e08bb11c`. The 312,278,280-byte archive matched published SHA-1 `30919cc28e5cae6b82f7817e6829d4ac863454ae`; its locally computed SHA-256 is `bf6907ff9b5e019fc52a74bdcef00ab962afce99e1cc99e5a50f935b2f684583`.

Run S1 with Alloy in a native parent, then S2a with a Chrome-style CEF Views window hosting native UI. `CefWindow::GetWindowHandle()` is an NSView handle on macOS; obtain its window rather than casting it to NSWindow. S2b is a bounded custom-build fallback only if S2a fails. Direct-parent Alloy behavior does not reject the Views route.

Custom builds stay entirely in `/Volumes/BoazBuild/cef`, with space monitoring and at most 12 jobs initially. Widevine and production signing remain independent release gates.

## Earlier CEF architecture decision, superseded by S0

The user authorized the orchestrator to choose and implement the best-supported architecture, including public CEF interfaces and necessary Chromium changes. The earlier 300-line, libcef-only constraint and routine design-approval requests are superseded. Product, security, performance, DRM, and release gates remain unchanged.

Deterministic evidence: with accessibility explicitly enabled, the signed Alloy host and the Chrome Views host retaining its original content root expose the HTML heading, labeled input, and button. The same Chrome Views host with the SwiftUI wrapper replacing the content root exposes native controls but loses page accessibility. All three runs exited normally. This is accessibility-tree evidence; real VoiceOver acceptance remains pending.

Architecture judgment: preserve the original Chromium widget/content root. Host SwiftUI through Chromium's `views::NativeViewHostMac`. Keep one real Browser and TabStripModel per visible Boaz window, so extension tab/window identity follows visible pages. Implement toolbar actions through Chromium's action model, permission handling, and popup host. The tab and action design reports describe the remaining implementation work. This selects the next implementation route, not a passed architecture gate.

Do not mutate the custom-build source while the baseline build owns it. Prepare versioned patch assets independently, then compile and exercise them after that build. First acceptance requires native and page accessibility together, two retained tabs, split view, correct extension IDs, and a native action popup. Production integration remains blocked on these proofs and trusted-script isolation.
