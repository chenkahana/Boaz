# Direct Chromium source preparation

This independently authored fetcher pins the official Chromium 157.0.8103.51 lite source archive. It does not copy Crest implementation code. This is source preparation only; native hosting, extensions, codecs, DRM, toolchain compatibility, and release acceptance remain separate gates.

Preview without changing files:

```sh
/opt/homebrew/bin/python3.12 Tools/chromium/fetch-source.py --dry-run
```

After review, execute with `--fetch`. The script dispatches the existing `Tools/cef/run-build.py` guard. That guard attaches/verifies the exact build image, checks the external 20 GiB/internal 30 GiB reserves, prevents concurrent guarded stages, keeps logs/temp/cache on the image, prevents sleep, and stops only its owned process group on failure.

The archive lives at `/Volumes/BoazBuild/cef/direct/downloads/chromium-157.0.8103.51-lite.tar.xz`; source lands at `/Volumes/BoazBuild/cef/direct/chromium/src`. An existing exact-checksum archive is reusable. Downloads use HTTPS, 60-second socket timeouts, an 8 GiB ceiling, exclusive partial creation, and SHA256 verification before archive promotion or extraction. No resume is implemented. Interrupted or invalid partial files remain for inspection and block another download until explicitly moved aside by the owner.

Extraction refuses an existing source or staging directory. It accepts only the expected archive root, regular files/directories and confined relative links. It rejects path traversal, duplicate entries, absolute/escaping links, device nodes, and hard links whose verified target has not appeared. Python 3.12's `data` extraction filter adds per-entry traversal/link protections. Legitimate internal relative symlinks remain symlinks. It verifies `chrome/VERSION` before promoting the staged source. A failed or interrupted extraction remains at `src.extracting`; no source or user files are automatically removed.

The expected top-level archive directory is `chromium-157.0.8103.51`, matching the official archive naming convention; the executed extraction below verified that member layout. A different root or forward hard-link ordering fails safely and requires inspection, not loosening path protections. The 8 GiB ceiling is a safety bound, not a measured archive size. Peak build storage and build throughput remain unmeasured.

Initial packet verification was Python syntax and one `--dry-run`; subsequent execution evidence follows below. The earlier unfinished CEF patch remains preserved on its own branch and is not applied here. Do not copy Crest's source-directory deletion policy; old data requires an explicit ownership/recovery decision.

## Executed source preparation, 2026-11-13

The official archive endpoint reported 2,079,590,576 bytes. Google's published SHA-256 matched the pinned value; the downloaded archive matched it too. Guarded extraction completed with exit 0 and verified `chrome/VERSION` as 157.0.8103.51. The previous CEF source/output tree remains intact. Log: `/Volumes/BoazBuild/cef/logs/20261113T101222.775449Z.log`.

Apple's Metal Toolchain 27B47 was downloaded/exported under the volume guard. `xcrun metal --version` now reports Apple metal 32023.922. The system-managed component is installed by Xcode; the exported bundle is retained under the direct workspace.

The initial native-host build uses `Tools/chromium/development.json` and `build.py --configure` or `--build`. It is non-component arm64 with symbols, expensive checks, PGO and ThinLTO disabled; it is not the performance/release configuration. Source/toolchain preparation and GN generation must pass before compilation.

## Native host compilation

`install-host.py --install` stages only independently authored `Tools/chromium/host` files into `src/boaz`, under the same volume guard. It records hashes and preserves the previous installation on updates. The development GN argument `root_extra_deps` includes this source set without modifying upstream build files. `build.py --host-objects` compiles the four adapter translation units with four jobs by default; a complete Chrome build is a separate `--build` operation.

GN generation with the host passed on 2026-11-13: 36,671 targets from 5,049 files. Log: `/Volumes/BoazBuild/cef/logs/20261113T104434.291401Z.log`. The first attempt found a duplicate ARC setting, removed because Chromium enables ARC by default. This proves build graph generation only, not compilation, linking, startup, or product acceptance. The later linked-host preparation below adds the browser startup hook and native UI entry.

On 2026-11-13, the first object build completed 10,018 prerequisite steps and compiled the native-view bridge, then rejected native reference/pointer members under Chromium's ownership checks. Those members now use `raw_ref`/`raw_ptr`; an unused borrowed window field was removed. The follow-up compiled the window and tab adapters; the new address adapter required an explicit `.get()` for a templated Chromium model lookup. The final incremental object build passed. Logs: `20261113T104456.889291Z.log`, `20261113T110407.265366Z.log`, `20261113T110452.937276Z.log`, all under `/Volumes/BoazBuild/cef/logs/`. These are object-compilation results, not a linked/runnable browser. Later ABI/permission/bootstrap changes require their own affected compile.

