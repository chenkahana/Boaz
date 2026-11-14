#include "extension_install.h"
#include "native_extension_prompt.h"
#import <AppKit/AppKit.h>
#include <map>
#include <memory>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/crx_installer.h"
#include "extensions/browser/install/crx_install_error.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "extensions/common/permissions/permission_set.h"
#include "ui/gfx/native_ui_types.h"

namespace boaz {
namespace {
using Client = extensions::ExtensionInstallPromptClient;
using Done = Client::DoneCallback;
void UI() { CHECK_CURRENTLY_ON(content::BrowserThread::UI); CHECK([NSThread isMainThread]); }
void Reply(Done callback, Client::Result result) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(callback), Client::DoneCallbackPayload(result)));
}
struct Operation;
using Operations = std::map<Profile*, std::shared_ptr<Operation>>;
Operations& Active() { static base::NoDestructor<Operations> operations; return *operations; }
struct Operation : std::enable_shared_from_this<Operation> {
  raw_ptr<Profile> profile;
  NSWindow* __weak parent;
  id __strong close_observer;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
  scoped_refptr<extensions::CrxInstaller> installer;
  base::OnceCallback<void(ExtensionInstallResult)> completion;
  std::string extension_id;
  bool cancelled = false;
  bool accepted = false;
  void Cancel() {
    UI(); cancelled = true;
  }
  void Finish(bool failed) {
    UI();
    if (!completion) return;
    if (close_observer) [[NSNotificationCenter defaultCenter] removeObserver:close_observer];
    close_observer = nil;
    auto* registry = extensions::ExtensionRegistry::Get(profile);
    const bool installed = !failed && registry && !extension_id.empty() &&
        registry->GetInstalledExtension(extension_id);
    auto result = installed ? ExtensionInstallResult::kInstalled :
        (cancelled && !accepted ? ExtensionInstallResult::kCancelled : ExtensionInstallResult::kFailed);
    auto callback = std::move(completion);
    Active().erase(profile.get());
    installer.reset();
    keep_alive.reset();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(std::move(callback), result));
  }

};
class NativePrompt final : public Client {
 public:
  explicit NativePrompt(std::weak_ptr<Operation> operation) : operation_(operation) {}
  void OnInstallSuccess(scoped_refptr<const extensions::Extension> extension, SkBitmap*) override {
    if (auto op = operation_.lock()) op->extension_id = extension->id();
  }
  void OnInstallFailure(const extensions::CrxInstallError&) override {}
  void SetUseAppInstalledBubble(bool) override {}
  void SetSkipPostInstallUI(bool) override {}
  void ConfirmInstall(Done callback, const extensions::Extension* extension) override { Present(std::move(callback), extension, nullptr); }
  void ShowInstallDialog(Done callback, const extensions::Extension* extension, const SkBitmap* icon) override { Present(std::move(callback), extension, icon); }
  void ConfirmReEnable(Done callback, const extensions::Extension*, content::BrowserContext*) override { Reply(std::move(callback), Result::ABORTED); }
  void ConfirmPermissions(Done callback, const extensions::Extension*, std::unique_ptr<const extensions::PermissionSet>) override { Reply(std::move(callback), Result::ABORTED); }
 private:
  void Present(Done callback, const extensions::Extension* extension, const SkBitmap* icon) {
    auto op = operation_.lock();
    if (!op || op->cancelled || !extension || !op->parent) { Reply(std::move(callback), Result::ABORTED); return; }
    op->extension_id = extension->id();
    prompt_ = std::make_unique<ExtensionInstallPrompt>(op->profile, gfx::NativeWindow(op->parent),
        std::make_unique<extensions::InstallPromptData>(extensions::InstallPromptData::INSTALL_PROMPT));
    prompt_->ShowDialog(std::move(callback), extension, icon, base::BindRepeating(
        [](std::weak_ptr<Operation> weak, std::unique_ptr<ExtensionInstallPromptShowParams> params, Done done,
           std::unique_ptr<extensions::InstallPromptData> data) {
          auto operation = weak.lock();
          if (!operation || operation->cancelled) { Reply(std::move(done), Result::ABORTED); return; }
          ShowNativeExtensionPrompt(std::move(params), base::BindOnce(
              [](std::weak_ptr<Operation> weak, Done done, Client::DoneCallbackPayload payload) {
                auto current = weak.lock();
                const auto result = !current || current->cancelled ? Result::ABORTED : payload.result;
                if (current) {
                  current->accepted = result == Result::ACCEPTED;
                  if (!current->accepted) current->cancelled = true;
                }
                std::move(done).Run(Client::DoneCallbackPayload(result));
              }, weak, std::move(done)), std::move(data));
        }, operation_));
  }
  std::weak_ptr<Operation> operation_;
  std::unique_ptr<ExtensionInstallPrompt> prompt_;
};
}
bool InstallNativeExtension(Profile* profile, void* native_parent, const base::FilePath& path,
                            base::OnceCallback<void(ExtensionInstallResult)> completion) {
  UI();
  NSWindow* parent = (__bridge NSWindow*)native_parent;
  if (!profile || profile->IsOffTheRecord() || !parent || !completion || !path.IsAbsolute() ||
      !path.MatchesExtension(FILE_PATH_LITERAL(".crx")) || Active().contains(profile)) return false;
  auto keep = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kCrxInstaller);
  if (!keep) return false;
  auto op = std::make_shared<Operation>();
  op->profile = profile; op->parent = parent; op->keep_alive = std::move(keep); op->completion = std::move(completion);
  op->installer = extensions::CrxInstaller::Create(profile, std::make_unique<NativePrompt>(op));
  op->installer->set_delete_source(false);
  op->installer->set_allow_silent_install(false);
  op->installer->set_off_store_install_allow_reason(extensions::CrxInstaller::OffStoreInstallAllowedFromSettingsPage);
  op->installer->AddInstallerCallback(base::BindOnce([](std::shared_ptr<Operation> operation,
      const std::optional<extensions::CrxInstallError>& error) {
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
            base::BindOnce([](std::shared_ptr<Operation> operation, bool failed) {
              operation->Finish(failed);
            }, std::move(operation), error.has_value()));
      }, op));
  std::weak_ptr<Operation> weak = op;
  op->close_observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
      object:parent queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) { if (auto current = weak.lock()) current->Cancel(); }];
  Active().emplace(profile, op);
  op->installer->InstallCrx(path);
  return true;
}
void CancelNativeExtensionInstalls() {
  UI();
  auto copy = Active();
  for (const auto& [profile, operation] : copy) operation->Cancel();
  CancelNativeExtensionPrompts();
}
}
