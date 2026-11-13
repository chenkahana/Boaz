#import <AppKit/AppKit.h>
#include "native_location_bar.h"

#include <algorithm>
#include <optional>
#include "base/check.h"
#include "base/memory/weak_ptr.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/supports_user_data.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "components/omnibox/browser/location_bar_model.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/gfx/mac/coordinate_conversion.h"

namespace boaz {
namespace {
const char kAddressStateKey = 0;
struct AddressState : base::SupportsUserData::Data {
  std::u16string text;
  std::string committed_url;
  NSRange selection = NSMakeRange(0, 0);
};

class NativeLocationBar final : public LocationBar,
                                public content::WebContentsObserver {
 public:
  NativeLocationBar(BrowserWindowInterface* browser,
                    base::RepeatingCallback<void*()> provider)
      : LocationBar(nullptr), browser_(browser), provider_(std::move(provider)) {
    Main();
    CHECK(browser_ && provider_);
    NSTextField* field = Field();
    observers_ = [NSMutableArray new];
    auto weak = weak_.GetWeakPtr();
    for (NSString* name in @[NSControlTextDidBeginEditingNotification,
                            NSControlTextDidEndEditingNotification,
                            NSControlTextDidChangeNotification]) {
      id token = [[NSNotificationCenter defaultCenter] addObserverForName:name object:field
          queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* notification) {
        if (!weak) return;
        if ([notification.name isEqualToString:NSControlTextDidChangeNotification]) weak->OnChanged();
        else weak->NotifyFocusChanged();
      }];
      [observers_ addObject:token];
    }
  }
  ~NativeLocationBar() override {
    Main(); weak_.InvalidateWeakPtrs();
    for (id token in observers_) [[NSNotificationCenter defaultCenter] removeObserver:token];
  }
  void FocusLocation(bool user, bool clear_if_failed) override {
    NSTextField* field = Field();
    if (!IsDrawn() || !field.enabled || !field.editable ||
        ![field.window makeFirstResponder:field]) {
      if (clear_if_failed) [field.window makeFirstResponder:nil];
      return;
    }
    if (user) [field selectText:nil];
    NotifyFocusChanged();
  }
  void FocusSearch() override { FocusLocation(true, false); }
  void UpdateFocusBehavior(bool visible) override { Field().enabled = visible; }
  void UpdateContentSettingsIcons() override {}
  void SaveStateToContents(content::WebContents* contents) override {
    Main(); if (!contents) return;
    auto state = std::make_unique<AddressState>();
    state->text = base::SysNSStringToUTF16(Field().stringValue);
    state->committed_url = contents->GetLastCommittedURL().spec();
    NSText* editor = Field().currentEditor;
    state->selection = editor ? editor.selectedRange : selection_;
    contents->SetUserData(&kAddressStateKey, std::move(state));
  }
  void Revert() override {
    Main(); auto* contents = GetWebContents();
    if (contents) contents->RemoveUserData(&kAddressStateKey);
    SetText(contents ? base::UTF8ToUTF16(contents->GetLastCommittedURL().spec()) : std::u16string(), NSMakeRange(0, 0));
  }
  OmniboxView* GetOmniboxView() override { return nullptr; }
  OmniboxPopupView* GetOmniboxPopupView() override { return nullptr; }
  OmniboxController* GetOmniboxController() override { return nullptr; }
  bool ShouldCloseOmniboxPopup(ui::MouseEvent*) override { return false; }
  content::WebContents* GetWebContents() override {
    Main(); auto* tab = browser_->GetActiveTabInterface();
    return tab ? tab->GetContents() : nullptr;
  }
  LocationBarModel* GetLocationBarModel() override {
    Main(); auto* model = LocationBarModel::From(browser_); CHECK(model); return model;
  }
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor() override { return std::nullopt; }
  ChipController* GetChipController() override { return nullptr; }
  void AnnounceAlert(const std::u16string& message) override {
    NSAccessibilityPostNotificationWithUserInfo(Field(), NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey: base::SysUTF16ToNSString(message),
          NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
  }
  void OnChanged() override { SaveStateToContents(GetWebContents()); }
  void UpdateWithoutTabRestore() override { if (!IsFocusWithin()) Revert(); }
  ui::TrackedElement* GetAnchorOrNull() override { return nullptr; }
  BrowserWindowInterface* GetBrowser() override { return browser_; }
  Profile* GetProfile() override { return browser_->GetProfile(); }
  bool IsInitialized() const override { return Field().window != nil; }
  bool IsVisible() const override { return !Field().hidden; }
  bool IsDrawn() const override {
    NSTextField* field = Field();
    return !field.hiddenOrHasHiddenAncestor && !NSIsEmptyRect(field.visibleRect) &&
        field.window.visible && !field.window.miniaturized;
  }
  bool IsFullscreen() const override { return (Field().window.styleMask & NSWindowStyleMaskFullScreen) != 0; }
  bool IsEditingOrEmpty() const override { return IsFocusWithin() || Field().stringValue.length == 0; }
  bool IsMouseHovered() const override {
    NSTextField* field = Field();
    NSPoint point = [field convertPoint:field.window.mouseLocationOutsideOfEventStream fromView:nil];
    return IsDrawn() && NSPointInRect(point, field.bounds);
  }
  bool IsFocusWithin() const override {
    NSTextField* field = Field();
    return field.window.firstResponder == field ||
        (field.currentEditor && field.window.firstResponder == field.currentEditor);
  }
  void InvalidateLayout() override { Field().needsLayout = YES; NotifyBoundsChanged(); }
  gfx::Rect Bounds() const override {
    NSTextField* field = Field(); NSRect rect = field.frame;
    if (!field.superview.flipped) rect.origin.y = NSHeight(field.superview.bounds) - NSMaxY(rect);
    return gfx::Rect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
  }
  gfx::Rect BoundsInScreen() const override {
    NSTextField* field = Field();
    return gfx::ScreenRectFromNSRect([field.window convertRectToScreen:[field convertRect:field.bounds toView:nil]]);
  }
  gfx::Size MinimumSize() const override {
    NSSize size = Field().fittingSize; return gfx::Size(size.width, size.height);
  }
  gfx::Size PreferredSize() const override { return MinimumSize(); }
  void Update(content::WebContents* contents) override {
    Main();
    if (!contents) { UpdateWithoutTabRestore(); return; }
    if (contents == web_contents()) {
      if (!IsFocusWithin()) {
        auto* saved = static_cast<AddressState*>(contents->GetUserData(&kAddressStateKey));
        if (!saved || saved->committed_url != contents->GetLastCommittedURL().spec()) Revert();
      }
      return;
    }
    Observe(contents);
    auto* saved = static_cast<AddressState*>(contents->GetUserData(&kAddressStateKey));
    if (saved && saved->committed_url == contents->GetLastCommittedURL().spec())
      SetText(saved->text, saved->selection);
    else
      Revert();
  }
  void ResetTabState(content::WebContents* contents) override {
    Main(); if (contents) contents->RemoveUserData(&kAddressStateKey);
    if (contents == GetWebContents()) Revert();
  }
  bool HasSecurityStateChanged() override {
    auto security = GetLocationBarModel()->GetSecurityLevel();
    bool changed = last_security_ && *last_security_ != security;
    last_security_ = security;
    return changed;
  }
  LocationBarTesting* GetLocationBarForTesting() override { return nullptr; }
 private:
  static void Main() { CHECK([NSThread isMainThread]); }
  NSTextField* Field() const {
    Main(); NSTextField* field = (__bridge NSTextField*)provider_.Run();
    CHECK([field isKindOfClass:NSTextField.class] && field.window);
    return field;
  }
  void SetText(const std::u16string& text, NSRange selection) {
    NSTextField* field = Field(); field.stringValue = base::SysUTF16ToNSString(text);
    selection.location = std::min(selection.location, field.stringValue.length);
    selection.length = std::min(selection.length, field.stringValue.length - selection.location);
    selection_ = selection;
    if (NSText* editor = field.currentEditor) {
      editor.string = field.stringValue;
      editor.selectedRange = selection;
    }
  }
  raw_ptr<BrowserWindowInterface> browser_;
  base::RepeatingCallback<void*()> provider_;
  NSMutableArray* __strong observers_;
  NSRange selection_ = NSMakeRange(0, 0);
  std::optional<security_state::SecurityLevel> last_security_;
  base::WeakPtrFactory<NativeLocationBar> weak_{this};
};
}
void NativeLocationBarDeleter::operator()(LocationBar* bar) const {
  delete static_cast<NativeLocationBar*>(bar);
}
NativeLocationBarPtr CreateNativeLocationBar(
    BrowserWindowInterface* browser, base::RepeatingCallback<void*()> field) {
  return NativeLocationBarPtr(new NativeLocationBar(browser, std::move(field)));
}
}
