# Chromium feasibility evidence

Recorded 2026-11-13 against Boaz `045132d7bd3b7a191730031a018554ad1f0bcfbe`, fetched from `origin/master`. The original `feat/phone-toolbar` checkout was left unchanged. Worktree: `~/.worktrees/Boaz/codex/chromium-migration`.

## Gate status

| Gate | Status | Evidence or missing prerequisite |
|---|---|---|
| F1 native host and lifecycle | Blocked, not executed | CMake absent from PATH; no selected CEF distribution or built host |
| F2 native embedding and extensions | Proposed direct route rejected by source contract; alternatives unproven | Inspected macOS CEF header forces Alloy when `parent_view` is supplied |
| F3 trusted scripts | Blocked by unselected runtime route | No isolated-world or extension messaging implementation demonstrated |
| F4 custom distribution | Blocked on this host | 36 GiB RAM and about 37 GiB available disk, below the plan's 64 GB RAM / 300 GB free build-host requirement |
| F5 platform behavior | Not executed | Requires a working selected host |
| F6 performance baseline | Not executed | No CEF host; no benchmark numbers claimed |
| F7 external dependencies | Partly inspected; unresolved | Worker provider rejected the selected model for lack of usage credits; signing/notarization, build-host provisioning, artifact access, codecs, and Widevine remain unverified |

No gate has a GO verdict. No binary lockfile has been fabricated. The upstream source revision below is an inspection reference, not a selected stable distribution.

## Deterministic evidence

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

## Judgment and next bounded experiment

The approved policy stops dependent implementation when deterministic evidence contradicts the initial assumption or a required tool is missing. Building an engine seam around an unproven extension host would commit the application to an architecture that may not meet parity.

After CMake and a usable worker provider are available, select a prebuilt macOS arm64 standard distribution and pin its version and checksum. The next architecture experiment is a Chrome-style CEF Views host with native-window integration. It must demonstrate extension access to visible tabs and pass focus, clipping, fullscreen, split view, and accessibility checks before acceptance. A separate hidden host is not an adequate substitute by assertion.

A larger custom-build machine is needed only for F4, not to start the prebuilt host experiment. Widevine approval remains a later external release gate. Neither blocker is evidence that native hosting itself is impossible.
