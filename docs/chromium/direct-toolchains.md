# Direct Chromium toolchain preparation

This independently authored recipe targets the verified Chromium 157.0.8103.51 source. It contains no Crest imports or copied implementation. It installs only four GCS toolchain packages and six CIPD packages identified in upstream DEPS; it does not generate GN files, install Metal, or compile Chromium.

```sh
/opt/homebrew/bin/python3.12 Tools/chromium/prepare-toolchains.py --dry-run
/opt/homebrew/bin/python3.12 Tools/chromium/prepare-toolchains.py --prepare
```

The second command dispatches the existing verified-volume guard. Direct downloads, extraction stages, CIPD cache, resolution records, and temporary files remain under `/Volumes/BoazBuild/cef/direct`; the guard owns logs and process supervision under `/Volumes/BoazBuild/cef`. It enforces both filesystem reserves and prevents concurrent guarded stages.

The script verifies the source version, depot_tools commit, and SHA256 of the already-installed CIPD client. It calls `.cipd_client` directly, bypassing the wrapper's automatic bootstrap/self-update, and also disables depot_tools auto-update. No global tool installation or Xcode selection change occurs.

Before any CIPD ensure, all six upstream versions are resolved to immutable instance IDs and written to `direct/toolchains/resolved.json`, bound to the recipe SHA256. Retries reuse that resolution. Ensure files contain only those instance IDs, with integrity checking enabled. A partial resolution remains for inspection; it is not silently overwritten or re-resolved. Resolved instance IDs are execution-time evidence, not yet present in this tooling commit.

GCS artifacts are checked against upstream byte counts and SHA256 before extraction. `gclient.py` in the pinned depot_tools implementation, lines3432–3464, extracts these GCS archives directly into the dependency destination without stripping a root component. This script preserves that layout. It restricts extraction to regular files, directories and confined links, rejects traversal/special entries/duplicates/forward hard links, and uses Python 3.12's data filter. Download partials and failed extraction stages remain untouched on failure.

Each package is installed into a new stage. An existing destination is reused only if its full file content, executable bits, and symlink targets match the verified stage; CIPD's own `.cipd` metadata is excluded from this payload comparison. Any difference stops preparation and preserves both trees. Nothing removes or replaces preexisting outputs. Installation receipts record file hashes and the recipe; subsequent runs recheck them. Empty directories are not part of payload identity. Stages retained after an identical existing destination are intentionally not cleaned automatically.

Upstream pins come from root `DEPS`: clang1020–1024, Rust1119–1123, libclang1155–1159, Node865–878, GN570/1185–1193, Python288, TypeScript3202–3211, ANGLE3523–3529. DevTools `third_party/devtools-frontend/src/DEPS:152–160` pins esbuild; Dawn `third_party/dawn/DEPS:31,601–608` pins Go.

Known limitations at handoff:

- The source archive already contains populated libclang, Python host, and esbuild destinations. Exact comparison may find matching packages or stop on a conflict; no result is assumed.
- Metal's command exists as an Xcode wrapper but the actual Metal component was unavailable during prerequisite inspection. Its separate installation is outside this tool.
- GN generation may identify additional optional dependencies. This is the first host-build package set, not an assertion that every Chromium target is provisioned.
- Package instance resolution, downloaded archive layouts, installation receipts, and client/network compatibility have not been exercised. No toolchain download or install was executed for this commit.

Verification is Python syntax plus one read-only dry run. No new tests were added. The four compressed GCS downloads total about 354 MiB; expanded storage and linker memory remain unmeasured.
