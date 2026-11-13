# Direct Chromium source preparation

This independently authored fetcher pins the official Chromium 157.0.8103.51 lite source archive. It does not copy Crest implementation code. This is source preparation only; native hosting, extensions, codecs, DRM, toolchain compatibility, and release acceptance remain separate gates.

Preview without changing files:

```sh
/opt/homebrew/bin/python3.12 Tools/chromium/fetch-source.py --dry-run
```

After review, execute with `--fetch`. The script dispatches the existing `Tools/cef/run-build.py` guard. That guard attaches/verifies the exact build image, checks the external 20 GiB/internal 30 GiB reserves, prevents concurrent guarded stages, keeps logs/temp/cache on the image, prevents sleep, and stops only its owned process group on failure.

The archive lives at `/Volumes/BoazBuild/cef/direct/downloads/chromium-157.0.8103.51-lite.tar.xz`; source lands at `/Volumes/BoazBuild/cef/direct/chromium/src`. An existing exact-checksum archive is reusable. Downloads use HTTPS, 60-second socket timeouts, an 8 GiB ceiling, exclusive partial creation, and SHA256 verification before archive promotion or extraction. No resume is implemented. Interrupted or invalid partial files remain for inspection and block another download until explicitly moved aside by the owner.

Extraction refuses an existing source or staging directory. It accepts only the expected archive root, regular files/directories and confined relative links. It rejects path traversal, duplicate entries, absolute/escaping links, device nodes, and hard links whose verified target has not appeared. Python 3.12's `data` extraction filter adds per-entry traversal/link protections. Legitimate internal relative symlinks remain symlinks. It verifies `chrome/VERSION` before promoting the staged source. A failed or interrupted extraction remains at `src.extracting`; no source or user files are automatically removed.

The expected top-level archive directory is `chromium-157.0.8103.51`, matching the official archive naming convention; this packet has not downloaded the archive to verify its member layout. A different root or forward hard-link ordering fails safely and requires inspection, not loosening path protections. The 8 GiB ceiling is a safety bound, not a measured archive size. Storage fit and extraction throughput remain unmeasured.

Verification for this packet is Python syntax and one `--dry-run`. No download, source extraction, toolchain installation, or build was executed. The earlier unfinished CEF patch remains preserved on its own branch and is not applied here. Do not copy Crest's source-directory deletion policy; old data requires an explicit ownership/recovery decision.
