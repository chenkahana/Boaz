# Chromium migration

The GitHub DMG is intended to move to Chromium while the Mac App Store and iPhone apps remain on WebKit. All migration work belongs to one draft PR on `codex/chromium-migration`. The DMG keeps both engines at runtime. Do not merge or release until full dual-engine parity and protected playback through WebKit are verified; Widevine remains disabled pending approval.

## Current status

The [S0 Crest study](spikes/S0-crest.md) selects a direct Chromium host. CEF development is frozen; the original runtime gates now apply to the new host. The [dual-engine revision](dual-engine.md) governs subsequent work. The external SSD now contains a verified APFS build image; CMake and Ninja are installed. The pinned direct Chromium source and Mac toolchains are installed; the first native-host compile is in progress. Earlier prebuilt CEF runtime evidence does not pass the new host gates. See [feasibility.md](feasibility.md) and [SSD verification](spikes/storage.md).

The [parity ledger](parity.md) records the existing implementation and required acceptance coverage. Source inventory is not runtime verification.

## Execution order

1. Use the default worker model and the verified SSD image. Build the pinned official Chromium source with independently authored host code. Preserve the frozen CEF experiments and outputs.
2. Prove native lifecycle, retained tabs, split view, extensions on visible pages, and trusted scripts in the direct host. Verify native/page accessibility together and actual extension tab/window identities. No Chrome toolbar or hidden substitute host is accepted.
3. After architecture gates pass, freeze engine contracts and implement WebKit adapters without changing iPhone behavior. The DMG keeps both engines, persistent tab choices and site rules. Use a concrete observable page facade, typed script values, origin/frame/navigation identity, single-completion callbacks, and explicit page lifecycle states.
4. Integrate the Objective-C++ Chromium bridge, helpers, artifact retrieval, and isolated build outputs. Engine callbacks retain their required threads; UI notifications cross to MainActor. Preserve a WebKit DMG configuration for rollback.
5. Implement ready packets in the parity ledger, two at a time, including protected-media routing, then developer tools and native UI polish. WebKit data remains intact and separate from Chromium data.
6. Verify both engines' performance, migration, signing, notarization, update/rollback, and three days of dogfooding. Real Netflix and Disney+ FairPlay playback in WebKit is mandatory. Widevine approval gates enabling Widevine, not the dual-engine release.

## Worker dispatch

The orchestrator owns contracts, overlapping application files, project generation, security decisions, integration, and acceptance. Use at most two workers plus the orchestrator. Use the default model without a separate worker-provider dependency. Keep tasks small and context bounded.

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
