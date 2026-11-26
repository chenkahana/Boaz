# PLAN-02: Chromium DMG runtime acceptance

Wave: 0 Stability
Status: Ready
Depends on: nothing. Splits naturally; claim one gate row at a time and note it in your draft PR.

## Goal

Close every "Source implemented; runtime acceptance owed" and "Pending" gate in
[docs/chromium/parity.md](../../chromium/parity.md) with recorded evidence. A failure found while gathering
evidence is a release-blocking bug: fix it before the next feature release.

## Why

The DMG auto-publishes on every master commit that touches the Mac app. Right now upgrades, profiles, passwords,
permissions, downloads and extensions ship on source-level confidence only. Stability means proven, not plausible.

## Scope, in ledger order

1. **Upgrade and data continuity**: upgrade a real install from the previous sandboxed build to the current DMG;
   tabs, spaces, archive, settings, sign-ins and cookies survive (must-have #13). Automate on a GitHub-hosted Mac
   runner where possible: download both DMGs, install, seed a fixture library, upgrade, assert.
2. **Profiles, private data, passwords**: per-profile isolation, password save/fill, private data boundaries.
3. **Permissions, downloads, extensions**: prompts, authenticated downloads, the extension cohort from the ledger.
4. **Runtime reopen / popup quit / engine switching** and **WebKit preservation** (`project-webkit-dmg.yml`).
5. What CI genuinely can't do, write as a step-by-step manual script with a results template so Chen (or any Mac)
   can run it in under an hour; record his run as the evidence.

## Non-goals

- Performance budgets (PLAN-04) and the deferred exhaustive matrices/dogfooding (stays deferred per the ledger).

## Acceptance criteria

- [ ] Every parity-ledger gate row cites dated evidence or has an issue filed for its failure.
- [ ] Automated acceptance runs in CI on release candidates where the runner allows it.
- [ ] Manual remainder exists as a script + results template in docs/chromium/.

## Verification

CI run links plus the edited parity.md rows; evidence lands in the ledger itself.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
