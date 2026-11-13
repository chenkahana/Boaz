# Chromium feasibility evidence

Recorded 2026-11-13 against Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`, fetched from `origin/master`. The original `feat/phone-toolbar` checkout was left unchanged. Worktree: `~/.worktrees/Boaz/codex/chromium-migration`.

## Gate status

| Gate | Status | Evidence or missing prerequisite |
|---|---|---|
| F1 native host and lifecycle | In progress | CMake 4.5.0 and Ninja 1.13.2 installed; prebuilt host under construction |
| F2 native embedding and extensions | Proposed direct route rejected by source contract; alternatives unproven | Inspected macOS CEF header forces Alloy when `parent_view` is supplied |
| F3 trusted scripts | Blocked by unselected runtime route | No isolated-world or extension messaging implementation demonstrated |
| F4 custom distribution | Storage ready; build not executed | Verified 500 GiB APFS image on existing SSD; use at most 12 jobs on this 36 GiB Mac |
| F5 platform behavior | Not executed | Requires a working selected host |
| F6 performance baseline | Not executed | No CEF host; no benchmark numbers claimed |
| F7 external dependencies | Partly inspected; unresolved | Default-model workers now available; signing/notarization, codecs, and Widevine remain unverified |

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

No secrets, cookies, passwords, or signing-key material were read. No custom CEF build, application build, runtime spike, performance run, or release was attempted.

## Updated execution decision

The APFS image at `/Volumes/Chen's SSD/BoazBuild.sparsebundle` preserves the exFAT drive and its existing files. It passed permissions, executable, symlink, hard-link, ownership, and detach/reattach checks. See [storage.md](spikes/storage.md).

Use the default model for workers. Build prerequisites and custom-build capacity do not block independent prebuilt experiments. CMake 4.5.0, Ninja 1.13.2, Python 3.9.6, Xcode 27.2, and macOS SDK 27.2 are available.

Selected prebuilt: CEF `156.0.28+g57389f0+chromium-156.0.8078.88`, macosarm64 standard distribution, source commit `57389f04a61ab0e9603d9f96602843d0e08bb11c`. The 312,278,280-byte archive matched published SHA-1 `30919cc28e5cae6b82f7817e6829d4ac863454ae`; its locally computed SHA-256 is `bf6907ff9b5e019fc52a74bdcef00ab962afce99e1cc99e5a50f935b2f684583`.

Run S1 with Alloy in a native parent, then S2a with a Chrome-style CEF Views window hosting native UI. `CefWindow::GetWindowHandle()` is an NSView handle on macOS; obtain its window rather than casting it to NSWindow. S2b is a bounded custom-build fallback only if S2a fails. Direct-parent Alloy behavior does not reject the Views route.

Custom builds stay entirely in `/Volumes/BoazBuild/cef`, with space monitoring and at most 12 jobs initially. Widevine and production signing remain independent release gates.
