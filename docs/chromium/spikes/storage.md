# External build storage verification

Recorded 2026-11-13. Verdict: GO for build filesystem use; custom CEF build capacity and duration remain unmeasured.

The existing exFAT volume at `/Volumes/Chen's SSD` was not reformatted. Only `BoazBuild.sparsebundle` was created on it. Initial available space was 700,857,188,352 bytes, above the required 520 GiB.

The image is 500 GiB APFS with 128 MiB bands, mounted at `/Volumes/BoazBuild`. Structured `hdiutil` and `diskutil` output confirmed the image-to-mount mapping, APFS filesystem, and enabled ownership. Spotlight reports indexing and searching disabled after adding `.metadata_never_index`.

## Acceptance evidence

- A disposable verification directory held an executable file with mode 0750 and current-user ownership.
- Symlink execution produced the expected output.
- A hard link had the same inode as its source.
- Normal detach and reattach succeeded. Contents, permissions, ownership, symlink execution, and hard-link identity survived.
- Only the disposable verification files were removed afterward.
- A bounded 512 MiB write with `fsync` completed in 0.159 seconds. This is a cached filesystem measurement, not physical-device throughput or a Chromium build-speed prediction.
- APFS free space after verification: 536,496,881,664 bytes. Sparse-image allocation on exFAT may retain freed bands until compaction.

## Operations

`Tools/cef/volume.sh` supports `create`, `attach`, `status`, `detach`, and `compact`. It refuses existing-image overwrite, conflicting mounts, wrong filesystems, and disabled ownership. Detach never forces an unmount. Compact requires the image to be detached.

Run custom build stages with `python3 Tools/cef/run-build.py -- COMMAND ARGS`. It attaches and validates the image, locks against concurrent guarded stages, runs in `/Volumes/BoazBuild/cef`, redirects temporary/cache paths, logs output, and prevents sleep. Every ten seconds it verifies the mount and requires 20 GiB outside the image and 30 GiB inside. Failure terminates only the launched process group, first gracefully, then after a 30-second timeout if necessary. It does not delete outputs.

Stop builds and detach normally before ejecting the external drive. A corrupt image is preserved for diagnosis; the scripts never repair, erase, or recreate it automatically.
