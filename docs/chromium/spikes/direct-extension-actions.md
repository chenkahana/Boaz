# Native extension actions

Status: implementation in progress, not extension acceptance. The direct host uses Chromium's `ExtensionActionViewModel` and native implementations of `ExtensionActionDelegate` and `ExtensionView`. It does not navigate an ordinary tab to a popup URL or synthesize an activeTab grant.

The model's user-action path invokes `ExtensionActionRunner` against the actual active WebContents. Its popup factory retains Chromium's extension window controller, profile and incognito checks. Native controls must validate their expected active page and anchor window before invocation. Side-panel actions remain explicitly unsupported in this packet.

The native popup owns the genuine ExtensionViewHost, attaches its borrowed content view before renderer creation, and defers presentation until load. Lifetime, focus, accessibility and actual extension behavior require runtime verification. Programmatic `action.openPopup`, command registration, context menus and withheld-site-permission reload prompts remain separate requirements.

A prepared three-file `native-popup-dialogs.patch` lets ExtensionView provide a synchronous dialog-suppression policy through ExtensionViewHost. Existing views default to their previous behavior. The experimental native popup suppresses JavaScript dialogs until native dialog handling is implemented; this is an explicit acceptance gap, not parity. The patch passed `git apply --check --no-index` against the pinned source. It is not applied to the active build and has not compiled yet.

Pinned source evidence: `extension_action_view_model.cc` owns user-action and popup dispatch; `extension_action_runner.cc` owns tab identity and grants; `extension_view_host_factory.cc` owns popup profile/window selection; `extension_action_api.cc` routes programmatic popup requests separately. No Crest implementation was copied.
