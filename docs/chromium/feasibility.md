# Chromium feasibility evidence

Recorded 2026-11-13 against Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`, fetched from `origin/master`. The original `feat/phone-toolbar` checkout was left unchanged. Worktree: `~/.worktrees/Boaz/codex/chromium-migration`.

## Gate status

| Gate | Status | Evidence or missing prerequisite |
|---|---|---|
| F1 native host and lifecycle | Partial; signed fresh-profile relaunch passes | Development signatures verify; two signed-profile runs load HTTPS and exit 0. Earlier ad-hoc profile still stalls. Notarization, IME, accessibility and performance remain pending |
| F2 native embedding and extensions | Public API route blocked; broader CEF adapter authorized | Native fullscreen shortcut now passes. Toolbar-free extension actions lack a public API; the selected next proof retains Chromium’s original root and real tab model, with native-view hosting and an explicit extension-action API. The former 300-line limit is superseded. See [actions](spikes/S2-actions.md) and [native parent](spikes/S2-native-parent.md) |
| F3 trusted scripts | Blocked by unselected runtime route | No isolated-world or extension messaging implementation demonstrated |
| F4 custom distribution | Build running; project generation passed | Pinned checkout and 117 applicable CEF patches completed; Debug and Release project generation passed. Guarded SSD build retains the 12-job cap. No custom artifact or codec pass yet |
| F5 platform behavior | Not executed | Requires a working selected host |
| F6 performance baseline | Not executed | Host now available; no benchmark numbers claimed |
| F7 external dependencies | Partly inspected; unresolved | Widevine eligibility inquiry submitted with authorization; no agreement or approval. Developer ID/notarization and codec distribution remain unverified; see [dependencies](spikes/distribution-dependencies.md) |

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

## Updated execution decision

The APFS image at `/Volumes/Chen's SSD/BoazBuild.sparsebundle` preserves the exFAT drive and its existing files. It passed permissions, executable, symlink, hard-link, ownership, and detach/reattach checks. See [storage.md](spikes/storage.md).

Use the default model for workers. Build prerequisites and custom-build capacity do not block independent prebuilt experiments. CMake 4.5.0, Ninja 1.13.2, Python 3.9.6, Xcode 27.2, and macOS SDK 27.2 are available.

Selected prebuilt: CEF `156.0.28+g57389f0+chromium-156.0.8078.88`, macosarm64 standard distribution, source commit `57389f04a61ab0e9603d9f96602843d0e08bb11c`. The 312,278,280-byte archive matched published SHA-1 `30919cc28e5cae6b82f7817e6829d4ac863454ae`; its locally computed SHA-256 is `bf6907ff9b5e019fc52a74bdcef00ab962afce99e1cc99e5a50f935b2f684583`.

Run S1 with Alloy in a native parent, then S2a with a Chrome-style CEF Views window hosting native UI. `CefWindow::GetWindowHandle()` is an NSView handle on macOS; obtain its window rather than casting it to NSWindow. S2b is a bounded custom-build fallback only if S2a fails. Direct-parent Alloy behavior does not reject the Views route.

Custom builds stay entirely in `/Volumes/BoazBuild/cef`, with space monitoring and at most 12 jobs initially. Widevine and production signing remain independent release gates.

## Architecture decision after native accessibility comparison

The user authorized the orchestrator to choose and implement the best-supported architecture, including public CEF interfaces and necessary Chromium changes. The earlier 300-line, libcef-only constraint and routine design-approval requests are superseded. Product, security, performance, DRM, and release gates remain unchanged.

Deterministic evidence: with accessibility explicitly enabled, the signed Alloy host and the Chrome Views host retaining its original content root expose the HTML heading, labeled input, and button. The same Chrome Views host with the SwiftUI wrapper replacing the content root exposes native controls but loses page accessibility. All three runs exited normally. This is accessibility-tree evidence; real VoiceOver acceptance remains pending.

Architecture judgment: preserve the original Chromium widget/content root. Host SwiftUI through Chromium's `views::NativeViewHostMac`. Keep one real Browser and TabStripModel per visible Boaz window, so extension tab/window identity follows visible pages. Implement toolbar actions through Chromium's action model, permission handling, and popup host. The tab and action design reports describe the remaining implementation work. This selects the next implementation route, not a passed architecture gate.

Do not mutate the custom-build source while the baseline build owns it. Prepare versioned patch assets independently, then compile and exercise them after that build. First acceptance requires native and page accessibility together, two retained tabs, split view, correct extension IDs, and a native action popup. Production integration remains blocked on these proofs and trusted-script isolation.
