#import <AppKit/AppKit.h>
#include "extension_side_panel.h"
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/common/extensions/api/side_panel.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/common/extension.h"

namespace boaz {
namespace {
void CheckUI() {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK([NSThread isMainThread]);
}
}  // namespace

class NativeSidePanel::Impl final : public extensions::ExtensionView,
                                    public extensions::ExtensionRegistryObserver,
                                    public extensions::SidePanelService::Observer {
 public:
  Impl(BrowserWindowInterface* browser, Presenter presenter)
      : browser_(browser), presenter_(std::move(presenter)) {
    registry_.Observe(extensions::ExtensionRegistry::Get(browser->GetProfile()));
    if (auto* service = extensions::SidePanelService::Get(browser->GetProfile())) service_.Observe(service);
  }
  ~Impl() override {
    closing_ = true;
    Hide(SidePanelEntryHideReason::kSidePanelClosed);
  }
  // Shows `id`'s panel for the active tab, replacing another. False when the tab has none.
  bool Show(const std::string& id) {
    CheckUI();
    if (closing_) return false;
    auto* tab = browser_->GetActiveTabInterface();
    content::WebContents* contents = tab ? tab->GetContents() : nullptr;
    auto* extension = extensions::ExtensionRegistry::Get(browser_->GetProfile())->enabled_extensions().GetByID(id);
    auto* service = extensions::SidePanelService::Get(browser_->GetProfile());
    if (!contents || !extension || !service) return false;
    const int tab_id = extensions::ExtensionTabUtil::GetTabId(contents);
    const auto options = service->GetOptions(*extension, tab_id);
    if (!options.enabled.value_or(false) || !options.path) return false;
    const auto specific = service->GetSpecificOptionsForTab(*extension, tab_id);
    const bool contextual = specific.path && specific.enabled.value_or(false);
    const GURL url = extension->GetResourceURL(*options.path);
    if (host_ && id_ == id && url_ == url && contextual_ == contextual) return true;
    Hide(SidePanelEntryHideReason::kReplaced);
    auto host = extensions::ExtensionViewHostFactory::CreateSidePanelHost(*extension, url, browser_.get(),
                                                                         contextual ? tab : nullptr);
    if (!host) return false;
    host_ = std::move(host);
    id_ = id;
    url_ = url;
    contextual_ = contextual;
    tab_id_ = tab_id;
    host_->set_view(this);
    host_->SetCloseHandler(base::BindOnce([](base::WeakPtr<Impl> self, extensions::ExtensionHost*) {
      if (self) self->PostHide(SidePanelEntryHideReason::kSidePanelClosed);
    }, weak_.GetWeakPtr()));
    host_->CreateRendererSoon();
    presenter_.Run((__bridge void*)host_->host_contents()->GetNativeView().GetNativeNSView(), extension->name());
    host_->host_contents()->WasShown();
    service->DispatchOnOpenedEvent(id, extensions::ExtensionTabUtil::GetWindowId(browser_.get()),
        contextual ? std::optional<int>(tab_id) : std::nullopt, url.path());
    shown_.Notify();
    return true;
  }
  void Hide(SidePanelEntryHideReason reason) {
    CheckUI();
    if (!host_) return;
    auto host = std::move(host_);
    const std::string id = std::exchange(id_, std::string());
    const std::string path(url_.path());
    url_ = GURL();
    host->host_contents()->WasHidden();
    presenter_.Run(nullptr, std::string());
    if (auto* service = extensions::SidePanelService::Get(browser_->GetProfile()))
      service->DispatchOnClosedEvent(id, extensions::ExtensionTabUtil::GetWindowId(browser_.get()),
          contextual_ ? std::optional<int>(tab_id_) : std::nullopt, path);
    // The host's own close request arrives through PostHide, so this never runs inside one of its callbacks.
    host.reset();
  }
  void PostHide(SidePanelEntryHideReason reason) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<Impl> self, SidePanelEntryHideReason reason) { if (self) self->Hide(reason); },
        weak_.GetWeakPtr(), reason));
  }
  // After a tab switch or an options change: the panel for the active tab, or none.
  void Refresh() {
    if (!host_) return;
    const std::string id = id_;
    if (!Show(id)) Hide(SidePanelEntryHideReason::kBackgrounded);
  }
  const std::string& id() const { return id_; }
  bool showing() const { return host_ != nullptr; }
  bool contextual() const { return contextual_; }
  content::WebContents* contents() const { return host_ ? host_->host_contents() : nullptr; }
  base::CallbackListSubscription RegisterShown(ShownCallback callback) { return shown_.Add(std::move(callback)); }

  // extensions::ExtensionView
  gfx::NativeView GetNativeView() override {
    return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView();
  }
  void ResizeDueToAutoResize(content::WebContents*, const gfx::Size&) override {}
  void RenderFrameCreated(content::RenderFrameHost*) override {}
  bool HandleKeyboardEvent(content::WebContents*, const input::NativeWebKeyboardEvent& event) override {
    if (event.skip_if_unhandled || !event.os_event.Get()) return false;
    NSEvent* native_event = event.os_event.Get();
    return native_event.type == NSEventTypeKeyDown && [NSApp.mainMenu performKeyEquivalent:native_event];
  }
  void OnLoaded() override {}

  // extensions::ExtensionRegistryObserver
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (extension->id() == id_) Hide(SidePanelEntryHideReason::kSidePanelClosed);
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_.Reset();
    Hide(SidePanelEntryHideReason::kSidePanelClosed);
  }
  // extensions::SidePanelService::Observer
  void OnPanelOptionsChanged(const extensions::ExtensionId& id,
                             const extensions::api::side_panel::PanelOptions&) override {
    if (id == id_) PostRefresh();
  }
  void OnSidePanelServiceShutdown() override { service_.Reset(); }
  void PostRefresh() {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<Impl> self) { if (self) self->Refresh(); }, weak_.GetWeakPtr()));
  }

 private:
  raw_ptr<BrowserWindowInterface> browser_;
  Presenter presenter_;
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  std::string id_;
  GURL url_;
  bool contextual_ = false;
  int tab_id_ = -1;
  bool closing_ = false;
  base::RepeatingCallbackList<void()> shown_;
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver> registry_{this};
  base::ScopedObservation<extensions::SidePanelService, extensions::SidePanelService::Observer> service_{this};
  base::WeakPtrFactory<Impl> weak_{this};
};

