# CEF update checker (retired)

The shipped Mac app uses the direct Chromium build. Its security updates follow
[security-update.md](security-update.md): detection, owners, the 72-hour target, escalation and the drill record.

## Retained CEF feasibility checker

Run `python3 Tools/cef/check-update.py` from the checkout, or pass `--lock PATH`. The checker reads the official CEF build metadata and compares numeric Chromium and CEF version components with `Vendor/CEF.lock`. It selects the newest stable macosarm64 standard artifact, reports its URL, size, publication time and published SHA1, and downloads no binary. The full new CEF commit and independently calculated SHA256 must be verified before changing the lock; the CDN supplies only a commit prefix and SHA1 here.

Successful JSON has `status: "ok"` and a boolean `updateAvailable`. Errors return exit code1, `status: "error"`, `updateAvailable: null`, and an explanation. An unavailable feed is never reported as up to date. Requests require HTTPS, use a 20-second socket timeout, a 60-second read budget checked between chunks, and a 32 MiB response cap. A blocked read can consume its socket timeout beyond the read budget. No lock changes, publication, scheduled automation, or issues are created.

`Vendor/CEF.lock` is the CEF 156 feasibility lock. It isn't shipped and gets no security updates.
