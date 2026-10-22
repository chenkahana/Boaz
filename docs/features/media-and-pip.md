# Feature: Media controls and auto-PiP

Priority basis: ranked #3 by users - auto-PiP on Google Meet was called the feature that "knows me deeply" (`docs/RESEARCH.md`).

## Goal

Media never gets lost and never blocks you. Leave a call tab, the video follows you; come back, it docks home.

## Spec

- **Auto-PiP:** switching away from a tab with active camera/mic call or playing video opens picture-in-picture automatically; switching back closes it. Per-site rules (always/never/ask), sensible defaults (Meet/Zoom/YouTube: ask once, remember).
- **Mini-player:** persistent bottom-left control for whatever is playing (play/pause, seek, mute, title); one global shortcut (`Cmd+Shift+P`) toggles PiP manually.
- Hovering a pinned media tab shows live playback state and controls.
- Multiple media sources: most recent wins the mini-player; others pause-button reachable via hover.

## Acceptance criteria

- [ ] Auto-PiP fires on tab switch away from an active Meet/Zoom/YouTube tab, per stored site rule
- [ ] Returning to the tab docks PiP automatically
- [ ] Per-site rule editing (always/never/ask) persists
- [ ] Mini-player reflects and controls current media from any space
- [ ] Global shortcut works when the browser is not focused (OS-level binding where platform allows)

## Implementation notes

- On the Firefox base: Meet auto-PiP is a known weak spot (user reports) - budget real testing time here; this is a differentiator, not a checkbox.
- `chrome/media` owns UI; site rules in the JSON model.

## Out of scope

System-wide media key remapping beyond the single global shortcut.
