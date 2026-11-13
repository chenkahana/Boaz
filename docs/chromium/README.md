# Chromium migration

The GitHub DMG is intended to move to Chromium while the Mac App Store and iPhone apps remain on WebKit. All migration work belongs to one draft PR on `codex/chromium-migration`. Do not merge or release until full parity, including DRM playback, is verified.

## Current status

Wave 0 is blocked. No Chromium engine, binary distribution, or application changes have been integrated. The source/API inspection in [feasibility.md](feasibility.md) rejects the assumed direct Chrome-style child-NSView route for the inspected CEF revision. It does not establish that all alternative architectures fail.

The [parity ledger](parity.md) records the existing implementation and required acceptance coverage. Source inventory is not runtime verification.

## Execution order

1. Resolve the build-tool and worker-provider blockers. Select and checksum a prebuilt CEF distribution and inspect its exact headers.
2. Prove native lifecycle, extensions on actual Boaz tabs, and trusted scripts. Investigate a CEF Views host only as a bounded feasibility task, including focus, clipping, accessibility, split view, and native-window behavior. A hidden extension host is not accepted without evidence that it controls the visible tabs.
3. After those gates pass, freeze engine contracts and implement WebKit adapters without changing iPhone behavior. Use a concrete observable page facade, typed script values, origin/frame/navigation identity, single-completion callbacks, and explicit page lifecycle states.
4. Integrate the Objective-C++ Chromium bridge, helpers, artifact retrieval, and isolated build outputs. CEF callbacks retain their documented thread contracts; UI notifications cross to MainActor.
5. Implement the ready packets in the parity ledger, two at a time, then developer tools and native UI polish.
6. Verify performance, migration, signing, notarization, update/rollback, and three days of dogfooding. DRM approval and working playback are release blockers, not deferred features.

## Worker dispatch

The orchestrator owns contracts, overlapping application files, project generation, security decisions, integration, and acceptance. Use at most two workers plus the orchestrator. The selected low-cost model is `glm-5.3-flash:cloud`; provider availability must be established before dispatch. Do not substitute a costly model silently.

Each worker gets one behavior, an exact base commit, prerequisite IDs, owned files, contracts, existing edge cases, acceptance scenarios, one bounded verification step, exclusions, and a required handoff. Handoffs distinguish deterministic evidence from judgment. Internal messages use `/caveman full` style. Return failures to the orchestrator after two unsuccessful attempts.

Workers commit only in their own worktrees under `~/.worktrees/Boaz/`. Only the orchestrator integrates their commits and updates the single PR. Workers do not open PRs or publish releases.

## Acceptance rules

- Keep the draft PR draft while any required gate is unresolved. Repository auto-merge behavior makes draft status consequential.
- Preserve ten live pages initially. Preserve existing Peek instead of creating a second implementation.
- Migration is restartable per profile and stage; retain WebKit source data and mark completion only after successful writes and flushes. Do not copy raw Arc LevelDB/IndexedDB directories.
- Keep automation off by default, loopback-only, and visibly indicated. Validate origin restrictions and restart requirements against the pinned engine.
- Inspect existing affected assertions and fixtures. Add no tests without Chen's request. Required builds and acceptance checks remain mandatory; do not run unrelated suites.
- Performance budgets: cold launch at most WebKit +150 ms and 1 second on the reference Mac; live-tab switch at most 16 ms without blank frames; unloaded restore no slower than WebKit; ten-tab memory at most 1.25 times WebKit; idle CPU at most 1% of one core; animation at display refresh rate; Speedometer within 3% of equivalent Chrome; arm64 DMG at most 160 MB and deltas at most 40 MB.
- Record machine, power/cache conditions, workload, timing points, and five samples per performance scenario. Load completion is not first paint. Repeat only failed or materially changed scenarios.
- Choose release versions from the then-current published versions. Preserve a higher-build-number WebKit rollback candidate and both engines' data. Production appcast changes are a release action, not artifact preparation.

## Known corrections to the source plan

The base already supports `Tools/release-mac.sh VERSION --no-publish`. Reuse it instead of adding a duplicate flag. The current `make dmg` target does not forward arbitrary extra arguments.

Download pause/resume/progress is requested new functionality: the current `Downloads.save` path and Mac toast reporting do not establish that such a download manager exists. Likewise, OS-native page behavior must be exercised before calling it verified parity.
