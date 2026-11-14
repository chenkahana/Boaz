#include "extension_permission_review.h"
#include "extension_management.h"
#include "native_extension_prompt.h"
#import <AppKit/AppKit.h>
#include <map>
#include <memory>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
namespace boaz {
namespace {
using Client = extensions::ExtensionInstallPromptClient;
void UI() { CHECK_CURRENTLY_ON(content::BrowserThread::UI); CHECK([NSThread isMainThread]); }
class Review;
using Reviews = std::map<Profile*, std::shared_ptr<Review>>;
Reviews& Active() { static base::NoDestructor<Reviews> reviews; return *reviews; }
class Review final : public extensions::ExtensionRegistryObserver, public ProfileObserver,
                     public std::enable_shared_from_this<Review> {
 public:
  Review(Profile* profile, NSWindow* parent, const extensions::Extension* extension,
         std::unique_ptr<ScopedProfileKeepAlive> keep,
         base::OnceCallback<void(ExtensionInstallResult)> callback)
      : profile_(profile), parent_(parent), extension_(extension), keep_(std::move(keep)), callback_(std::move(callback)) {}
  void Start() {
    profile_observation_.Observe(profile_);
    registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile_));
    std::weak_ptr<Review> weak = shared_from_this();
    observer_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:parent_ queue:nil usingBlock:^(NSNotification*) {
      if (auto self = weak.lock()) self->Cancel();
    }];
    prompt_ = std::make_unique<ExtensionInstallPrompt>(profile_, gfx::NativeWindow(parent_),
        std::make_unique<extensions::InstallPromptData>(extensions::InstallPromptData::RE_ENABLE_PROMPT));
    prompt_->ShowDialog(base::BindOnce([](std::weak_ptr<Review> weak, Client::DoneCallbackPayload payload) {
      if (auto self = weak.lock()) self->Decide(payload.result);
    }, weak), extension_.get(), nullptr,
        base::BindRepeating([](std::weak_ptr<Review> weak,
                              std::unique_ptr<ExtensionInstallPromptShowParams> params,
                              Client::DoneCallback callback,
                              std::unique_ptr<extensions::InstallPromptData> data) {
          auto self = weak.lock();
          if (!self || self->cancelled_) {
            base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
                base::BindOnce(std::move(callback), Client::DoneCallbackPayload(Client::Result::ABORTED)));
            return;
          }
          self->prompt_token_ = ShowNativeExtensionPrompt(std::move(params), std::move(callback), std::move(data));
          if (self->cancelled_) CancelNativeExtensionPrompt(self->prompt_token_);
        }, weak));
  }
  void Cancel() {
    UI(); cancelled_ = true;
    if (prompt_token_) CancelNativeExtensionPrompt(prompt_token_);
    Decide(Client::Result::ABORTED);
  }
 private:
  void Decide(Client::Result result) {
    UI();
    if (finishing_) return;
    finishing_ = true;
    auto outcome = ExtensionInstallResult::kCancelled;
    if (!cancelled_ && result == Client::Result::ACCEPTED) {
      outcome = ExtensionInstallResult::kFailed;
      auto* registry = extensions::ExtensionRegistry::Get(profile_);
      auto* registrar = extensions::ExtensionRegistrar::Get(profile_);
      if (parent_ && IsNativeExtensionPromptContext(profile_, (__bridge void*)parent_) &&
          registry && registrar && registry->disabled_extensions().GetByID(extension_->id()) == extension_.get() &&
          NeedsExtensionPermissionReview(profile_, extension_->id())) {
        registry_observation_.Reset();
        registrar->GrantPermissionsAndEnableExtension(*extension_);
        if (registry->enabled_extensions().GetByID(extension_->id()) == extension_.get() &&
            !registry->disabled_extensions().GetByID(extension_->id())) outcome = ExtensionInstallResult::kInstalled;
      }
    }
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Review> self, ExtensionInstallResult outcome) {
          self->Complete(outcome);
        }, shared_from_this(), outcome));
  }
  void Complete(ExtensionInstallResult outcome) {
    if (observer_) [[NSNotificationCenter defaultCenter] removeObserver:observer_];
    observer_ = nil; registry_observation_.Reset(); profile_observation_.Reset();
    prompt_.reset();
    std::move(callback_).Run(outcome);
    keep_.reset(); Active().erase(profile_.get()); NativeExtensionPromptsChanged();
  }
  void OnExtensionWillBeInstalled(content::BrowserContext*, const extensions::Extension* extension,
                                   bool, const std::string&) override { if (extension->id() == extension_->id()) Cancel(); }
  void OnExtensionLoaded(content::BrowserContext*, const extensions::Extension* extension) override { if (extension->id() == extension_->id()) Cancel(); }
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override { if (extension->id() == extension_->id()) Cancel(); }
  void OnExtensionUninstalled(content::BrowserContext*, const extensions::Extension* extension,
                              extensions::UninstallReason) override { if (extension->id() == extension_->id()) Cancel(); }
  void OnShutdown(extensions::ExtensionRegistry*) override { registry_observation_.Reset(); Cancel(); }
  void OnProfileWillBeDestroyed(Profile*) override { profile_observation_.Reset(); Cancel(); }
  raw_ptr<Profile> profile_;
  NSWindow* __weak parent_;
  id __strong observer_ = nil;
  scoped_refptr<const extensions::Extension> extension_;
  std::unique_ptr<ScopedProfileKeepAlive> keep_;
  base::OnceCallback<void(ExtensionInstallResult)> callback_;
  std::unique_ptr<ExtensionInstallPrompt> prompt_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver> registry_observation_{this};
  uint64_t prompt_token_ = 0;
  bool cancelled_ = false;
  bool finishing_ = false;
};
}
bool StartExtensionPermissionReview(Profile* profile, void* native_parent, const std::string& id,
                                    base::OnceCallback<void(ExtensionInstallResult)> callback) {
  UI();
  NSWindow* parent = (__bridge NSWindow*)native_parent;
  if (!callback || !parent || !parent.isVisible || parent.attachedSheet || Active().contains(profile) ||
      !NeedsExtensionPermissionReview(profile, id) || !IsNativeExtensionPromptContext(profile, native_parent)) return false;
  auto keep = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kCrxInstaller);
  if (!keep) return false;
  auto review = std::make_shared<Review>(profile, parent,
      extensions::ExtensionRegistry::Get(profile)->disabled_extensions().GetByID(id), std::move(keep), std::move(callback));
  Active().emplace(profile, review); review->Start(); NativeExtensionPromptsChanged(); return true;
}
void CancelExtensionPermissionReviews() {
  UI(); auto copy = Active();
  for (const auto& [profile, review] : copy) review->Cancel();
}
size_t PendingExtensionPermissionReviews() { UI(); return Active().size(); }
}
