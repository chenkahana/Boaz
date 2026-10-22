# Feature: Sync (owned, encrypted, self-hostable)

Surpass-Arc bet (#4 in `docs/PLAN.md`). Arc's sync dies with its servers on 2026-12-22; ours must be un-sunstable.

## Goal

Spaces, tabs, folders, rules, themes, and settings follow the user across machines - with keys the server never sees and a server the user can replace.

## Spec

- E2E encryption: key derived from a user passphrase (or stored device key + recovery phrase); server stores opaque encrypted blobs only.
- Reference relay: single-container server (stateless API + object storage), documented for self-hosting; hosted default relay for convenience, swappable by URL in settings.
- Data: the full JSON model (`docs/ARCHITECTURE.md` data model), versioned, with per-record tombstones.
- Export: one click -> JSON + Markdown of every space/tab/shelf/rule, no account required. Import works offline.
- Conflict policy: last-writer-wins per record, with a recoverable 30-day blob history.

## Acceptance criteria

- [ ] Two machines converge spaces/tabs/rules within 10s of a change
- [ ] Server-side inspection shows only ciphertext (documented test)
- [ ] Point settings at a self-hosted relay and everything still works
- [ ] Full export produces valid JSON + Markdown without any network
- [ ] Recovery phrase restores a fresh install

## Implementation notes

- `core/sync` is engine-agnostic by design (architecture rule).
- No analytics on sync traffic beyond aggregate blob counts on the hosted relay; publish the relay's data policy in-repo.

## Out of scope

Live collaborative/shared spaces (real-time co-browsing) - post-v1 exploration.
