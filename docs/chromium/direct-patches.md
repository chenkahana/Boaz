# Pinned direct-host source patches

`python3 Tools/chromium/apply-patches.py` checks the manifest, source version, existing receipt, patch hashes and full input/output file hashes. Remaining patches are checked and applied only to disposable internal-disk staging. Default invocation does not modify SSD files. A pending interrupted transaction is reported rather than replayed in dry mode.

`python3 Tools/chromium/apply-patches.py --apply` dispatches through `Tools/cef/run-build.py`. The internal stage requires the established working directory, TMPDIR and held build lock. This cannot run alongside a guarded build. Run after source extraction and before building modified sources.

Root-owned `Tools/chromium/patches.lock.json` schema:

```json
{
  "chromium_version": "157.0.8103.51",
  "patches": [{
    "file": "patches/native-host.patch",
    "sha256": "64 lowercase hex characters",
    "files": [{"path": "chrome/path/file.cc", "before": "sha256", "after": "sha256"}]
  }]
}
```

Paths must be canonical and confined. Existing regular source files only: no symlinks, additions, deletions, renames, mode changes, binary patches or undeclared paths. `/opt/homebrew/bin/git apply --no-index` works without a source `.git` directory. Patch files remain repository inputs; Chromium VERSION must match source.lock.json.

Each transaction has a unique `direct/patch-history/<id>/` directory containing only listed staged files and preserved originals. After complete staged output validation and persistence, `direct/patches-applied.json` records the exact applied prefix and pending transaction **before any source replacement**. Source replacement uses same-directory temporary files, fsync and atomic rename. A crash can leave a mixture of declared before/after hashes, never an accepted arbitrary state. Rerunning `--apply` validates the pending transaction and finishes it. Applied pins cannot change; append patches instead. Final hashes of previously applied files are validated before appending.

Originals and old transaction directories are never deleted automatically. Interrupted temporary files or unreceipted history directories remain available for inspection. Do not manually reverse patches, reset the archive, or clean outputs to resolve a mismatch. Preserve the receipt/history/source and investigate the exact reported path. This tool protects against accidental drift, not hostile concurrent edits outside the shared guard.

Verification for this packet: Python AST parsing and whitespace diff check. Worker dry invocation stopped at missing Tools/chromium/source.lock.json in its older branch (root owns that lock and patches.lock.json); no fabricated manifest or SSD execution is part of worker verification. Root must execute the dry check and guarded application against the actual pinned patch series. No tests or build harness added.

Root integration routes both check and apply through the volume guard. Disposable check staging lives under the direct workspace's `tmp/patch-check`, not the internal disk. Applied source files and transaction originals remain on the build image. The initial nine-file patch passed guarded staging/hash checks and applied successfully on 2026-11-13; its four changed C++ translation units also compiled. Runtime and interruption/retry acceptance remain separate.
