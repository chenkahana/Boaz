#import <AppKit/AppKit.h>
#include "extension_popup.h"
#include <algorithm>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/javascript_dialogs/app_modal_dialog_queue.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/common/extension.h"
#include "ui/base/base_window.h"

namespace boaz {
namespace {
void CheckUI() {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK([NSThread isMainThread]);
}
void Fail(ShowPopupCallback callback) {
  if (callback) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(callback), nullptr));
}
}  // namespace

class NativeExtensionPopup::Impl final
    : public extensions::ExtensionView,
      public content::WebContentsObserver,
      public extensions::ExtensionRegistryObserver,
      public extensions::SecurityDialogTracker::Observer {
 public:
  class PageObserver final : public content::WebContentsObserver {
   public:
    PageObserver(content::WebContents* page, base::WeakPtr<Impl> popup)
        : content::WebContentsObserver(page), popup_(popup) {}
    void DidStartNavigation(content::NavigationHandle* navigation) override {
      if (navigation->IsInPrimaryMainFrame() && popup_) popup_->Close();
    }
    void WebContentsDestroyed() override { if (popup_) popup_->Close(); }
   private:
    base::WeakPtr<Impl> popup_;
  };

  Impl(std::unique_ptr<extensions::ExtensionViewHost> host,
       BrowserWindowInterface* browser, NSView* anchor, gfx::Rect rect,
       ShowPopupCallback callback)
      : content::WebContentsObserver(host->host_contents()),
        host_(std::move(host)), browser_(browser->GetWeakPtr()),
        callback_(std::move(callback)), extension_id_(host_->extension()->id()) {
    parent_ = anchor.window;
    NSRect local = NSMakeRect(rect.x(), rect.y(), rect.width(), rect.height());
    anchor_screen_ = [parent_ convertRectToScreen:[anchor convertRect:local toView:nil]];
    panel_ = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 25, 25)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    panel_.releasedWhenClosed = NO;
    NSString* extension_name = base::SysUTF8ToNSString(host_->extension()->name());
    panel_.title = extension_name.length ? extension_name : @"Extension";
    panel_.accessibilityLabel = panel_.title;
    panel_.hidesOnDeactivate = NO;
    panel_.animationBehavior = NSWindowAnimationBehaviorNone;
    NSView* native = host_->host_contents()->GetNativeView().GetNativeNSView();
    [panel_.contentView addSubview:native];
    native.frame = panel_.contentView.bounds;
    native.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    host_->set_view(this);
    auto weak = weak_.GetWeakPtr();
    page_ = std::make_unique<PageObserver>(
        browser->GetTabStripModel()->GetActiveWebContents(), weak);
    active_changed_ = browser->RegisterActiveTabDidChange(base::BindRepeating(
        [](base::WeakPtr<Impl> popup, BrowserWindowInterface*) {
          if (popup) popup->Close();
        }, weak));
    browser_closed_ = browser->RegisterBrowserDidClose(base::BindRepeating(
        [](base::WeakPtr<Impl> popup, BrowserWindowInterface*) {
          if (popup) popup->Close();
        }, weak));
    registry_.Observe(extensions::ExtensionRegistry::Get(host_->browser_context()));
    security_.Observe(extensions::SecurityDialogTracker::GetInstance());
    notifications_ = [[NSMutableArray alloc] init];
    auto observe = [&](NSNotificationName name, id object) {
      id token = [[NSNotificationCenter defaultCenter] addObserverForName:name
          object:object queue:[NSOperationQueue mainQueue]
          usingBlock:^(NSNotification*) { if (weak) weak->Close(); }];
      [notifications_ addObject:token];
    };
    observe(NSWindowWillCloseNotification, parent_);
    observe(NSWindowWillMoveNotification, parent_);
    observe(NSWindowDidResizeNotification, parent_);
    observe(NSWindowWillMiniaturizeNotification, parent_);
    observe(NSWindowWillBeginSheetNotification, parent_);
    observe(NSWindowWillBeginSheetNotification, panel_);
    observe(NSWindowDidResignKeyNotification, panel_);
    observe(NSApplicationDidResignActiveNotification, NSApp);
    host_->SetCloseHandler(base::BindOnce([](base::WeakPtr<Impl> popup,
                                           extensions::ExtensionHost*) {
      if (popup) popup->Close();
    }, weak));
  }
  ~Impl() override {
    CheckUI();
    Close();
    weak_.InvalidateWeakPtrs();
    host_.reset();
  }
  void Start() {
    load_timeout_.Start(FROM_HERE, base::Seconds(10),
        base::BindOnce(&Impl::Close, weak_.GetWeakPtr()));
    auto weak = weak_.GetWeakPtr();
    host_->host_contents()->WasHidden();
    if (!weak || !CanPresent()) return;
    host_->CreateRendererSoon();
    if (!weak || !CanPresent()) return;
    if (host_->has_loaded_once()) OnLoaded();
  }
  void Complete() {
    if (!callback_) return;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](base::WeakPtr<Impl> popup, ShowPopupCallback callback) {
          std::move(callback).Run(popup && popup->showing_ && !popup->closed_
                                    ? popup->host_.get() : nullptr);
        }, weak_.GetWeakPtr(), std::move(callback_)));
  }
  void Close() {
    CheckUI();
    if (closed_) return;
    closed_ = true;
    load_timeout_.Stop();
    showing_ = false;
    Complete();
    for (id token in notifications_) [[NSNotificationCenter defaultCenter] removeObserver:token];
    [notifications_ removeAllObjects];
    active_changed_ = {};
    browser_closed_ = {};
    registry_.Reset();
    security_.Reset();
    page_.reset();
    Observe(nullptr);
    if (host_) {
      host_->host_contents()->WasHidden();
      [host_->host_contents()->GetNativeView().GetNativeNSView() removeFromSuperview];
      // Do not destroy a host from within one of its own callbacks.
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
          base::BindOnce([](base::WeakPtr<Impl> popup) {
            if (popup) popup->host_.reset();
          }, weak_.GetWeakPtr()));
    }
    [parent_ removeChildWindow:panel_];
    [panel_ orderOut:nil];
    [panel_ close];
  }
  bool IsShowing() const { return showing_ && !closed_; }
  gfx::NativeView GetNativeView() override {
    return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView();
  }
  void ResizeDueToAutoResize(content::WebContents*, const gfx::Size& size) override {
    if (closed_) return;
    NSSize next = NSMakeSize(std::clamp(size.width(), 25, 800),
                            std::clamp(size.height(), 25, 600));
    NSRect frame = [panel_ frameRectForContentRect:NSMakeRect(0, 0, next.width, next.height)];
    NSRect screen = parent_.screen.visibleFrame;
    frame.origin.x = std::clamp(NSMinX(anchor_screen_), NSMinX(screen),
                               std::max(NSMinX(screen), NSMaxX(screen) - frame.size.width));
    frame.origin.y = std::clamp(NSMinY(anchor_screen_) - frame.size.height,
                               NSMinY(screen), std::max(NSMinY(screen), NSMaxY(screen) - frame.size.height));
    [panel_ setFrame:frame display:showing_];
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (closed_ || frame->GetParent()) return;
    if (auto* view = frame->GetView())
      view->EnableAutoResize(extensions::kExtensionPopupMinSize,
                             extensions::kExtensionPopupMaxSize);
  }
  bool HandleKeyboardEvent(content::WebContents*, const input::NativeWebKeyboardEvent& event) override {
    CheckUI();
    if (event.skip_if_unhandled || !event.os_event.Get()) return false;
    NSEvent* native_event = event.os_event.Get();
    if (native_event.type != NSEventTypeKeyDown) return false;
    if (native_event.keyCode == 53) { Close(); return true; }
    return [NSApp.mainMenu performKeyEquivalent:native_event];
  }
  // Experimental host rejects JS dialogs; native dialog parity remains gated.
  // Requires the root-owned ExtensionView/ExtensionViewHost suppression patch.
  bool ShouldSuppressDialogs() const override { return true; }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (showing_ && navigation->IsInPrimaryMainFrame()) Close();
  }
  bool CanPresent() {
    if (closed_) return false;
    if (!host_ || !browser_ || !parent_) { Close(); return false; }
    return true;
  }
  void OnLoaded() override {
    if (!CanPresent() || showing_) return;
    load_timeout_.Stop();
    if (!browser_ || parent_.attachedSheet || NSApp.modalWindow ||
        javascript_dialogs::AppModalDialogQueue::GetInstance()->HasActiveDialog() ||
        extensions::SecurityDialogTracker::GetInstance()->BrowserHasVisibleSecurityDialogs(browser_.get())) {
      Close(); return;
    }
    auto weak = weak_.GetWeakPtr();
    ResizeDueToAutoResize(nullptr, gfx::Size(panel_.contentView.bounds.size.width,
                                            panel_.contentView.bounds.size.height));
    if (!weak || !CanPresent()) return;
    [parent_ addChildWindow:panel_ ordered:NSWindowAbove];
    if (!weak || !CanPresent()) return;
    showing_ = true;
    [panel_ makeKeyAndOrderFront:nil];
    if (!weak || !CanPresent()) return;
    host_->host_contents()->WasShown();
    if (!weak || !CanPresent()) return;
    host_->host_contents()->Focus();
    if (!weak || !CanPresent()) return;
    Complete();
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override { Close(); }
  void WebContentsDestroyed() override { Close(); }
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (extension->id() == extension_id_) Close();
  }
  void OnSecurityDialogAdded(views::Widget*) override { Close(); }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_.Reset();
    Close();
  }
 private:
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  ShowPopupCallback callback_;
  std::string extension_id_;
  NSPanel* __strong panel_;
  NSWindow* __weak parent_;
  NSMutableArray* __strong notifications_;
  NSRect anchor_screen_;
  bool closed_ = false;
  bool showing_ = false;
  std::unique_ptr<PageObserver> page_;
  base::CallbackListSubscription active_changed_;
  base::CallbackListSubscription browser_closed_;
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver> registry_{this};
  base::ScopedObservation<extensions::SecurityDialogTracker, extensions::SecurityDialogTracker::Observer> security_{this};
  base::OneShotTimer load_timeout_;
  base::WeakPtrFactory<Impl> weak_{this};
};

