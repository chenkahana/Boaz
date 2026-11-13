# Default browser on macOS

Boaz's existing General settings and onboarding use `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for HTTP and HTTPS. macOS handles any required consent before the async call completes. The action stays disabled while the request runs; errors appear inline. After both calls, Boaz checks the actual handlers again rather than assuming success.

`NSWorkspace.urlForApplication(toOpen:)` resolves each scheme. Boaz reports itself as default only when both resolved applications have its bundle identifier. Settings refreshes when shown and when the app becomes active, including after changes in System Settings. A partially changed or cancelled request does not produce a success message.

The existing `CFBundleURLTypes` declarations in `project.yml` register both schemes with the Viewer role. `project-dmg.yml` inherits them. No Chromium changes, dependency, entitlement, routing replacement, or new settings architecture is needed.

## Incoming links

`AppDelegate.application(_:open:)` passes the complete URL array to `MacModel.openExternal`. That method accepts HTTP/HTTPS URLs with a host and forwards each original URL to the existing Quick Window scene. Paths, query strings and fragments are not reconstructed. SwiftUI reuses a Quick Window for the same URL value.

Before the window-opening action exists, requests append to `pendingExternalURLs`. `registerOpenWindow` clears the pending array before scheduling its delivery, preventing repeated menu registration from replaying it. Main-window restoration is unchanged. The same application routing applies to both Mac distributions and remains available to the Chromium/WebKit migration.

## Verification

Generated App Store and DMG plists were parsed and both contain HTTP and HTTPS. Existing queue, Quick Window startup and restoration code paths were inspected. No new tests were added and no default-handler setting was changed during automated verification.

Build outputs and logs live under `build/default-browser/`, separately for each distribution. Both App Store and DMG Debug builds passed with Xcode 27.2, two build jobs, and signing disabled. Both built app plists retain HTTP/HTTPS registration. These are unsigned compilation checks, not installed-app acceptance or proof of Chromium integration.

Manual operating-system acceptance remains required on an installed signed build of each distribution:

1. Confirm Boaz is offered under System Settings > Desktop & Dock > Default web browser.
2. Request the change in Boaz Settings, accept macOS consent, and confirm the success text only after both handlers change.
3. Change the browser in System Settings, return to Boaz, and confirm the action returns. Cancel a request and confirm any error is shown without false success.
4. Open HTTP and HTTPS links from another app, both with Boaz running and after quitting it. Use a batch of distinct links and confirm each opens once.
5. Include paths, queries and fragments; check the resulting addresses. Repeat an identical URL and confirm the existing Quick Window is brought forward.
6. Confirm ordinary in-app navigation and restored main tabs remain intact. Repeat against the Chromium/WebKit DMG when that integration is available.

Apple references: [setting a scheme handler](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)), [checking the handler](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(toopen:)-7qkzf), and [URL-type registration](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes).
