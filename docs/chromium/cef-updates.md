# Chromium updates and security response

The active application uses the direct Chromium source pin. Run `python3 Tools/chromium/check-update.py`; it checks the official Mac stable ChromiumDash metadata against `Tools/chromium/source.lock.json`, without changing inputs or downloading binaries. Errors return nonzero with `updateAvailable: null`. HTTPS stays on the official host; response limit is 1 MiB, socket timeout 20 seconds and checked read budget 60 seconds.

The live check on 2026-11-13 passed and found stable `158.0.8127.37`, published 2026-11-12, ahead of the current `157.0.8103.51` feasibility pin. This is an update finding, not a security-advisory classification. Keep running builds frozen; review upstream advisories and validate the new source archive/revision/checksum before a separate rebuild checkpoint in this same PR. Production acceptance requires resolving this stale-pin finding.

For the direct build, update the verified source lock, SDK/toolchain pins if required, and every patch preimage/postimage. Use `Tools/chromium/apply-patches.py --apply`, `install-host.py --install`, then guarded focused/full builds and the application build/stage/sign commands. Preserve previous compiled and signed artifacts. Never rewrite an already-applied patch entry in place; use an incremental correction or a new clean source checkout for the revision update. The response ownership, 72-hour target and unchanged acceptance gates below apply to the direct application.

## Retained CEF feasibility checker

Run `python3 Tools/cef/check-update.py` from the checkout, or pass `--lock PATH`. The checker reads the official CEF build metadata and compares numeric Chromium and CEF version components with `Vendor/CEF.lock`. It selects the newest stable macosarm64 standard artifact, reports its URL, size, publication time and published SHA1, and downloads no binary. The full new CEF commit and independently calculated SHA256 must be verified before changing the lock; the CDN supplies only a commit prefix and SHA1 here.

Successful JSON has `status: "ok"` and a boolean `updateAvailable`. Errors return exit code1, `status: "error"`, `updateAvailable: null`, and an explanation. An unavailable feed is never reported as up to date. Requests require HTTPS, use a 20-second socket timeout, a 60-second read budget checked between chunks, and a 32 MiB response cap. A blocked read can consume its socket timeout beyond the read budget. No lock changes, publication, scheduled automation, or issues are created.

The maintainer, Chen, owns security triage and release decisions. The build orchestrator owns revision verification, reproducible builds, acceptance evidence, and preparation of signed artifacts. The response target is a verified security update within 72 hours of upstream disclosure or detection, whichever reaches the maintainer first. Record that start time, advisory/release links, affected shipped versions, and a named owner in the PR evidence ledger. A newer CEF build alone does not prove a security fix; inspect Chromium advisories and the CEF changes before classifying it.

For a security update:

1. Verify the complete CEF commit, Chromium revision, compatible depot_tools revision, artifact identity, and checksum. Update the prebuilt lock and custom-build pins together in the authorized update work. The current lock is for feasibility binaries; production codec/DRM artifacts require their own verified build provenance.
2. Build through `Tools/cef/build-cef.sh` and its storage guard on the verified build volume. Keep the prior artifacts and source data. Review any CEF patch against the new revision; a conflicting or changed security-sensitive patch blocks release.
3. Run the required engine builds and affected acceptance scenarios, including lifecycle, profiles/private data, passwords, extensions, media and DRM. Run performance scenarios affected by the update. Record failures explicitly; the 72-hour target does not waive gates.
4. Prepare the non-publishing release artifact using the accepted release configuration. Verify nested signatures, entitlements, Developer ID signing, notarization, clean-account launch, Sparkle upgrade and delta behavior. Local Apple Development spike signing is not distribution acceptance. Production publication requires the release decision and passing migration gates.
5. Prepare a higher-version WebKit rollback artifact that preserves both engines' data. Verify its update path before changing the production appcast. Do not roll users back to a known-vulnerable Chromium build merely because it is available.

Escalate immediately to Chen if the upstream fix is unavailable, the build fails, a patch cannot be safely ported, signing/notarization is unavailable, or a required product gate fails. Record the blocker, user exposure, next action, owner, and next review time. If the 72-hour target will be missed, state the missed target explicitly and decide whether a verified WebKit rollback is needed. Never mark the response complete because an update was detected or compiled.

The checker is read-only tooling. Continuous monitoring and release scheduling remain unwired until the release architecture is accepted. Until then, the named maintainer must arrange manual checks; no automatic coverage is claimed.
