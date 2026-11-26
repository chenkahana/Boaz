#!/bin/bash
# Tools/perf/run.sh — the one-command entry point for a PLAN-04 perf session (docs/qa.md §4).
#
# Only ever run this on the orchestrator's explicit go, with the Mac idle and on AC power, and never while Chen
# is screen-sharing: every row drives a real GUI window and steals keyboard focus. Chen's own production Boaz may
# stay running — the perf copy launches under the development identity (com.chenkahana.boaz.chromium.dev), a
# different bundle id, so it can't reach his copy — but no OTHER com.chenkahana.boaz.chromium.dev process
# (including a PLAN-16 dev build) may be running; see perf.py's guard_no_other_dev_instance_running.
#
# Usage: Tools/perf/run.sh [dmg-tag] [N]
#   dmg-tag  Published release tag to measure (default v0.4.48).
#   N        Samples per row after one discarded warm-up (default 7; see perf.py's `summarize`).
#
# Writes <run-dir>/results.json and results.md; prints the markdown table to stdout. Takes roughly 25 minutes.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dmg_tag="${1:-v0.4.48}"
samples="${2:-7}"

command -v python3 >/dev/null || { echo "run.sh: python3 is required" >&2; exit 1; }
command -v swift >/dev/null || { echo "run.sh: swift (Xcode command line tools) is required" >&2; exit 1; }
command -v gh >/dev/null || { echo "run.sh: gh (GitHub CLI) is required to download the release DMG" >&2; exit 1; }

exec python3 "${script_dir}/perf.py" all --dmg-tag "${dmg_tag}" -N "${samples}"
