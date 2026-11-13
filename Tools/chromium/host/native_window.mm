#import <AppKit/AppKit.h>

#include "native_window.h"
#include "native_location_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/observer_list.h"
#include "base/strings/utf_string_conversions.h"
#include "base/timer/timer.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/themes/theme_service_factory.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"

namespace boaz {
namespace {
void Main() { CHECK([NSThread isMainThread]); }
void Unsupported(const char* feature) { LOG(WARNING) << "Boaz native host unavailable: " << feature; }

class NativeNotice final : public ExclusiveAccessBubble {
 public:
  NativeNotice(const ExclusiveAccessBubbleParams& params,
      base::RepeatingCallback<void(const std::string&, bool)> display,
      ExclusiveAccessBubbleHideCallback callback)
      : ExclusiveAccessBubble(params), display_(std::move(display)), callback_(std::move(callback)) {
    ShowAndStartTimers();
  }
  ~NativeNotice() override {
    if (visible_) display_.Run("", false);
    if (callback_) std::move(callback_).Run(ExclusiveAccessBubbleHideReason::kInterrupted);
  }
  bool visible() const { return visible_; }
  void OnFullscreenTransitionComplete() { ShowAndStartTimers(); }
 private:
  void Show() override {
    auto text = exclusive_access_bubble::GetInstructionTextForType(params_.type, u"Esc",
        params_.origin.opaque() ? std::nullopt : std::optional(base::UTF8ToUTF16(params_.origin.Serialize())), params_.has_download, false);
    visible_ = true;
    display_.Run(base::UTF16ToUTF8(text), true);
  }
  void Hide() override {
    visible_ = false;
    display_.Run("", false);
    if (callback_) std::move(callback_).Run(ExclusiveAccessBubbleHideReason::kTimeout);
  }
  base::RepeatingCallback<void(const std::string&, bool)> display_;
  ExclusiveAccessBubbleHideCallback callback_;
  bool visible_ = false;
};

class NativeWindow final : public BrowserWindow,
                           public ExclusiveAccessContext,
                           public web_modal::WebContentsModalDialogHost {
 public:
  NativeWindow(BrowserWindowInterface* browser, NSWindow* window,
               const NativeWindowServices& services)
      : browser_(browser), window_(window), services_(services),
        restored_(gfx::ScreenRectFromNSRect(window.frame)) {
    Main();
    CHECK(browser_ && window_);
    CHECK(services_.request_close && services_.content_view && services_.address_field && services_.focus_address &&
          services_.focus_toolbar && services_.handle_key && services_.exclusive_access_notice);
    location_bar_ = CreateNativeLocationBar(browser_, services_.address_field);
    restored_state_ = window_.zoomed ? ui::mojom::WindowShowState::kMaximized : ui::mojom::WindowShowState::kNormal;
    observers_ = [[NSMutableArray alloc] init];
    const base::WeakPtr<NativeWindow> weak = weak_factory_.GetWeakPtr();
    for (NSString* name in @[NSWindowDidResizeNotification, NSWindowDidMoveNotification,
                            NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification,
                            NSWindowDidResignKeyNotification, NSWindowWillEnterFullScreenNotification,
                            NSWindowWillMiniaturizeNotification, NSWindowDidDeminiaturizeNotification]) {
      id token = [[NSNotificationCenter defaultCenter] addObserverForName:name object:window_
          queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* notification) {
        if (weak) weak->OnWindowEvent(notification.name);
      }];
      [observers_ addObject:token];
    }
  }
  ~NativeWindow() override {
    Main();
    weak_factory_.InvalidateWeakPtrs();
    if (attention_) [NSApp cancelUserAttentionRequest:attention_];
    for (id token in observers_) [[NSNotificationCenter defaultCenter] removeObserver:token];
    notice_.reset();
    for (auto& observer : modal_observers_) observer.OnHostDestroying();
  }
  void DeleteBrowserWindow() override { Main(); delete this; }
  bool IsActive() const override { Main(); return window_.keyWindow; }
  bool IsMaximized() const override { Main(); return window_.zoomed; }
  bool IsMinimized() const override { Main(); return window_.miniaturized; }
  bool IsFullscreen() const override { Main(); return (window_.styleMask & NSWindowStyleMaskFullScreen) != 0; }
  gfx::NativeWindow GetNativeWindow() const override { Main(); return gfx::NativeWindow(window_); }
  gfx::Rect GetRestoredBounds() const override { Main(); return restored_; }
  ui::mojom::WindowShowState GetRestoredState() const override {
    Main();
    if (IsFullscreen() || IsMinimized()) return restored_state_;
    return IsMaximized() ? ui::mojom::WindowShowState::kMaximized : ui::mojom::WindowShowState::kNormal;
  }
  gfx::Rect GetBounds() const override { Main(); return gfx::ScreenRectFromNSRect(window_.frame); }
  void Show() override { Main(); [window_ makeKeyAndOrderFront:nil]; }
  void Hide() override { Main(); [window_ orderOut:nil]; }
  bool IsVisible() const override { Main(); return window_.visible; }
  void ShowInactive() override { Main(); [window_ orderFront:nil]; }
  void Close() override { Main(); services_.request_close.Run(); }
  void Activate() override { Main(); if (window_.miniaturized) [window_ deminiaturize:nil]; [window_ makeKeyAndOrderFront:nil]; }
  void Deactivate() override {
    Main();
    for (NSWindow* candidate in NSApp.orderedWindows) {
      if (candidate != window_ && candidate.visible && candidate.canBecomeKeyWindow) {
        [candidate makeKeyWindow]; return;
      }
    }
    [NSApp deactivate];
  }
  void Maximize() override { Main(); if (!window_.zoomed) [window_ zoom:nil]; }
  void Minimize() override { Main(); restored_state_ = GetWindowShowState(); [window_ miniaturize:nil]; }
  void Restore() override {
    Main();
    if (IsFullscreen()) [window_ toggleFullScreen:nil];
    else if (window_.miniaturized) [window_ deminiaturize:nil];
    else if (window_.zoomed) [window_ zoom:nil];
  }
  void SetBounds(const gfx::Rect& bounds) override { Main(); [window_ setFrame:gfx::ScreenRectToNSRect(bounds) display:YES]; }
  void FlashFrame(bool flash) override {
    Main();
    if (attention_) { [NSApp cancelUserAttentionRequest:attention_]; attention_ = 0; }
    if (flash) attention_ = [NSApp requestUserAttention:NSInformationalRequest];
  }
  ui::ZOrderLevel GetZOrderLevel() const override { Main(); return window_.level > NSNormalWindowLevel ? ui::ZOrderLevel::kFloatingWindow : ui::ZOrderLevel::kNormal; }
  void SetZOrderLevel(ui::ZOrderLevel level) override { Main(); window_.level = level == ui::ZOrderLevel::kNormal ? NSNormalWindowLevel : NSFloatingWindowLevel; }
  bool IsOnCurrentWorkspace() const override { Main(); return window_.onActiveSpace; }
  bool IsVisibleOnScreen() const override { Main(); return window_.visible && (window_.occlusionState & NSWindowOcclusionStateVisible); }
  void SetTopControlsShownRatio(content::WebContents*, float) override {}
  bool DoBrowserControlsShrinkRendererSize(const content::WebContents*) const override { return false; }
  ui::NativeTheme* GetNativeTheme() override { Main(); return ui::NativeTheme::GetInstanceForNativeUi(); }
  const ui::ThemeProvider* GetThemeProvider() const override { Main(); return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile()); }
  const ui::ColorProvider* GetColorProvider() const override { Main(); return ThemeServiceFactory::GetForProfile(browser_->GetProfile())->GetColorProvider(); }
  int GetTopControlsHeight() const override { return 0; }
  void SetTopControlsGestureScrollInProgress(bool) override {}
  std::vector<StatusBubble*> GetStatusBubbles() override { return {}; }
  void UpdateTitleBar() override {
    Main(); auto* contents = Active();
    if (contents) { const auto title = contents->GetTitle(); window_.title = [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(title.data()) length:title.size()]; }
  }
  void UpdateLoadingAnimations(bool) override {}
  void OnActiveTabChanged(content::WebContents*, content::WebContents* contents, int, int) override {
    Main(); notice_.reset(); NotifyPositionRequiresUpdate();
    location_bar_->Update(contents);
    UpdateTitleBar(); if (contents && IsActive()) contents->Focus();
  }
  void OnTabDetached(content::WebContents*, bool) override { Main(); notice_.reset(); NotifyPositionRequiresUpdate(); }
  gfx::Size GetContentsSize() const override { Main(); NSView* view = Content(); return gfx::Size(view.bounds.size.width, view.bounds.size.height); }
  void SetContentsSize(const gfx::Size& size) override {
    Main(); const gfx::Size current = GetContentsSize(); NSRect frame = window_.frame;
    frame.size.width += size.width() - current.width(); frame.size.height += size.height() - current.height();
    frame.origin.y -= size.height() - current.height(); [window_ setFrame:frame display:YES];
  }
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override { return nullptr; }
  LocationBar* GetLocationBar() const override { return location_bar_.get(); }
  ui::AcceleratorProvider* GetAcceleratorProvider() override { return nullptr; }
  PinnedToolbarActions* GetPinnedToolbarActions() override { return nullptr; }
  void SetFocusToLocationBar(bool user) override { Main(); location_bar_->FocusLocation(user, false); }
  void UpdateReloadStopState(bool, bool) override {}
  void UpdateToolbar(content::WebContents* contents) override { Main(); location_bar_->Update(contents); }
  bool UpdateToolbarSecurityState() override { return false; }
  void UpdateCustomTabBarVisibility(bool, bool) override {}
  void ResetToolbarTabState(content::WebContents* contents) override { Main(); location_bar_->ResetTabState(contents); }
  void FocusToolbar() override { Main(); services_.focus_toolbar.Run(); }
  void ToolbarSizeChanged(bool) override { Main(); NotifyPositionRequiresUpdate(); }
  void TabDraggingStatusChanged(bool) override {}
  void LinkOpeningFromGesture(WindowOpenDisposition) override {}
  void FocusAppMenu() override { Unsupported("app menu focus"); }
  bool IsTabStripEditable() const override { return false; }
  void DisableTabStripEditingForTesting() override {}
  bool IsToolbarVisible() const override { return false; }
  bool IsToolbarShowing() const override { return false; }
  bool IsLocationBarVisible() const override { return false; }
  void ShowUpdateChromeDialog() override { Unsupported("Chrome updater UI"); }
  void ShowIntentPickerBubble(std::vector<apps::IntentPickerAppInfo>, bool, bool,
      apps::IntentPickerBubbleType, const std::optional<url::Origin>&,
      IntentPickerResponse callback) override {
    Main(); std::move(callback).Run("", apps::PickerEntryType::kUnknown,
        apps::IntentPickerCloseReason::ERROR_BEFORE_PICKER, false);
  }
  void ShowBookmarkBubble(const GURL&, bool) override { Unsupported("bookmark UI"); }
  ShowTranslateBubbleResult ShowTranslateBubble(content::WebContents*, translate::TranslateStep,
      const std::string&, const std::string&, translate::TranslateErrors, bool) override {
    return ShowTranslateBubbleResult::kBrowserWindowNotValid;
  }
  DownloadBubbleUIController* GetDownloadBubbleUIController() override { return nullptr; }
  void ConfirmBrowserCloseWithPendingDownloads(int, DownloadCloseType, base::OnceCallback<void(bool)> callback) override {
    Main(); std::move(callback).Run(false);
  }
  void ShowAppMenu() override { Unsupported("app menu"); }
  void PreHandleDragUpdate(const content::DropData&, const gfx::PointF&) override {}
  void PreHandleDragExit() override {}
  void HandleDragEnded() override {}
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override {
    Main(); OnExclusiveAccessUserInput();
    return services_.handle_key.Run(event) ? content::KeyboardEventProcessingResult::HANDLED
                                        : content::KeyboardEventProcessingResult::NOT_HANDLED;
  }
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent&) override { return false; }
  std::unique_ptr<FindBar> CreateFindBar() override { Unsupported("find bar"); return nullptr; }
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost() override { return this; }
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(content::WebContents* contents) override {
    Main();
    auto* tabs = browser_->GetTabStripModel();
    return contents && tabs && tabs->GetIndexOfWebContents(contents) != TabStripModel::kNoTab
        ? this : nullptr;
  }
  void ShowAvatarBubbleFromAvatarButton(bool) override { Unsupported("avatar UI"); }
  void ShowHatsDialog(const std::string&, const std::optional<std::string>&,
      const std::optional<uint64_t>, base::OnceClosure, base::OnceClosure failure,
      const SurveyBitsData&, const SurveyStringData&) override { if (failure) std::move(failure).Run(); }
  ExclusiveAccessContext* GetExclusiveAccessContext() override { return this; }
  std::string GetWorkspace() const override { return {}; }
  bool IsVisibleOnAllWorkspaces() const override { Main(); return window_.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces; }
  void ShowEmojiPanel() override { Main(); [NSApp orderFrontCharacterPalette:nil]; }
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(content::RenderFrameHost*, content::EyeDropperListener*) override { Unsupported("eye dropper"); return nullptr; }
  void ShowCaretBrowsingDialog() override { Unsupported("caret browsing dialog"); }
  void CreateTabSearchBubble() override { Unsupported("tab search"); }
  void CloseTabSearchBubble() override {}
  void ShowIncognitoClearBrowsingDataDialog() override { Unsupported("private data dialog"); }
  void ShowIncognitoHistoryDisclaimerDialog() override { Unsupported("private history dialog"); }
  bool IsUnframedModeEnabled() const override { return false; }
  bool GetCanResize() override { Main(); return window_.styleMask & NSWindowStyleMaskResizable; }
  ui::mojom::WindowShowState GetWindowShowState() const override {
    if (IsFullscreen()) return ui::mojom::WindowShowState::kFullscreen;
    if (IsMinimized()) return ui::mojom::WindowShowState::kMinimized;
    if (IsMaximized()) return ui::mojom::WindowShowState::kMaximized;
    return ui::mojom::WindowShowState::kNormal;
  }
  void ShowChromeLabs() override { Unsupported("Chrome Labs"); }
  BrowserView* AsBrowserView() override { return nullptr; }

  Profile* GetProfile() override { Main(); return browser_->GetProfile(); }
  void EnterFullscreen(const url::Origin& origin, ExclusiveAccessBubbleType type, FullscreenTabParams params) override {
    Main();
    if (params.display_id != display::kInvalidDisplayId) Unsupported("fullscreen display targeting");
    UpdateExclusiveAccessBubble({.origin = origin, .type = type}, {});
    if (!IsFullscreen()) [window_ toggleFullScreen:nil];
  }
  void UpdateUIForTabFullscreen() override { Main(); NotifyPositionRequiresUpdate(); }
  void ExitFullscreen() override { Main(); notice_.reset(); if (IsFullscreen()) [window_ toggleFullScreen:nil]; }
  void UpdateExclusiveAccessBubble(const ExclusiveAccessBubbleParams& params,
                                  ExclusiveAccessBubbleHideCallback callback) override {
    Main(); notice_.reset();
    if (params.type == EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE) {
      if (callback) std::move(callback).Run(ExclusiveAccessBubbleHideReason::kNotShown);
      return;
    }
    notice_ = std::make_unique<NativeNotice>(params, services_.exclusive_access_notice, std::move(callback));
  }
  bool IsExclusiveAccessBubbleDisplayed() const override { Main(); return notice_ && notice_->visible(); }
  void OnExclusiveAccessUserInput() override { Main(); if (notice_) notice_->OnUserInput(); }
  content::WebContents* GetWebContentsForExclusiveAccess() override { Main(); return Active(); }
  bool CanUserEnterFullscreen() const override { Main(); return window_.styleMask & NSWindowStyleMaskResizable; }
  bool CanUserExitFullscreen() const override { return true; }

  gfx::NativeView GetHostView() const override { Main(); return gfx::NativeView(Content()); }
  gfx::Point GetDialogPosition(const gfx::Size& size) override { const auto bounds = GetContentsSize(); return gfx::Point(std::max(0, (bounds.width() - size.width()) / 2), std::max(0, (bounds.height() - size.height()) / 2)); }
  gfx::Size GetMaximumDialogSize() override { return GetContentsSize(); }
  bool ShouldActivateDialog() const override { return IsActive(); }
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override { Main(); modal_observers_.AddObserver(observer); }
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override { Main(); modal_observers_.RemoveObserver(observer); }
  void NotifyPositionRequiresUpdate() override { Main(); for (auto& observer : modal_observers_) observer.OnPositionRequiresUpdate(); }
 private:
  NSView* Content() const {
    NSView* view = (__bridge NSView*)services_.content_view.Run();
    CHECK(view && view.window == window_); return view;
  }
  content::WebContents* Active() const {
    auto* tab = browser_->GetActiveTabInterface(); return tab ? tab->GetContents() : nullptr;
  }
  void OnWindowEvent(NSString* name) {
    Main();
    if ([name isEqualToString:NSWindowWillEnterFullScreenNotification] ||
        [name isEqualToString:NSWindowWillMiniaturizeNotification]) {
      restored_state_ = GetWindowShowState();
    }
    if ([name isEqualToString:NSWindowDidResignKeyNotification]) notice_.reset();
    if ([name isEqualToString:NSWindowDidEnterFullScreenNotification] || [name isEqualToString:NSWindowDidExitFullScreenNotification]) {
      if (auto* manager = ExclusiveAccessManager::From(browser_)) manager->fullscreen_controller()->WindowFullscreenStateChanged();
      if ([name isEqualToString:NSWindowDidEnterFullScreenNotification] && notice_) notice_->OnFullscreenTransitionComplete();
    }
    if (!IsFullscreen() && !IsMaximized() && !IsMinimized()) restored_ = GetBounds();
    NotifyPositionRequiresUpdate();
  }
  BrowserWindowInterface* browser_;
  NSWindow* __strong window_;
  NSMutableArray* __strong observers_;
  NativeWindowServices services_;
  gfx::Rect restored_;
  ui::mojom::WindowShowState restored_state_ = ui::mojom::WindowShowState::kNormal;
  NSInteger attention_ = 0;
  std::unique_ptr<NativeNotice> notice_;
  NativeLocationBarPtr location_bar_;
  base::ObserverList<web_modal::ModalDialogHostObserver> modal_observers_;
  base::WeakPtrFactory<NativeWindow> weak_factory_{this};
};
}  // namespace

std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateNativeBrowserWindow(
    BrowserWindowInterface* browser, void* nswindow, const NativeWindowServices& services) {
  Main();
  return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
      new NativeWindow(browser, (__bridge NSWindow*)nswindow, services));
}
}  // namespace boaz
