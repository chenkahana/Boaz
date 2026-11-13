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
includes with `enable: false`. While it's off, the app neither requests the entitlement (signing would fail without
the grant) nor shows the Settings section (it would point to a choice iOS doesn't offer yet).

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
