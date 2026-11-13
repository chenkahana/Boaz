# S3: trusted password scripts — source feasibility

Verdict: **not passed; runtime proof required**. No app launches, password access, implementation changes, or tests were performed for this report. Inspection uses CEF `156.0.28+g57389f0`, commit `57389f04a61ab0e9603d9f96602843d0e08bb11c`, Chromium `156.0.8078.88`. The integration starting point was `2c8d41b`; this worker's source branch contains the equivalent spike commits through `e19416a`.

## Deterministic evidence

Existing `Apps/Browser/PasswordAutofill.swift` installs a document-start, main-frame-only script in `WKContentWorld.world(name: "boaz-passwords")`. Messages use WebKit's frame security origin, not a claimed origin in the message body. Filling requires local authentication and executes in that same isolated world. Private browsing permits filling but disables saving. Preserve these behaviors.

CEF's public `CefFrame::ExecuteJavaScript` and `GetV8Context` have no isolated-world selector. `CefRenderProcessHandler::OnContextCreated` exposes browser, frame, and context but no world identity. The pinned [renderer observer](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/renderer/render_frame_observer.cc#L129) receives `world_id` and does not pass it to the client callback. Injecting a privileged `CefV8Handler` in every callback would therefore expose it to an untrusted page context. No public API route to create and positively identify a private password world was established in this inspection.

V8 handles are confined to their creation thread; use `CefV8Context::GetTaskRunner` for that thread. `OnContextReleased` forbids retaining context references afterward. Browser and renderer `OnProcessMessageReceived` callbacks supply a CEF browser/frame and source process, but do not identify the JavaScript world. `CefFrame::GetIdentifier` identifies a frame, not a document/navigation generation. `GetURL` is not an authoritative security origin for inherited or opaque origins. `SendProcessMessage` explicitly does not guarantee delivery during navigation, close, or crashes; an acknowledgement is required when completion matters. These APIs alone do not provide the missing isolated-world boundary.

Chrome extension content scripts execute in isolated worlds and communicate with their extension worker through runtime messaging. They share the DOM with the page, so isolation does not make filled DOM values secret from that page. [Content-script documentation](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts).

The pinned [runtime schema](https://github.com/chromium/chromium/blob/156.0.8078.88/extensions/common/api/runtime.json) supplies `MessageSender.id`, `tab`, `frameId`, `url`, `origin`, `documentId`, and `documentLifecycle`. `origin` may differ from URL or be opaque; lifecycle is a snapshot and can change after a port opens. The pinned [tabs schema](https://github.com/chromium/chromium/blob/156.0.8078.88/chrome/common/extensions/api/tabs.json) permits `tabs.sendMessage` and `tabs.connect` to target a specific `documentId`.

Native messaging requires a registered host, the extension's `nativeMessaging` permission, and an exact `allowed_origins` extension-origin allowlist. Chrome launches the host with the calling extension origin; the protocol uses length-prefixed JSON over standard input/output. A content script cannot call the native API directly; its trusted worker must mediate. [Native-messaging documentation](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging). Official web documentation was consulted because the binary distribution does not include these extension contracts; document metadata was additionally checked against the pinned Chromium schemas.

## Proposed contract — judgment, not accepted architecture

Use a packaged, fixed-ID Boaz MV3 extension with a document-start **ISOLATED** content script, initially main-frame only. Keep page-facing bridges, `window.postMessage`, externally connectable entry points, and main-world secrets out of the password channel. The worker accepts only its own internal sender, main frame, an allowed non-opaque origin, a known visible Boaz tab, and a current document. Extract identity from browser-provided `sender`, never message-body fields. Reject missing identity instead of degrading to URL-only validation.

The native side must bind each connection to the correct engine profile and page registry. Extension ID alone does not identify the profile. The native host's asserted origin and allowlist are extension boundaries, not authentication against arbitrary local processes; a connection from the helper to Boaz needs authenticated local IPC and a verified helper identity. Keep Keychain operations and user authentication in Boaz. Do not let a worker-provided tab number select a profile or disclose a password without this binding.

Track an operation by profile, Boaz page ID, extension tab ID, frame ID, document UUID, canonical origin, and a single-use operation ID. Authenticate locally, then revalidate the active document and origin before releasing a fill response. Target the exact document with `tabs.sendMessage(..., {documentId})`; the isolated recipient checks its active operation before touching the DOM. If navigation removes that document, fail closed. A content script cannot forge the worker's browser-supplied sender metadata, but its DOM observations remain untrusted page input.

Cancel pending operations on invalidating navigation, close, renderer failure, extension unload, port disconnect, or worker restart. A stale worker port is insufficient evidence that a document is active; account for BFCache/prerender lifecycle and revalidate at delivery. Timeout/ACK handling completes each native operation once; duplicate replies are ignored. Do not persist passwords in worker storage or logs. Keep transient password exposure bounded to the authenticated fill/save flow.

Save requests require the same origin/document validation, the existing user confirmation, and the private-profile no-save rule. Isolated execution cannot establish that a form submission was honest: the website controls its DOM and synthetic events. Do not treat script-reported submission as permission to save silently.

## Blocking evidence to obtain

- Demonstrate packaged extension installation and isolated content-script execution on actual visible Boaz tabs, including worker restart and relaunch.
- Verify CEF's exact native-host registration/search path and launch behavior; Chrome's standard host path must not be assumed for CEF.
- Prove authenticated native IPC, connection-to-profile binding, tab/page mapping, and private-context separation.
- Exercise page attempts to call/spoof the bridge, modified DOM, opaque origins, cross-origin frames, same-frame navigation during authentication, BFCache, crash, close, duplicate replies, and disconnect. Use disposable credentials only.
- Verify fill and save behavior, main-frame restriction, private no-save, and absence of secret-bearing logs.

Until these pass, password migration is blocked. A custom CEF isolated-world API could be a separate architecture option, but this report neither specifies nor authorizes that patch. The extension route depends on S2 and cannot be accepted solely from headers or Chrome documentation.
