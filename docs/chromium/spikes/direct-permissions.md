# Direct-host native permission prototype

Status: source implementation only. Compile, factory routing, native runtime and security acceptance remain blocked on integration. This is not permission parity.

The factory returns a Chromium PermissionPrompt using an NSAlert sheet on the associated WebContents' actual top-level native window. It never asks the page for display text or origins. It copies Chromium request fragments and serializes requesting/embedding origins, rejects opaque origins, and retains no PermissionRequest pointers.

Supported requests: camera, microphone, notifications. Buttons: Not Now (Dismiss), Block (Deny), Allow (Accept), and Allow Once only when every request satisfies Chromium's DoesSupportTemporaryGrants predicate. Completion calls the delegate once, then returns without touching the potentially destroyed prompt. The first/default button grants nothing.

Geolocation, embedded permission elements, all other request types, quiet/abusive requests, missing windows and existing sheets are ignored without showing a louder prompt or persisting a denial. These remain explicit product blockers, including quiet indicators, geolocation accuracy selection, storage access, MIDI, local network, clipboard, exclusive access and OS-level media consent. No permission revocation UI or Boaz permission persistence is implemented.

## Lifetime contract

Construction posts display to the UI task runner; the request manager must own the prompt before the task executes. The posted task checks the weak delegate and GetCurrentPrompt identity. A sheet callback captures only a weak prompt. Destruction invalidates callbacks before ending the sheet. Chromium owns navigation/tab-close cancellation. Tab switching returns kDestroyPromptButKeepRequestPending, so hiding a page removes the sheet without answering the request. A later active-tab prompt may display it again. The factory checks WebContents/delegate identity and UI/main-thread execution.

## Deterministic source evidence

Pinned Chromium 157.0.8103.51:

- components/permissions/permission_prompt.h: Delegate request-pointer lifetime warning; GetWeakPtr, GetCurrentPrompt, GetAssociatedWebContents, tab-switch behavior, and all prompt pure virtuals.
- components/permissions/resolvers/permission_prompt_options.h:26–41: geolocation accuracy options versus monostate. Prototype deliberately does not grant geolocation with missing options.
- chrome/browser/ui/views/permissions/permission_prompt_bubble_base_view.cc:314–335: decision dispatch and GEOLOCATION_WITH_OPTIONS assertion; :347–360: temporary-grant eligibility predicate.
- components/permissions/permission_request_manager.cc:816–860: Dismiss/Ignore cancel requests, without granting; :2170–2195: tab switch deletes prompt while preserving pending request for the selected behavior.
- components/permissions/permission_request_manager_unittest.cc:360 onward: existing ForgetRequestsOnPageNavigation assertion sequence inspected. Android TwoRequestsTabSwitch test is not evidence for this desktop sheet.
- components/permissions/permission_uma_constants.h:246–247: CUSTOM_MODAL_DIALOG disposition.
- ui/gfx/native_ui_types.h:169: actual NSWindow extraction.

Verification: API/source crosscheck and git diff --check. No tests added or executed, no build or runtime performed. Root must add the GN sources and native-host-specific permission factory hook before runtime. Required acceptance: allow/block/dismiss/allow-once completion, cancellation during navigation and close, tab switch/re-show, competing sheets, quiet suppression, forged frame origins, mixed camera/microphone request, and repeated clicks. Native sheet accessibility, localization, bounds reporting and inactive-page handling remain unverified; GetViewBoundsInScreen currently explicitly returns no optional bounds.
