# Extension artifact for the Chromium spike

## Verified artifact

uBlock Origin Lite `2026.1110.1816`, from the official
[uBlockOrigin/uBOL-home release](https://github.com/uBlockOrigin/uBOL-home/releases/tag/2026.1110.1816).

- Asset: `uBOLite_2026.1110.1816.chromium.zip`
- Size: 9,081,087 bytes
- GitHub-published and locally verified SHA-256: `85fe5909366e8ada66c5b331bbdbf69cf5100245ed6161b1e4e2f1f848ec7d03`
- [Download](https://github.com/uBlockOrigin/uBOL-home/releases/download/2026.1110.1816/uBOLite_2026.1110.1816.chromium.zip)
- Preparation: 1,029 ZIP entries extracted into a new ignored build directory after checksum validation; absolute paths, traversal, backslash paths, duplicate names, symlinks, and special entries were rejected.

No browser was launched and no user profile was modified during preparation. This is artifact verification, not an extension-runtime pass.

## Manifest evidence

| Field | Value |
|---|---|
| Manifest version | 3 |
| Minimum Chrome version | 122.0 |
| Background worker | `/js/background.js`, module |
| Action popup | `popup.html` |
| Permissions | `activeTab`, `alarms`, `declarativeNetRequest`, `offscreen`, `scripting`, `storage`, `unlimitedStorage`, `userScripts` |
| Host permissions | `<all_urls>` |
| Static content scripts | None; `js/scripting-manager.js` dynamically calls `browser.scripting.registerContentScripts` |
| Declarative rulesets | 56 resources; six enabled by default |
| Default enabled rulesets | `ublock-filters`, `easylist`, `easyprivacy`, `pgl`, `ublock-badware`, `urlhaus-full` |
| Manifest public key | Absent; do not assume the unpacked extension has its store ID |

The worker and popup files exist. The popup queries the active tab in the current window, making it a useful probe of the CEF host's tab/window semantics.

## Next runtime checks

1. Launch the isolated Chrome-style spike with `--load-extension` pointing to this unpacked artifact. Record the runtime extension ID rather than hardcoding the store ID. Keep the artifact path stable across relaunches.
2. Verify the extension appears in `chrome://extensions` without install errors and its module worker starts.
3. Open the action popup against an ordinary page. Verify it reports the page's hostname and filtering state, rather than the extension page or another window.
4. Exercise network blocking and dynamic cosmetic/content-script registration through the extension's own controls. Verify behavior on both visible panes if split view is available.
5. Relaunch with the same isolated profile and artifact path; verify settings and active rulesets persist.

These checks do not establish CRX installation, Chrome Web Store installation, native messaging, or the remaining seven required extensions. Each remains a separate acceptance row.
