# Native extension actions

Status: native action controller, popup, ABI 4 connection and Swift menu compile. Runtime extension acceptance remains pending. The direct host uses Chromium's `ExtensionActionViewModel` and native implementations of `ExtensionActionDelegate` and `ExtensionView`. It does not navigate an ordinary tab to a popup URL or synthesize an activeTab grant.

The model's user-action path invokes `ExtensionActionRunner` against the actual active WebContents. Its popup factory retains Chromium's extension window controller, profile and incognito checks. Native controls must validate their expected active page and anchor window before invocation. Side-panel actions remain explicitly unsupported in this packet.

The native popup owns the genuine ExtensionViewHost, attaches its borrowed content view before renderer creation, and defers presentation until load. Lifetime, focus, accessibility and actual extension behavior require runtime verification. Programmatic `action.openPopup`, command registration, context menus and withheld-site-permission reload prompts remain separate requirements.

A prepared three-file `native-popup-dialogs.patch` lets ExtensionView provide a synchronous dialog-suppression policy through ExtensionViewHost. Existing views default to their previous behavior. The experimental native popup suppresses JavaScript dialogs until native dialog handling is implemented; this is an explicit acceptance gap, not parity. The patch passed `git apply --check --no-index` and was applied through the guarded series. Chromium rejected an inline nonempty virtual method under its style plugin; a second pinned patch moves that definition out of the header. Both the native popup and the affected upstream host then compiled.

Pinned source evidence: `extension_action_view_model.cc` owns user-action and popup dispatch; `extension_action_runner.cc` owns tab identity and grants; `extension_view_host_factory.cc` owns popup profile/window selection; `extension_action_api.cc` routes programmatic popup requests separately. No Crest implementation was copied.

The first action/popup packets include unload invalidation, deferred failure callbacks, a ten-second first-load timeout and re-entrant close checks around native presentation. The full build was checkpointed before guarded patch/source installation. Completed outputs were preserved.

ABI 4 exposes enumeration and user invocation to the Swift menu. Enumeration copies action IDs/names during its synchronous visitor. Invocation checks the expected active page, native anchor and browser lifetime. The action controller is destroyed on the browser close-scheduled notification, before delayed window cleanup. The menu uses a fresh snapshot when opened and invokes only after native menu tracking returns.

Compilation evidence on 2026-11-13: `20261113T115915.530995Z.log` compiled the action controller and bootstrap, then reported the inline-method style failure. `20261113T120045.844641Z.log` passed the popup and upstream ExtensionViewHost objects after the fix. `20261113T120117.676585Z.log` passed the Swift 6 ABI 4 UI library. Logs are under `/Volumes/BoazBuild/cef/logs/`. The full application build resumed with 12 jobs; no popup runtime, installation or cohort pass is claimed.
