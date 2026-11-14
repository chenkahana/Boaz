# Parked CEF fork tooling

S0 selected a direct Chromium host. This tooling preserves work prepared before that decision; it is not the active migration build route. No Boaz CEF patch has been applied or compiled.

The baseline build must finish before applying patches. `apply-fork.py` shares the build runner's exclusive lock and refuses changes while a guarded build is active. Its default mode only checks applicability and may run during compilation.

Patches live in `Tools/cef/patches`, use paths relative to the CEF repository, and are committed before application. Supply the reviewed SHA-256 explicitly:

```sh
python3 Tools/cef/apply-fork.py Tools/cef/patches/PATCH.patch --sha256 SHA256
python3 Tools/cef/apply-fork.py Tools/cef/patches/PATCH.patch --sha256 SHA256 --apply
Tools/cef/build-cef.sh --forked --smoke --jobs 12
```

The script verifies the APFS image identity and pinned CEF revision. It applies to `chromium_git/chromium/src/cef`, the build's actual checkout. `chromium_git/cef` is the download copy; changing it alone does not change the source being compiled. Conflicts stop application without cleanup or reset. Already-applied patches are recognized by a reverse applicability check.

An applied-patch receipt at `/Volumes/BoazBuild/cef/fork.json` records the CEF revision and patch hashes. Fork builds verify both source revisions, each hash, and reverse applicability before starting. They pass `--no-update` to the pinned upstream build script, preserving local changes and disabling CEF, Chromium, and depot-tools updates. Once a receipt exists, an ordinary build refuses to proceed without `--forked`.

The upstream `gclient_hook.py` invokes `tools/version_manager.py -u --fast-check` to regenerate translated files before project generation. Patches that add public APIs must also include their source/build declarations and follow the pinned translator's version annotations. A successful patch check is not evidence that generated bindings compile or the feature works.

After the smoke build and runtime acceptance pass, use `--forked` without `--smoke` to package a minimal distribution. Record the source revisions, patch hashes, generated API changes, artifact checksum, size, and verification evidence. Never publish an artifact merely because compilation succeeded.

Chromium-source patches need a separately pinned application path and receipt before use; this first tool intentionally accepts CEF-root patches only. No implicit directory traversal or mixed-repository patches are supported.
