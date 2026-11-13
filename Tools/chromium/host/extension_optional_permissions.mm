#include "extension_optional_permissions.h"
#import <AppKit/AppKit.h>
#include <map>
#include <optional>
#include <vector>
#include "native_extension_prompt.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "base/uuid.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/frame_tree_node_id.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_function.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/process_manager.h"
#include "extensions/browser/process_manager_observer.h"
#include "extensions/common/extension.h"
#include "extensions/common/permissions/permission_set.h"
#include "ui/gfx/native_ui_types.h"

namespace boaz {
namespace {
using Client = extensions::ExtensionInstallPromptClient;
using Done = Client::DoneCallback;
void UI() { CHECK_CURRENTLY_ON(content::BrowserThread::UI); CHECK([NSThread isMainThread]); }
void Abort(Done done) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(done), Client::DoneCallbackPayload(Client::Result::ABORTED)));
}
class Request;
using Requests = std::map<Request*, std::shared_ptr<Request>>;
Requests& Active() { static base::NoDestructor<Requests> requests; return *requests; }
class Request final : public content::WebContentsObserver, public ProfileObserver,
    public extensions::ExtensionRegistryObserver, public extensions::ProcessManagerObserver,
    public std::enable_shared_from_this<Request> {
 public:
  Request(Profile* profile, NSWindow* parent, ExtensionFunction& requester) : parent_(parent) {
    UI();
    if (!profile || profile->IsOffTheRecord() || requester.browser_context() != profile ||
        !requester.extension() || !IsNativeExtensionPromptContext(profile, (__bridge void*)parent)) return;
    profile_ = profile;
    extension_ = requester.extension();
    if (auto* frame = requester.render_frame_host()) {
      if (frame->GetBrowserContext() != profile || !frame->IsActive() || !frame->IsRenderFrameLive()) return;
      document_ = frame->GetWeakDocumentPtr();
      for (auto* ancestor = frame; ancestor; ancestor = ancestor->GetParent())
        ancestors_.push_back(ancestor->GetFrameTreeNodeId());
      Observe(content::WebContents::FromRenderFrameHost(frame));
    } else if (requester.worker_id()) {
      worker_ = requester.worker_id();
      if (worker_->extension_id != extension_->id()) return;
      auto* manager = extensions::ProcessManager::Get(profile);
      if (!manager || !manager->HasServiceWorker(*worker_)) return;
      worker_context_ = manager->GetContextIdForWorker(*worker_);
      if (!worker_context_.is_valid()) return;
    } else return;
    keep_alive_ = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kCrxInstaller);
    if (!keep_alive_) return;
    profile_observation_.Observe(profile);
    if (auto* registry = extensions::ExtensionRegistry::Get(profile)) registry_observation_.Observe(registry);
    if (worker_) process_observation_.Observe(extensions::ProcessManager::Get(profile));
    valid_ = true;
  }
  ~Request() override { if (close_observer_) [[NSNotificationCenter defaultCenter] removeObserver:close_observer_]; }
  bool Valid() const {
    if (!valid_ || !profile_ || !parent_ || !parent_.isVisible ||
        !IsNativeExtensionPromptContext(profile_, (__bridge void*)parent_)) return false;
    auto* registry = extensions::ExtensionRegistry::Get(profile_);
    if (!registry || registry->enabled_extensions().GetByID(extension_->id()) != extension_.get()) return false;
    if (worker_) {
      auto* manager = extensions::ProcessManager::Get(profile_);
      return manager && manager->HasServiceWorker(*worker_) &&
          manager->GetContextIdForWorker(*worker_) == worker_context_;
    }
    auto* frame = document_.AsRenderFrameHostIfValid();
    return frame && frame->IsActive() && frame->IsRenderFrameLive() &&
        content::WebContents::FromRenderFrameHost(frame) == web_contents();
  }
  void Start(Done callback, const extensions::Extension* extension,
             std::unique_ptr<const extensions::PermissionSet> permissions) {
    UI();
    if (started_) { Abort(std::move(callback)); return; }
    started_ = true;
    callback_ = std::move(callback);
    Active().emplace(this, shared_from_this());
    NativeExtensionPromptsChanged();
    if (!Valid() || extension != extension_.get() || !permissions) { Finish(Client::Result::ABORTED); return; }
    std::weak_ptr<Request> weak = shared_from_this();
    close_observer_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
        object:parent_ queue:nil usingBlock:^(NSNotification*) { if (auto request = weak.lock()) request->Cancel(); }];
    prompt_ = std::make_unique<ExtensionInstallPrompt>(profile_, gfx::NativeWindow(parent_),
        std::make_unique<extensions::InstallPromptData>(extensions::InstallPromptData::PERMISSIONS_PROMPT));
    prompt_->ShowDialog(base::BindOnce([](std::weak_ptr<Request> weak, Client::DoneCallbackPayload payload) {
      if (auto request = weak.lock()) request->Finish(payload.result);
    }, weak), extension_.get(), nullptr, std::move(permissions), base::BindRepeating(
        [](std::weak_ptr<Request> weak, std::unique_ptr<ExtensionInstallPromptShowParams> params,
           Done done, std::unique_ptr<extensions::InstallPromptData> data) {
          auto request = weak.lock();
          if (!request || !request->Valid() || request->finishing_) { Abort(std::move(done)); return; }
          request->prompt_token_ = ShowNativeExtensionPrompt(std::move(params), std::move(done), std::move(data));
        }, weak));
  }
  void Cancel() {
    UI(); valid_ = false;
    if (prompt_token_) CancelNativeExtensionPrompt(prompt_token_);
    Finish(Client::Result::ABORTED);
  }
 private:
  void Finish(Client::Result result) {
    if (!callback_ || finishing_) return;
    finishing_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Request> self, Client::Result result) {
          if (!self->Valid()) result = Client::Result::ABORTED;
          if (result != Client::Result::ACCEPTED && result != Client::Result::USER_CANCELED)
            result = Client::Result::ABORTED;
          auto callback = std::move(self->callback_);
          self->Observe(nullptr);
          self->profile_observation_.Reset(); self->registry_observation_.Reset(); self->process_observation_.Reset();
          if (self->close_observer_) [[NSNotificationCenter defaultCenter] removeObserver:self->close_observer_];
          self->close_observer_ = nil;
          self->prompt_.reset();
          std::move(callback).Run(Client::DoneCallbackPayload(result));
          self->keep_alive_.reset(); self->profile_ = nullptr;
          Active().erase(self.get());
          NativeExtensionPromptsChanged();
        }, shared_from_this(), result));
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsSameDocument()) return;
    for (auto node : ancestors_) if (node == navigation->GetFrameTreeNodeId()) { Cancel(); return; }
  }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (document_.AsRenderFrameHostIfValid() == frame || !document_.AsRenderFrameHostIfValid()) Cancel();
  }
  void WebContentsDestroyed() override { Cancel(); Observe(nullptr); }
  void OnProfileWillBeDestroyed(Profile*) override { Cancel(); profile_observation_.Reset(); profile_ = nullptr; }
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (extension == extension_.get()) Cancel();
  }
  void OnShutdown(extensions::ExtensionRegistry*) override { Cancel(); registry_observation_.Reset(); }
  void OnStoppedTrackingServiceWorkerInstance(content::BrowserContext&, const extensions::WorkerId& worker) override {
    if (worker_ && *worker_ == worker) Cancel();
  }
  void OnProcessManagerShutdown(extensions::ProcessManager*) override { Cancel(); process_observation_.Reset(); }
  raw_ptr<Profile> profile_ = nullptr;
  NSWindow* __weak parent_;
  id __strong close_observer_;
  scoped_refptr<const extensions::Extension> extension_;
  content::WeakDocumentPtr document_;
  std::vector<content::FrameTreeNodeId> ancestors_;
  std::optional<extensions::WorkerId> worker_;
  base::Uuid worker_context_;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver> registry_observation_{this};
  base::ScopedObservation<extensions::ProcessManager, extensions::ProcessManagerObserver> process_observation_{this};
  std::unique_ptr<ExtensionInstallPrompt> prompt_;
  Done callback_;
  uint64_t prompt_token_ = 0;
  bool valid_ = false;
  bool started_ = false;
  bool finishing_ = false;
};
class NativeClient final : public Client {
 public:
  explicit NativeClient(std::shared_ptr<Request> request) : request_(std::move(request)) {}
  ~NativeClient() override { request_->Cancel(); }
  void OnInstallSuccess(scoped_refptr<const extensions::Extension>, SkBitmap*) override {}
  void OnInstallFailure(const extensions::CrxInstallError&) override {}
  void SetUseAppInstalledBubble(bool) override {}
  void SetSkipPostInstallUI(bool) override {}
  void ConfirmInstall(Done done, const extensions::Extension*) override { Abort(std::move(done)); }
  void ConfirmReEnable(Done done, const extensions::Extension*, content::BrowserContext*) override { Abort(std::move(done)); }
  void ShowInstallDialog(Done done, const extensions::Extension*, const SkBitmap*) override { Abort(std::move(done)); }
  void ConfirmPermissions(Done done, const extensions::Extension* extension,
                          std::unique_ptr<const extensions::PermissionSet> permissions) override {
    request_->Start(std::move(done), extension, std::move(permissions));
  }
 private:
  std::shared_ptr<Request> request_;
};
}
std::unique_ptr<extensions::ExtensionInstallPromptClient> CreateNativeOptionalPermissionsPrompt(
    Profile* profile, gfx::NativeWindow window, ExtensionFunction& requester) {
  UI();
  return std::make_unique<NativeClient>(std::make_shared<Request>(profile, window.GetNativeNSWindow(), requester));
}
void CancelNativeOptionalPermissionPrompts() {
  UI(); auto copy = Active();
  for (const auto& [key, request] : copy) request->Cancel();
}
size_t PendingNativeOptionalPermissionPrompts() { UI(); return Active().size(); }
}