namespace {
std::optional<std::string> ExtensionOf(const SidePanelEntryKey& key) {
  if (key.id() != SidePanelEntryId::kExtension) return std::nullopt;
  return key.extension_id();
}
}  // namespace

NativeSidePanel::NativeSidePanel(BrowserWindowInterface* browser, Presenter presenter)
    : impl_(std::make_unique<Impl>(browser, std::move(presenter))) {}
NativeSidePanel::~NativeSidePanel() = default;
void NativeSidePanel::Close() { impl_->Hide(SidePanelEntryHideReason::kSidePanelClosed); }
void NativeSidePanel::Show(SidePanelEntryId, std::optional<SidePanelOpenTrigger>, bool) {}
void NativeSidePanel::Show(SidePanelEntryKey key, std::optional<SidePanelOpenTrigger>, bool) {
  if (auto id = ExtensionOf(key)) impl_->Show(*id);
}
void NativeSidePanel::ShowFrom(SidePanelEntryKey key, gfx::Rect) { Show(key, std::nullopt, false); }
void NativeSidePanel::Close(SidePanelEntryHideReason reason, bool) { impl_->Hide(reason); }
void NativeSidePanel::Toggle(SidePanelEntryKey key, SidePanelOpenTrigger trigger) {
  if (IsSidePanelEntryShowing(key)) impl_->Hide(SidePanelEntryHideReason::kSidePanelClosed);
  else Show(key, trigger, false);
}
std::optional<SidePanelEntryId> NativeSidePanel::GetCurrentEntryId() const {
  return impl_->showing() ? std::optional(SidePanelEntryId::kExtension) : std::nullopt;
}
int NativeSidePanel::GetCurrentEntryDefaultContentWidth() const { return 0; }
void NativeSidePanel::OverrideContentsWidth(int) {}
void NativeSidePanel::ResetContentsWidthOverride() {}
bool NativeSidePanel::IsSidePanelShowing() const { return impl_->showing(); }
bool NativeSidePanel::IsSidePanelEntryShowing(const SidePanelEntryKey& key) const {
  auto id = ExtensionOf(key);
  return id && impl_->showing() && impl_->id() == *id;
}
bool NativeSidePanel::IsSidePanelEntryShowing(const SidePanelEntryKey& key, bool for_tab) const {
  return IsSidePanelEntryShowing(key) && impl_->contextual() == for_tab;
}
base::CallbackListSubscription NativeSidePanel::RegisterSidePanelShown(ShownCallback callback) {
  return impl_->RegisterShown(std::move(callback));
}
void NativeSidePanel::OnActiveTabChanged(content::WebContents*, content::WebContents*, bool) {
  impl_->PostRefresh();
}
content::WebContents* NativeSidePanel::GetWebContentsForTest(SidePanelEntryId id) {
  return id == SidePanelEntryId::kExtension ? impl_->contents() : nullptr;
}
}  // namespace boaz
