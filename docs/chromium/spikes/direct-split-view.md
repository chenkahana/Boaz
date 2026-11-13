# Native split-view packet

Status: model and native pane implementation prepared, not compiled or runtime accepted. The current full build remains ABI 4; the queued split/script integration is ABI 6.

Chromium's TabStripModel owns the split, ordering and focused tab. GetForegroundTabs returns one active page or both members of its split. Boaz publishes those real page handles and the separate active handle through its C interface. Native panes reuse the same retained WebContents views, with no reload or second browser window. Model changes refresh layout after callback unwinding.

The implementation validates tab ownership, lifecycle, profile, finite ratio, group/pin compatibility and stacked-layout availability before mutation. Existing conflicting splits are rejected. Creating a split focuses its first page. Divider changes preserve whichever pane was focused. Closing, replacement and before-unload cancellation retain the existing synchronous detach barriers.

## Visibility evidence

Pinned Chromium 157's WebContentsViewMac::GetNativeView returns the outer WebContentsViewCocoa. In `content/app_shim_remote_cocoa/web_contents_view_cocoa.mm`, native window attachment and hidden-state changes update visibility. Detached/hidden views become hidden; an occluded window becomes occluded, with delayed/coalesced occlusion handling. The route reaches WebContentsImpl::UpdateWebContentsVisibility, including frame-tree and accessibility visibility.

Therefore the native coordinator attaches/hides the outer views and does not routinely issue WasShown/WasHidden. A visible second pane must not be backgrounded merely because it lacks focus. Minimize, window occlusion and fullscreen transitions remain Chromium/AppKit visibility inputs. Native attachment is supported by source evidence, not yet proven by the running host.

## Outstanding acceptance

Compile the model and Swift packet, then verify two pages retain JavaScript/scroll state, both render and resize, divider movement retains focus, address/extension targeting follows the active pane, and actual extension tab/window IDs remain correct. Exercise close cancellation, replacement, renderer crash, window transfer, minimize/restore, VoiceOver and IME.

Content fullscreen still needs explicit sibling-pane suspension/restoration behavior; ordinary macOS window fullscreen is a separate case. Do not mark fullscreen parity passed merely because NSWindow enters fullscreen. Whole-window GetContentsSize assumptions also need runtime inspection against pane-specific renderer bounds. No new tests were added, and no runtime or performance result is claimed.
