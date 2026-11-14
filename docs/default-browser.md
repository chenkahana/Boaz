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

# Default browser on iPhone

iOS lets someone choose Boaz as their default browser only once Apple grants the managed entitlement
`com.apple.developer.web-browser` to Boaz's App ID (`com.chenkahana.boaz`). Everything that doesn't need the grant is
in place; this page lists what is done, what the Account Holder does in Apple Developer, and how to verify it.

Apple's requirements: [Preparing your app to be the default browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser).

## What Boaz already does

| Requirement | Where |
|---|---|
| Declares the `http` and `https` URL schemes | `project.yml`, `CFBundleURLTypes` of `Boaz-iOS` |
| No `UIWebView`; pages are system WebKit (`WebPage`/`WKWebView`) | `Apps/Browser` |
| On launch, a field for an address or search | the bar's **+** (New Tab) and the search overlay |
| Opens the link's exact URL (path, query and fragment untouched), in a new tab, or the tab already showing it | `Apps/iOS/Intents/DeepLink.swift` |
| Works on a cold launch: a link that arrives before the library has loaded is replayed once it has | `DeepLink.handle` |
| None of the `Info.plist` keys Apple rejects for browsers (`NSPhotoLibraryUsageDescription`, `NSLocationAlways…`, `NSHomeKitUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSHealth…`) and no Universal Links claims | `project.yml` |
| Settings › Default Browser: shows "Boaz is your default browser", or a button that opens iOS Settings › Apps › Default Apps | `Apps/iOS/Views/DefaultBrowserSection.swift` |

The entitlement and the Settings section are both in [`web-browser.yml`](../web-browser.yml), which `project.yml`
includes. Apple granted the entitlement on 2026-11-14 and it's on. With `enable: false` the app neither requests the
entitlement (signing would fail on an App ID without the grant) nor shows the Settings section.

The Settings section asks iOS with `UIApplication.isDefault(.webBrowser)` once per launch when Settings opens, and again
when you come back from the Settings app. iOS rate-limits that call; when it's limited, the section keeps offering the
button. The button opens `UIApplication.openDefaultApplicationsSettingsURLString`, the public URL for Settings ›
Apps › Default Apps.

## Getting the entitlement (Account Holder)

Apple Developer requires the **Account Holder** role to request a managed capability.

1. Sign in and open the request form: https://developer.apple.com/contact/request/default-browser-entitlement/
   (also reachable from Certificates, Identifiers & Profiles › Identifiers › `com.chenkahana.boaz` › Capability
   Requests › Default Web Browser).
2. Fill it in:
   - **Team**: the Boaz team. **Website**: https://chenkahana.com/boaz
   - Tick each requirement: `http`/`https` in `Info.plist`, no `UIWebView`, an address/search field on launch, no
     Universal Links claims, none of the listed `Info.plist` keys, and direct navigation to the requested URL. Boaz meets
     all of them (table above).
   - **App Name**: Boaz. **Bundle ID**: `com.chenkahana.boaz`.
   - **Built for iOS**: confirm. **Already available**: Yes, https://apps.apple.com/app/boaz-browser/id6832646304
   - **Browser App Installation (EU)**: No. Boaz doesn't install apps or marketplaces.
   - **Other details**: no account is needed; links open in a new tab with the URL unchanged.
3. Wait for Apple's answer. Check it under the App ID's **Capability Requests** tab (Status).

## After Apple grants it

1. In Certificates, Identifiers & Profiles › Identifiers › `com.chenkahana.boaz` › **Capabilities**, enable
   **Default Web Browser** and save. Automatic signing (Xcode, Xcode Cloud) then puts it in new provisioning profiles;
   a manual profile has to be edited and saved (or regenerated) to pick it up.
2. In `project.yml`, set `enable: true` on the `web-browser.yml` include and run `make project`. That adds the
   entitlement to `Apps/iOS/Boaz.entitlements` and compiles the Settings section (`DEFAULT_BROWSER`).
3. Build a signed Release (`make device DEVICE=<udid>` or an archive) and confirm the entitlement made it in:

   ```bash
   codesign -d --entitlements - Boaz.app | grep -A1 com.apple.developer.web-browser
   security cms -D -i Boaz.app/embedded.mobileprovision | grep -A1 com.apple.developer.web-browser
   ```

   Both must show `com.apple.developer.web-browser` set to true. If the profile lacks it, signing fails with a
   "provisioning profile doesn't include the entitlement" error: go back to step 1.
4. App Review: mention in the review notes that Boaz holds the default browser entitlement and can be chosen in
   Settings › Apps › Default Apps › Browser App. Don't add any of the `Info.plist` keys listed above in later versions.

## Verification

Now, without the grant:

- [ ] `make ios` builds; `Apps/iOS/Boaz.entitlements` has no `com.apple.developer.web-browser`.
- [ ] A build generated with `web-browser.yml` enabled compiles unsigned (proves the section and setting merge).
- [ ] In the simulator, `xcrun simctl openurl booted "boaz://open?url=https%3A%2F%2Fexample.com%2Fa%3Fq%3D1%23top"`
      opens `https://example.com/a?q=1#top` in a new tab, both with Boaz running and after quitting it (cold launch).
      This is the same `DeepLink` path a web link takes.
- [ ] Sending the same link again switches to that tab instead of opening a second one.
- [ ] `boaz://search?q=…`, widgets and App Shortcuts still work; `boaz://open?url=javascript:alert(1)` does nothing.

After the grant, on a physical iPhone:

- [ ] Settings › Apps › Default Apps › Browser App lists Boaz; choose it.
- [ ] A link tapped in Mail, Messages and Notes opens in Boaz with its path, query and fragment, cold and warm.
- [ ] A Universal Link to another app (for example a YouTube video) still opens that app.
- [ ] Boaz › Settings shows "Boaz is your default browser"; switching the default back to Safari and returning to Boaz
      shows the button again.