## Linked-host preparation, 2026-11-13

The Swift 6 UI dylib compiled after replacing non-Sendable callback return values and copying the C function table before entering main-actor isolation. Log: `20261113T111054.496238Z.log`. Bootstrap, ABI 3 and the native permission-sheet object compiled in `20261113T111643.168085Z.log`. The four patched Chromium translation units compiled in `20261113T111723.093883Z.log`. No application launch or signing acceptance is implied.

The first source patch modifies nine upstream files with pinned before/after hashes. It registers native startup/window/permission hooks, links the independent host and disables Widevine component registration through `boaz_widevine_enabled=false`, emitted as `BOAZ_WIDEVINE_ENABLED`. Applying a later patch requires preserving the applied prefix and validating current source. The build runner now writes adjacent `.metrics.json` files with duration, minimum sampled free capacity and sampled owned-process RSS sum. RSS includes shared pages and is not physical footprint; ten-second samples are observed peaks, not absolute maxima.

The full application build started with four jobs. After 186 seconds, the guard recorded a 1,168,670,720-byte peak sampled RSS sum and the Mac reported 50% memory headroom. The owned process group stopped normally and Ninja resumed with eight jobs; existing outputs were preserved. Logs are `20261113T111844.408813Z.log` and `20261113T112159.617046Z.log`. This is a development build, not a performance measurement. See [development signing](direct-signing.md) for the next distribution-preparation step.

## LLVM supplement and script objects, 2026-11-13

The eight-job build stopped at the SwiftShader library inspection step because the official compiler archive does not include `llvm-otool`. The log `20261113T112159.617046Z.log` records the missing executable; this was not a C++ error. Its 688.812-second run sampled a 3,439,689,728-byte maximum process-tree RSS sum. No capacity limit was reached.

The separate official `llvmobjdump` package is now pinned by version, SHA-256 and file inventory. Guarded installation preserves the compiler and its base receipt, and adds a supplemental receipt. Installation passed in `20261113T114234.321230Z.log`; the installed `llvm-otool` successfully inspected the previously failing SwiftShader library.

The isolated-world patch and trusted execution coordinator are installed. The coordinator compiled in `20261113T114138.892688Z.log`. The browser-side password submission coordinator compiled in `20261113T114322.222276Z.log`. It rejects private saves, validates the exact main-frame document around confirmation, and cancels pending operations on navigation/crash/close. Renderer submission events, native confirmation UI, Keychain persistence and runtime acceptance remain pending. No new tests were added.

The full build resumed with eight jobs using the preserved outputs. A linked application and production Boaz integration remain unverified.

The eight-job continuation was checkpointed normally after 892.719 seconds to integrate the completed extension packet. Peak sampled process RSS sum was 3,780,657,152 bytes; the Mac reported 45% memory headroom. Native extension actions, popup policy, bootstrap and Swift UI compiled after one Chromium style-rule correction, recorded in [native extension actions](spikes/direct-extension-actions.md). The full build resumed at 12 jobs with generated signing tools included. Existing outputs were retained.

During the 12-job build, macOS memory pressure changed from normal (`kern.memorystatus_vm_pressure_level=1`) to warning (`2`) in heavier Blink compilation. The verified owned guard stopped normally; log `20261113T120132.703785Z.log` records 2,346.792 seconds and a 10,383,949,824-byte peak sampled process RSS sum. No disk reserve was reached.

The same installed ABI 4 source resumed at eight jobs in `20261113T124057.016502Z.log`, with 25,579 remaining Ninja steps. Before resuming, installed host hashes, applied-patch output hashes, GN settings and the ABI 4 header were checked against their receipts. The existing volume guard invoked Ninja directly with the same targets and toolchain environment; this avoided installing the queued ABI 6 source or using the normal build driver's repository-match check to imply those newer sources were compiled. Memory pressure returned to normal after the reduction. This is build-resource evidence, not application performance acceptance.

The eight-job continuation was stopped normally when running the explicitly requested default-browser Mac build alongside it caused memory-pressure warning. Both Mac distribution builds then passed serially. Installed Chromium host and final patch hashes were reverified unchanged before resuming eight jobs in `20261113T131828.225222Z.log`; prior outputs were preserved. Do not overlap further full application builds with this Chromium build.
