# Chromium security updates

Boaz for Mac ships its own build of Chromium, pinned in `Tools/chromium/source.lock.json`. When Google ships a Chrome
stable update with security fixes, the target is a published Boaz DMG on that Chromium version within 72 hours of
Google's release. The clock (T0) starts at the chromiumdash publish time of that version. [SECURITY.md](../../SECURITY.md)
states the policy for users.

## Steps

| Step | What happens | Owner | Command or place |
|---|---|---|---|
| D detect | A scheduled check compares the pin with Mac stable every 6 hours and keeps one open issue, "Chromium security update: …", while Boaz is behind. The issue gives T0. | CI | `.github/workflows/chromium-update.yml`; by hand: `python3 Tools/chromium/check-update.py` |
| T triage | Read the [Chrome Releases](https://chromereleases.googleblog.com/) post: security fixes, severity, and whether Google says an exploit exists in the wild. Decide go or no-go. A new major line costs more patch work than a patch release (see [When a step fails](#when-a-step-fails)). | Chen | the issue |
| B bump | Pin the new lite source archive: version, URL, and the SHA-256 from Google's published `.hashes` file. | dev | `security-update.py VERSION` (below) |
| F fetch | Download and verify the archive, move the current tree aside, extract the new one, and check that its DEPS still pin the same toolchains. | build Mac | same command |
| P rebase | Apply the patch series to the new tree, rewrite `patches.lock.json`, commit the pins. Manual only when a patch conflicts. | dev | same command |
| C build | Apply the patches, install toolchains and the host, build Chromium, pack and upload the `chromium-base-KEY` prerelease. | build Mac | same command |
| R candidate | Push the branch and run the Release workflow with `dry_run` on it. It builds, signs and notarizes the DMG and keeps it as a workflow artifact without publishing. | CI | `gh workflow run release.yml --ref BRANCH -f dry_run=true` |
| S smoke | On that DMG, installed over the current release: must-haves 1 (every page in Chromium), 3 (each space's own profile session, `chrome://` pages), 4 (extensions, `chrome://extensions`, Web Store install, popups) and 13 (spaces, tabs, history, passwords and sign-ins survive the update), plus [QA](../qa.md) §3. | dev | the DMG |
| G publish | Merge to master. The Release workflow ships `vX.Y.Z` with the DMG and `appcast.xml`. | Chen | the merge |
| V verify | `releases/latest/download/appcast.xml` lists the new version, and an installed previous release updates to it through Sparkle. | dev | `curl -sL https://github.com/chenkahana/Boaz/releases/latest/download/appcast.xml` |

`check-update.py` reads Google's Mac stable metadata from chromiumdash over HTTPS (1 MiB limit, 20-second socket
timeout, 60-second read budget) and changes nothing. A feed error exits nonzero with `updateAvailable: null`, so an
unreachable feed never reads as up to date.

## Running the build-Mac steps

Steps B to C are one command on the build Mac, from a clean checkout on a working branch with `/Volumes/BoazBuild`
attached and no other build running:

```sh
Tools/chromium/security-update.py 159.0.8154.40 --dry-run   # prints every step, its owner and command
Tools/chromium/security-update.py 159.0.8154.40
```

It runs these steps in order and stops at the first failure:

| Step | Runs |
|---|---|
| `bump` | rewrites `source.lock.json`; refuses a version that isn't newer than the pin, because Chromium profiles don't downgrade |
| `fetch` | `fetch-source.py --fetch` |
| `toolchains-check` | `prepare-toolchains.py --check-deps` |
| `rebase` | `rebase-patches.py --rebase` |
| `commit` | commits the source, patch and toolchain pins and `patches/` on the branch, then checks no other Chromium input is uncommitted |
| `apply` | `apply-patches.py --apply` |
| `toolchains`, `objdump` | `prepare-toolchains.py --prepare`, `prepare-objdump.py --prepare` |
| `host` | `install-host.py --install` |
| `build` | `build.py --build --jobs 6` (`--jobs N` to change; memory pressure on the build Mac caps it at 6 to 8) |
| `pack` | `chromium-base.py pack --upload` |

Every run writes a timing receipt, `build/security-update/VERSION-TIMESTAMP.json`, with each step's start, end,
duration and exit code. After fixing a failure, continue with `--from STEP`; that run writes its own receipt.
Each tool also runs on its own, with the commands in [direct-build](direct-build.md) and [release](../release.md).

**Source trees.** `fetch-source.py` keeps the previous version's tree and receipts (`chromium/`, `toolchains/`,
`patches-applied.json`, `patch-history/`, `host-installed.json`, `host-history/`, `native-built.json`) under
`/Volumes/BoazBuild/cef/direct/previous/VERSION`, and moves them only after the new archive is downloaded and
verified. Keep that tree until the new release has passed V. On 2026-11-26 the 157 tree took 26.6 GiB, 13.5 GiB of
it the build output, so two trees fit in the volume's 158 GiB free above the guard's 20 GiB reserve. Remove an older
`previous/VERSION` by hand when space runs short.

**Patch rebase.** The lite archive has no `.git`, so there is no three-way merge. `rebase-patches.py` applies each
patch, in order, to copies of the files it touches. A clean apply gets new before and after hashes in
`patches.lock.json`, and every patched file whose upstream content changed is listed under `review`: the patch
still applied, but read it against the new code, above all in security-touched files. A conflicting patch is listed
with git's error and keeps its old entry, so `apply-patches.py` refuses it. Edit the listed patch against the new tree, then run `security-update.py VERSION --from rebase`. Every
rebase starts again from the unpatched tree.

