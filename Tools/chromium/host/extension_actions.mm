#import <AppKit/AppKit.h>
#include "extension_actions.h"
#include "extension_popup.h"
#include "base/check.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "ui/base/base_window.h"
#include "ui/gfx/geometry/rect.h"
namespace boaz {
class NativeExtensionActions::Impl final : public extensions::ExtensionRegistryObserver {
 public:
  class Delegate final : public ExtensionActionDelegate {
   public:
    explicit Delegate(Impl* owner) : owner_(owner) {}
    void AttachToModel(ExtensionActionViewModel*) override {}
    void DetachFromModel() override { owner_->Close(); }
    void RegisterCommand() override {}
    void UnregisterCommand() override {}
    bool IsShowingPopup() const override {
      return owner_->popup_ && owner_->popup_->IsShowing();
    }
    void HidePopup() override { owner_->Close(); }
    gfx::NativeView GetPopupNativeViewForTesting() override {
      return owner_->popup_ ? owner_->popup_->GetNativeView() : gfx::NativeView();
    }
    void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
        PopupShowAction action, bool by_user, ShowPopupCallback callback) override {
      if (!by_user || !owner_->invoking_ || !owner_->AnchorValid()) {
        owner_->result_ = Result::kUnsupported;
        if (callback) std::move(callback).Run(nullptr);
        return;
      }
      owner_->Close();
      owner_->popup_ = NativeExtensionPopup::Create(std::move(host), owner_->browser_,
          (__bridge void*)owner_->anchor_, owner_->bounds_, action, std::move(callback));
      if (!owner_->popup_) owner_->result_ = Result::kUnavailable;
    }
    void ShowContextMenuAsFallback() override { owner_->result_ = Result::kUnsupported; }
    void CloseExtensionsMenuIfOpen() override {}
    content::WebContents* GetActiveWebContents() const override {
      auto* tab = owner_->browser_->GetActiveTabInterface();
      return tab ? tab->GetContents() : nullptr;
    }
   private:
    raw_ptr<Impl> owner_;
  };
  explicit Impl(BrowserWindowInterface* browser) : browser_(browser) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK(browser);
    registry_ = extensions::ExtensionRegistry::Get(browser->GetProfile());
    if (registry_) observation_.Observe(registry_);
  }
  ~Impl() override {
    observation_.Reset();
    Close();
    model_.reset();
  }
  bool AnchorValid() const {
    return anchor_ && browser_->GetWindow() &&
        anchor_.window == browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() &&
        anchor_.window != nil && !bounds_.IsEmpty();
  }
  void Close() {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto popup = std::move(popup_);
    if (popup) popup->Close();
  }
  Result Invoke(content::WebContents* expected, const std::string& id,
                void* anchor, const gfx::Rect& bounds) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK([NSThread isMainThread]);
    if (invoking_) return Result::kUnavailable;
    auto* tab = browser_->GetActiveTabInterface();
    if (!expected || !tab || tab->GetContents() != expected ||
        expected->GetBrowserContext() != browser_->GetProfile()) return Result::kInvalidTarget;
    anchor_ = (__bridge NSView*)anchor;
    bounds_ = bounds;
    if (!AnchorValid()) return Result::kInvalidAnchor;
    auto* extension = registry_ ? registry_->enabled_extensions().GetByID(id) : nullptr;
    if (!extension || !extensions::ExtensionActionManager::Get(browser_->GetProfile())
            ->GetExtensionAction(*extension) ||
        !extensions::ExtensionActionRunner::GetForWebContents(expected)) return Result::kUnavailable;
    auto* side_panel = extensions::SidePanelService::Get(browser_->GetProfile());
    if (side_panel && side_panel->HasSidePanelActionForTab(
          *extension, extensions::ExtensionTabUtil::GetTabId(expected))) return Result::kUnsupported;
    if (!model_ || model_->GetId() != id) {
      Close();
      model_.reset();
      model_ = ExtensionActionViewModel::Create(id, browser_, std::make_unique<Delegate>(this));
    }
    if (!model_->IsEnabled(expected)) return Result::kUnsupported;
    result_ = Result::kOk;
    invoking_ = true;
    model_->ExecuteUserAction(ToolbarActionViewModel::InvocationSource::kToolbarButton);
    invoking_ = false;
    return result_;
  }
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension* extension,
      extensions::UnloadedExtensionReason) override {
    if (model_ && model_->GetId() == extension->id()) Close();
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    observation_.Reset();
    registry_ = nullptr;
    Close();
    model_.reset();
  }
 private:
  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<extensions::ExtensionRegistry> registry_ = nullptr;
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver>
      observation_{this};
  std::unique_ptr<ExtensionActionViewModel> model_;
  std::unique_ptr<NativeExtensionPopup> popup_;
  NSView* __weak anchor_ = nil;
  gfx::Rect bounds_;
  bool invoking_ = false;
  Result result_ = Result::kUnavailable;
};
NativeExtensionActions::NativeExtensionActions(BrowserWindowInterface* browser)
    : impl_(std::make_unique<Impl>(browser)) {}
NativeExtensionActions::~NativeExtensionActions() = default;
NativeExtensionActions::Result NativeExtensionActions::Invoke(content::WebContents* contents,
    const std::string& id, void* anchor, const gfx::Rect& bounds) {
  return impl_->Invoke(contents, id, anchor, bounds);
}
void NativeExtensionActions::ClosePopup() { impl_->Close(); }
}
