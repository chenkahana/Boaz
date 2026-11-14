
- Date: 2026-11-13
- Trigger: Stopped the migration broadly on custom-build storage and an unavailable worker provider, although prebuilt feasibility experiments were independent.
- Rule: Scope blockers to their dependency. Install authorized tools, use default workers, and continue prebuilt experiments while preparing custom-build storage. An APFS sparse bundle can provide build filesystem semantics on an existing exFAT SSD without reformatting it; verify it first.
- Scope: repo / Chromium migration

- Date: 2026-11-13
- Trigger: Repeated architecture permission questions after the user delegated product and implementation judgment.
- Rule: Make routine architecture and scope decisions from evidence under existing authorization. Keep acceptance gates explicit; ask only for genuinely missing external facts or actions that require separate authorization.
- Scope: repo / Chromium migration

- Date: 2026-11-13
- Trigger: Ended the implementation turn at a prototype progress checkpoint despite ready authorized work.
- Rule: Continue through ready implementation packets; a progress update is not a completion boundary. Stop only at an actual dependency, requested review, or completed scope.
- Scope: repo / long-running migration

- Date: 2026-11-13
- Trigger: Repeated compilation polling while independent migration implementation remained ready.
- Rule: Keep build inputs stable, dispatch bounded source implementation in parallel, and scope runtime blockers to the exact dependent work. Code complete is a milestone, never a substitute for acceptance.
- Scope: repo / long-running builds and migrations

- Date: 2026-11-14
- Trigger: Implemented and installed iPhone layout changes from `feat/phone-toolbar` without checking whether the user expected current `master`; that branch still contained the retired Spaces UI.
- Rule: Before changing or installing an app, compare the checkout branch with the requested release base and build from a worktree at fetched `origin/master` when the user asks for latest master.
- Scope: repo / iOS device installs

- Date: 2026-11-14
- Trigger: A floating bottom toolbar and a web view that ignored the bottom safe area let page content sit behind the toolbar on unfolded portrait.
- Rule: When the requirement is reachable page content, make the toolbar consume layout height and keep the web view inside that viewport; inspect both the toolbar container and the web view's safe-area modifiers.
- Scope: repo / iPhone Duo browser layout
