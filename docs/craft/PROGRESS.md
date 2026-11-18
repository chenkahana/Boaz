# Craft research: progress

RESUME HERE: R0.3, Instruments. Try `xcrun xctrace record --template 'App Launch'` and 'Animation Hitches' against the Duo simulator (`BE5E8A2D-…`); Mac traces are needs Chen session.

Runtime rules for whoever resumes: never move, delete or modify `~/Library/Containers/com.chenkahana.boaz` or Chen's
Chromium profile data, and never quit Chen's running Boaz (must-have 13). Mac runtime that would risk either is
recorded as "needs Chen session" with exact steps. The iOS simulator only drives the Duo's folded screen; open, book
and laptop postures are "needs device". Binaries go to `~/tmp/codex/boaz-craft/`, never into git.

## Log

Append-only. One line per completed sub-step: date, step, what was done, commit.

- 2026-11-18 · setup · Worktree `~/.worktrees/Boaz/craft-research` on `docs/craft-research` from `origin/master` 66c3d63; plan copied to `PLAN.md` with checklist; `tasks/ux-review.md` copied to `inputs/` · (this commit)
- 2026-11-18 · R0.1 · iPhone Duo sim (folded) installed; isolated Mac WebKit build runs in background; standard iPhone, Duo postures and DMG runtime marked needs device / needs Chen session · (this commit)
- 2026-11-18 · R0.2 · iPhone main + tab flows recorded light and dark with audits; Mac static captures and menu inventory · (this commit)
