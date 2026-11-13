# Browser-side trusted execution

Status: implementation packet; not an S3 pass. GN integration and the dedicated ISOLATED_WORLD_ID_BOAZ reservation are applied. The coordinator compiled against Chromium 157 in guarded build log `20261113T114138.892688Z.log`. No renderer save-event bridge is implemented.

TrustedExecution observes one WebContents, captures only its primary main frame, and binds targets to a weak document, global frame ID, exact nonopaque browser-derived origin, browser context and local epoch. Caller must capture before authentication and pass that same target afterward; Execute revalidates it instead of capturing whichever page is now visible. Main-frame-only preserves the current password policy; subframe fill remains unsupported.

Execute accepts an internal trusted function expression and a serializable base::DictValue. This pinned Chromium uses DictValue, not the older Value::Dict spelling. JSON arguments are serialized twice and passed through JSON.parse, preserving data semantics rather than treating dictionary keys as object-literal syntax. Function source is trusted application code, never page input. Source UTF-16 storage and serialized argument JSON each have a 64 KiB limit. Serialization failure, invalid targets and a 64-operation limit complete asynchronously with explicit status.

Each operation owns a cancellable five-second OneShotTimer, released on completion or cancellation. Returned values must serialize to at most 64 KiB of JSON; unsupported or larger results complete with invalid-argument status and no result. This is a bounded password-operation channel, not an unrestricted page-text API. Normal results revalidate the entire target. A dropped Mojo callback reports renderer failure, rather than confusing it with a valid null result. Primary cross-document navigation start cancels the epoch, even if navigation later fails; same-document navigation preserves it. Renderer exit, relevant frame deletion, explicit Close, WebContents destruction and owner destruction cancel pending work. Each pending entry is removed before posting its client completion. Delayed results and timeouts cannot complete the removed operation again. No secrets, arguments or results are logged.

Close detaches observation and clears the browser-context pointer. Construction checks its non-null WebContents precondition before accessing the browser context. Close/destruction only posts completions; callers must bind their own lifetime safely. The shutdown coordinator must drain posted completions before releasing its UI task runner and callback owners. This class cannot guarantee completion after process termination or task-runner shutdown. Successful status means Chromium returned a JavaScript result, not that a password was filled; the trusted function must return a typed application result. The upstream API does not separately report JavaScript exceptions.

## Source verification

Pinned Chromium 157.0.8103.51:

- content/public/browser/render_frame_host.h:598–627: once-result callback, UI-thread delivery, isolated-world execution; :1162 weak document.
- content/browser/renderer_host/render_frame_host_impl.cc:3882–3893: UI-thread and reserved-world bounds checks.
- content/public/browser/weak_document_ptr.h:17–43: document invalidation.
- content/public/browser/document_user_data.h:40–58: BFCache/crash caveats; implementation additionally checks live/active frame and maintains cancellation epoch.
- content/public/browser/web_contents_observer.h:143,281,340,777: frame deletion, renderer loss, navigation start and close callbacks.
- mojo/public/cpp/bindings/callback_helpers.h:163–169: WrapCallbackWithDropHandler distinguishes response from callback destruction.
- base/json/json_writer.h:40–49: serialization failure for unsupported values/depth.

API/source crosscheck, diff whitespace verification and compilation passed. No new tests or runtime execution. Root must compile and verify hostile navigation, opaque origin, frame substitution, BFCache/crash, timeout, dropped and duplicate callbacks, callback-driven owner destruction and private-mode policy. Private fill/no-save and persistent save messages belong to the later document-bound Mojo service. Less-than-5-ms p50 is an unmeasured runtime target.

The separate `trusted-world.patch` reserves the Boaz ID inside the existing macOS-only enum section after AppleScript. Android numeric IDs remain unchanged. The official lite source archive omits the Java counterpart named by the header's lint comment; no replacement Java file is invented. The patch and coordinator are now installed through the guarded series. Runtime isolation, exact-document cancellation and latency acceptance remain pending.

The next prepared packet adds one-use document-token ownership and ABI 5 dispatch. Tokens and identity remain native; the renderer receives only the trusted function and serialized arguments. The bootstrap now accounts for accepted operations before shutdown notification. This integration is not installed over the active ABI 4 build and has not compiled yet. Authentication, actual password fill/save, isolated-world observation and latency remain runtime gates.

Queued-success delivery now revalidates the document again on the client-completion task. Navigation or renderer loss between the renderer reply and that task produces invalid-target without a result; close/destruction produces closed. The task owns the completion independently of the executor weak pointer, so shutdown still drains exactly one callback. This change is queued for the next host installation and compile; the running build retains its installed source. Runtime race acceptance remains pending.
