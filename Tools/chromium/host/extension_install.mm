#include "extension_install.h"
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
#include "extensions/browser/crx_install_error.h"
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
  NSAlert* __strong alert;
  id __strong close_observer;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
  scoped_refptr<extensions::CrxInstaller> installer;
  base::OnceCallback<void(ExtensionInstallResult)> completion;
  Done consent;
  std::string extension_id;
  bool cancelled = false;
  bool accepted = false;
  void Cancel() {
    UI(); cancelled = true;
    if (consent) Reply(std::move(consent), Client::Result::ABORTED);
    if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
  }
  void Finish(bool failed) {
    UI();
    if (!completion) return;
    if (close_observer) [[NSNotificationCenter defaultCenter] removeObserver:close_observer];
    close_observer = nil;
    if (consent) Reply(std::move(consent), Client::Result::ABORTED);
    if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
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
  void Show(Done callback, std::unique_ptr<extensions::InstallPromptData> data) {
    UI();
    if (cancelled || !parent || !parent.isVisible || parent.attachedSheet ||
        data->requires_parent_permission() || data->ShouldWithheldPermissionsOnDialogAccept()) {
      cancelled = true; Reply(std::move(callback), Client::Result::ABORTED); return;
    }
    consent = std::move(callback);
    alert = [[NSAlert alloc] init];
    alert.messageText = base::SysUTF16ToNSString(data->GetDialogTitle());
    [alert addButtonWithTitle:base::SysUTF16ToNSString(data->GetAcceptButtonLabel())];
    [alert addButtonWithTitle:base::SysUTF16ToNSString(data->GetAbortButtonLabel())];
    NSMutableString* text = [base::SysUTF16ToNSString(data->GetPermissionsHeading()) mutableCopy];
    auto permissions = data->GetPermissions();
    for (size_t i = 0; i < permissions.permissions.size(); ++i) {
      [text appendFormat:@"\n\n%@", base::SysUTF16ToNSString(permissions.permissions[i])];
      if (i < permissions.details.size()) [text appendFormat:@"\n%@", base::SysUTF16ToNSString(permissions.details[i])];
    }
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 220)];
    scroll.hasVerticalScroller = YES;
    NSTextView* view = [[NSTextView alloc] initWithFrame:scroll.bounds];
    view.editable = NO; view.selectable = YES; view.verticallyResizable = YES;
    view.autoresizingMask = NSViewWidthSizable;
    view.textContainer.widthTracksTextView = YES;
    view.string = text;
    [view setAccessibilityLabel:@"Requested extension permissions"];
    scroll.documentView = view; alert.accessoryView = scroll;
    std::weak_ptr<Operation> weak = shared_from_this();
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
      if (auto op = weak.lock(); op && op->consent) {
        bool accept = !op->cancelled && response == NSAlertFirstButtonReturn;
        op->accepted = accept;
        if (!accept) op->cancelled = true;
        auto decision = std::move(op->consent);
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
            base::BindOnce([](std::weak_ptr<Operation> weak, Done callback, bool accept) {
              auto current = weak.lock();
              const bool approved = current && !current->cancelled && accept;
              if (current) current->accepted = approved;
              std::move(callback).Run(Client::DoneCallbackPayload(
                  approved ? Client::Result::ACCEPTED : Client::Result::USER_CANCELED));
            }, weak, std::move(decision), accept));
      }
    }];
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
        [](std::weak_ptr<Operation> weak, std::unique_ptr<ExtensionInstallPromptShowParams>, Done done,
           std::unique_ptr<extensions::InstallPromptData> data) {
          if (auto operation = weak.lock()) operation->Show(std::move(done), std::move(data));
          else Reply(std::move(done), Result::ABORTED);
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
}
}