**Toolchains.** `toolchains.lock.json` stays valid while, for each pinned destination, the DEPS entry that owns it
(root `DEPS`, or the dawn and devtools-frontend DEPS for their own directories) still pins exactly that artifact: GCS
object, SHA-256 and size, or CIPD package and version, with `Var()` resolved. The DEPS files are parsed, never run. When they don't, usually at a new major version, `toolchains-check` lists what
moved. Re-pin those entries from the new DEPS (see [direct-toolchains](direct-toolchains.md)), update
`toolchains.resolved.json` (its `recipe_sha256` is the new lock's SHA-256; resolve a moved CIPD version with
`.cipd_client resolve PACKAGE -version VERSION`). When clang moves, re-pin `toolchains.objdump.json` too: its
`llvmobjdump` package carries clang's package version, so take the object's generation and MD5 from the GCS object
metadata, check the MD5, and record its SHA-256 and extracted tree. Then continue with `--from toolchains-check`.
A moved rust also invalidates the content-blocking library, whose receipt is bound to the toolchain lock, so `build`
stops. After the `toolchains` step has installed the new rust, rebuild it (`build-adblock.py`), re-validate its assets
against the new library (`adblock/prepare-assets.py --resources … --output` a new `assets-DATE` directory under
`direct/adblock`), point `adblock/assets.lock.json` at that directory and its new `assets.json` (staging refuses assets
validated against another library), commit, and continue with `--from host`.

## When a step fails

- **Archive layout.** The fetcher accepts only a `chromium-VERSION` root and checks `chrome/VERSION`. Lite archive
  sizes vary (2.08 GB for 157.0.8103.51, 0.96 GB for 157.0.8103.81), so a layout change stops extraction and leaves
  `src.extracting` for inspection. Don't loosen the path checks to get past it.
- **A new major line.** Expect patch conflicts in the files Boaz patches (53 patches over 107 files) and toolchain
  re-pins. If the work won't fit inside 72 hours, tell Chen with the options and the exposure.
- **Build memory.** Never overlap two full builds. If macOS reports memory-pressure warnings, the guard stops cleanly;
  continue with `--from build --jobs 4`.
- **Pack refuses.** `chromium-base.py` packs only a build that matches the committed inputs. Commit, then
  `--from pack`.
- **Notarization or CI outage.** Re-run the workflow when Apple or GitHub recovers, and note the delay.

Escalate to Chen at once when the upstream fix is unavailable, the build fails, a patch can't be ported safely,
signing or notarization is down, or a must-have fails in S. Record the blocker, who is exposed, the next action, its
owner and when you'll look again, in the issue. Recovery is always forward: fix the problem in a newer release. Never
ship a Chromium older than the one users have, and never route pages to another engine to cover a missed update. If
the target is missed, the release notes say so and give the lag. A detected or compiled update isn't a shipped one.

## Release rules for security updates

`docs/release.md` asks engine changes to soak for a day before the next risky release. Whether a security update
skips the soak, or soaks after it ships, is Chen's call. Until he decides, a security update follows the normal rule.

## Drill record

Every step of one real upstream patch release, timed from T0. Times are UTC; durations come from the receipts.

Upstream version: — · T0 (chromiumdash): — · Published Boaz version: — · Total: —

| Step | Budget | Started | Ended | Duration | Notes |
|---|---|---|---|---|---|
| D detect | 6 h | | | | |
| T triage | | | | | |
| B bump | 5 min | | | | |
| F fetch and extract | 1 h | | | | |
| P rebase | 0.5–4 h | | | | |
| C build | 4–5 h | | | | |
| C pack and upload | 0.5 h | | | | |
| R candidate | 0.3 h | | | | |
| S smoke | 2 h | | | | |
| G publish | ≤ 24 h | | | | |
| V verify | 0.5 h | | | | |

### Phase 0 (catch-up, outside the 72 h clock)

157.0.8103.51 → 159.0.8154.34 (Mac stable since 2026-11-24 18:32 UTC), two major lines, run on 2026-11-26 before
the first real drill. Times are UTC; they come from the security-update receipt and the volume guard's logs.

| Step | Started | Ended | Duration | Notes |
|---|---|---|---|---|
| B bump | 17:26:55 | 17:26:57 | 2 s | SHA-256 from Google's `.hashes` |
| F fetch and extract | 17:26:57 | 17:32:21 | 5.4 min | lite archive 0.98 GB; tree 8.1 GiB before the build |
| F toolchains-check, re-pin | 17:32:21 | 17:34:16 | 2 min | clang, rust, libclang and gn moved; `toolchains.objdump.json` re-pinned with clang |
| P rebase | 17:34:16 | 17:39:41 | 5.5 min | 18 of 53 patches conflicted; 13 fixed by hand, 5 then applied unchanged |
| C apply, toolchains, objdump | 17:40:20 | 17:42:44 | 2.4 min | |
| C content-blocking library | 17:42:59 | 17:45:14 | 2.3 min | new rust; assets re-validated, rules unchanged |
| C host, host objects (`-k 0`) | 17:45:14 | 18:13:39 | 28 min | 5 host files needed 159 API fixes |
| C full build | 18:13:45 | | | `build.py --build --jobs 6`, 50,109 steps |