std::unique_ptr<NativeExtensionPopup> NativeExtensionPopup::Create(
    std::unique_ptr<extensions::ExtensionViewHost> host,
    BrowserWindowInterface* browser, void* anchor_nsview, gfx::Rect rect,
    PopupShowAction action, ShowPopupCallback callback) {
  CheckUI();
  NSView* anchor = (__bridge NSView*)anchor_nsview;
  if (!host || !browser || !anchor || ![anchor isKindOfClass:[NSView class]] ||
      !browser->GetWindow() || !browser->GetTabStripModel()->GetActiveWebContents() ||
      anchor.window != browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() ||
      !anchor.window || rect.IsEmpty() || action != PopupShowAction::kShow ||
      anchor.window.attachedSheet || NSApp.modalWindow ||
      javascript_dialogs::AppModalDialogQueue::GetInstance()->HasActiveDialog() ||
      extensions::SecurityDialogTracker::GetInstance()->BrowserHasVisibleSecurityDialogs(browser)) {
    Fail(std::move(callback));
    return nullptr;
  }
  auto impl = std::make_unique<Impl>(std::move(host), browser, anchor, rect, std::move(callback));
  auto result = std::unique_ptr<NativeExtensionPopup>(new NativeExtensionPopup(std::move(impl)));
  result->impl_->Start();
  return result;
}
NativeExtensionPopup::NativeExtensionPopup(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}
NativeExtensionPopup::~NativeExtensionPopup() = default;
void NativeExtensionPopup::Close() { impl_->Close(); }
bool NativeExtensionPopup::IsShowing() const { CheckUI(); return impl_->IsShowing(); }
gfx::NativeView NativeExtensionPopup::GetNativeView() const { CheckUI(); return impl_->GetNativeView(); }
}  // namespace boaz
