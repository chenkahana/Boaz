#import <AppKit/AppKit.h>
#include "extension_actions.h"
#include "extension_popup.h"
#include "base/check.h"
#include <map>
#include "extensions/browser/extension_action_icon_factory.h"
#include "extensions/browser/extension_icon_image.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/gfx/geometry/size.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "base/strings/string_util.h"
#include "extensions/browser/extension_action.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
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
class NativeExtensionActions::Impl final : public extensions::ExtensionRegistryObserver,
                                           public extensions::ExtensionActionDispatcher::Observer,
                                           public extensions::ExtensionActionIconFactory::Observer {
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
        if (callback)
          base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
              FROM_HERE, base::BindOnce(std::move(callback), nullptr));
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
  explicit Impl(BrowserWindowInterface* browser, base::RepeatingClosure changed)
      : browser_(browser), changed_(std::move(changed)) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK(browser);
    registry_ = extensions::ExtensionRegistry::Get(browser->GetProfile());
    if (registry_) observation_.Observe(registry_);
    if (auto* dispatcher = extensions::ExtensionActionDispatcher::Get(browser->GetProfile()))
      action_observation_.Observe(dispatcher);
  }
  ~Impl() override {
    changed_.Reset();
    icon_factories_.clear();
    action_observation_.Reset();
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
  Result GetMetadata(content::WebContents* expected, const std::string& id,
                     Metadata* output) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK([NSThread isMainThread]);
    if (!output) return Result::kInvalidTarget;
    *output = {};
    auto* tab = browser_->GetActiveTabInterface();
    if (!expected || !tab || tab->GetContents() != expected ||
        expected->GetBrowserContext() != browser_->GetProfile()) return Result::kInvalidTarget;
    auto* extension = registry_ ? registry_->enabled_extensions().GetByID(id) : nullptr;
    auto* manager = extensions::ExtensionActionManager::Get(browser_->GetProfile());
    auto* action = extension && manager ? manager->GetExtensionAction(*extension) : nullptr;
    if (!action) return Result::kUnavailable;
    const int tab_id = extensions::ExtensionTabUtil::GetTabId(expected);
    if (tab_id < 0) return Result::kInvalidTarget;
    Metadata metadata{action->GetTitle(tab_id), action->GetDisplayBadgeText(tab_id), {}};
    if (metadata.title.size() > 4096 || metadata.badge_text.size() > 256 ||
        !base::IsStringUTF8(metadata.title) || !base::IsStringUTF8(metadata.badge_text) ||
        metadata.title.find('\0') != std::string::npos ||
        metadata.badge_text.find('\0') != std::string::npos) return Result::kUnsupported;
    auto& factory = icon_factories_[id];
    if (!factory) factory = std::make_unique<extensions::ExtensionActionIconFactory>(extension, action, this);
    auto image = factory->GetIcon(tab_id);
    if (!image.IsEmpty()) {
      auto resized = gfx::ImageSkiaOperations::CreateResizedImage(*image.ToImageSkia(),
          skia::ImageOperations::RESIZE_BEST, gfx::Size(32, 32));
      const auto& bitmap = resized.GetRepresentation(1.0f).GetBitmap();
      const bool loading_default = action->GetExplicitlySetIcon(tab_id).IsEmpty() &&
          action->GetDeclarativeIcon(tab_id).IsEmpty() && action->default_icon_image() &&
          !action->default_icon_image()->did_complete_initial_load();
      if (!loading_default && bitmap.width() == 32 && bitmap.height() == 32) {
        auto encoded = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
        if (encoded && encoded->size() <= 256 * 1024) metadata.icon_png = std::move(*encoded);
      }
    }
    *output = std::move(metadata);
    return Result::kOk;
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
    if (!model_ || model_invalid_ || model_->GetId() != id) {
      Close();
      model_.reset();
      model_ = ExtensionActionViewModel::Create(id, browser_, std::make_unique<Delegate>(this));
      model_invalid_ = false;
    }
    if (!model_->IsEnabled(expected)) return Result::kUnsupported;
    result_ = Result::kOk;
    invoking_ = true;
    model_->ExecuteUserAction(ToolbarActionViewModel::InvocationSource::kToolbarButton);
    invoking_ = false;
    return result_;
  }
  void OnIconUpdated() override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (changed_) changed_.Run();
  }
  void OnExtensionActionUpdated(extensions::ExtensionAction*, content::WebContents* contents,
                                content::BrowserContext* context) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (context != browser_->GetProfile()) return;
    auto* tab = browser_->GetActiveTabInterface();
    if (contents && (!tab || tab->GetContents() != contents)) return;
    if (changed_) changed_.Run();
  }
  void OnShuttingDown() override { action_observation_.Reset(); }
  void OnExtensionLoaded(content::BrowserContext* context, const extensions::Extension*) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (context == browser_->GetProfile() && changed_) changed_.Run();
  }
  void OnExtensionUnloaded(content::BrowserContext* context, const extensions::Extension* extension,
      extensions::UnloadedExtensionReason) override {
    icon_factories_.erase(extension->id());
    if (model_ && model_->GetId() == extension->id()) {
      model_invalid_ = true;
      Close();
    }
    if (context == browser_->GetProfile() && changed_) changed_.Run();
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    icon_factories_.clear();
    action_observation_.Reset();
    changed_.Reset();
    observation_.Reset();
    registry_ = nullptr;
    Close();
    model_.reset();
  }
 private:
  raw_ptr<BrowserWindowInterface> browser_;
  base::RepeatingClosure changed_;
  std::map<std::string, std::unique_ptr<extensions::ExtensionActionIconFactory>> icon_factories_;
  base::ScopedObservation<extensions::ExtensionActionDispatcher,
      extensions::ExtensionActionDispatcher::Observer> action_observation_{this};
  raw_ptr<extensions::ExtensionRegistry> registry_ = nullptr;
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver>
      observation_{this};
  std::unique_ptr<ExtensionActionViewModel> model_;
  std::unique_ptr<NativeExtensionPopup> popup_;
  NSView* __weak anchor_ = nil;
  gfx::Rect bounds_;
  bool invoking_ = false;
  bool model_invalid_ = false;
  Result result_ = Result::kUnavailable;
};
NativeExtensionActions::NativeExtensionActions(BrowserWindowInterface* browser,
    base::RepeatingClosure changed)
    : impl_(std::make_unique<Impl>(browser, std::move(changed))) {}
NativeExtensionActions::~NativeExtensionActions() = default;
NativeExtensionActions::Result NativeExtensionActions::Invoke(content::WebContents* contents,
    const std::string& id, void* anchor, const gfx::Rect& bounds) {
  return impl_->Invoke(contents, id, anchor, bounds);
}
NativeExtensionActions::Result NativeExtensionActions::GetMetadata(
    content::WebContents* contents, const std::string& id, Metadata* output) const {
  return impl_->GetMetadata(contents, id, output);
}
void NativeExtensionActions::ClosePopup() { impl_->Close(); }
}
