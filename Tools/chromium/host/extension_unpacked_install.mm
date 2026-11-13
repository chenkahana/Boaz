#include "extension_unpacked_install.h"
#import <AppKit/AppKit.h>
#include <map>
#include <memory>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "chrome/browser/extensions/extension_util.h"
#include "chrome/browser/extensions/extension_management.h"
#include "chrome/browser/supervised_user/supervised_user_browser_utils.h"
#include "components/prefs/pref_service.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/unpacked_installer.h"

namespace boaz {
namespace {
void UI() {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK([NSThread isMainThread]);
}
struct Operation;
using Operations = std::map<Profile*, std::shared_ptr<Operation>>;
Operations& Active() {
  static base::NoDestructor<Operations> operations;
  return *operations;
}
struct Operation : ProfileObserver, std::enable_shared_from_this<Operation> {
  raw_ptr<Profile> profile = nullptr;
  base::FilePath path;
  NSWindow* __weak parent;
  NSAlert* __strong alert;
  id __strong close_observer;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
  scoped_refptr<extensions::UnpackedInstaller> installer;
  base::OnceCallback<void(ExtensionInstallResult)> completion;
  bool loading = false;

  void Finish(ExtensionInstallResult result) {
    UI();
    if (!completion) return;
    auto self = shared_from_this();
    auto callback = std::move(completion);
    if (close_observer) [[NSNotificationCenter defaultCenter] removeObserver:close_observer];
    close_observer = nil;
    if (alert.window.sheetParent)
      [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
    profile->RemoveObserver(this);
    Active().erase(profile.get());
    profile = nullptr;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Operation> operation,
                         base::OnceCallback<void(ExtensionInstallResult)> reply,
                         ExtensionInstallResult result) {
          operation->installer.reset();
          operation->keep_alive.reset();
          std::move(reply).Run(result);
        }, std::move(self), std::move(callback), result));
  }
  void Cancel() {
    UI();
    if (!loading) Finish(ExtensionInstallResult::kCancelled);
  }
  void OnProfileWillBeDestroyed(Profile*) override {
    Finish(ExtensionInstallResult::kFailed);
  }
  void Load() {
    UI();
    if (!completion || loading) return;
    if (!parent || !parent.isVisible) { Cancel(); return; }
    if (supervised_user::AreExtensionsPermissionsEnabled(profile) ||
        extensions::ExtensionManagementFactory::GetForBrowserContext(profile)->BlocklistedByDefault()) {
      Finish(ExtensionInstallResult::kFailed);
      return;
    }
    auto* profile_prefs = profile->GetPrefs();
    if (!profile_prefs->GetBoolean(prefs::kExtensionsUIDeveloperMode)) {
      if (!profile_prefs->IsUserModifiablePreference(prefs::kExtensionsUIDeveloperMode)) {
        Finish(ExtensionInstallResult::kFailed);
        return;
      }
      extensions::util::SetDeveloperModeForProfile(profile, true);
    }
    if (!completion || !profile) return;
    loading = true;
    installer = extensions::UnpackedInstaller::Create(profile);
    installer->set_allow_file_access(false);
    installer->set_allow_incognito_access(false);
    installer->set_be_noisy_on_failure(false);
    std::weak_ptr<Operation> weak = shared_from_this();
    installer->set_completion_callback(base::BindOnce(
        [](std::weak_ptr<Operation> weak, const extensions::Extension* extension,
           const base::FilePath&, const std::u16string& error) {
          if (auto operation = weak.lock()) {
            auto* registry = operation->profile
                ? extensions::ExtensionRegistry::Get(operation->profile) : nullptr;
            const bool enabled = extension && error.empty() && registry &&
                registry->enabled_extensions().Contains(extension->id());
            operation->Finish(enabled ? ExtensionInstallResult::kInstalled : ExtensionInstallResult::kFailed);
          }
        }, weak));
    installer->Load(path);
  }
  void Show() {
    UI();
    if (!completion) return;
    if (!parent || !parent.isVisible || parent.attachedSheet) { Cancel(); return; }
    alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Load developer extension?";
    alert.informativeText = [NSString stringWithFormat:
        @"Only load a folder from a developer you trust. This turns on developer extensions for this profile and may re-enable other installed developer extensions. The extension will run with its requested permissions and may read or change your browsing data. Future changes to this folder are also trusted. This is not a permission-by-permission review. File URL and private browsing access remain disabled.\n\n%@",
        base::SysUTF8ToNSString(path.value())];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Load Extension"];
    std::weak_ptr<Operation> weak = shared_from_this();
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
          base::BindOnce([](std::weak_ptr<Operation> weak, bool approved) {
            if (auto operation = weak.lock()) {
              if (approved) operation->Load();
              else operation->Cancel();
            }
          }, weak, response == NSAlertSecondButtonReturn));
    }];
  }
};
}
bool InstallNativeUnpackedExtension(Profile* profile, void* native_parent,
    const base::FilePath& path, base::OnceCallback<void(ExtensionInstallResult)> completion) {
  UI();
  NSWindow* parent = (__bridge NSWindow*)native_parent;
  if (!profile || profile->IsOffTheRecord() || !parent || !completion ||
      !path.IsAbsolute() || path.ReferencesParent() || Active().contains(profile)) return false;
  auto keep = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kCrxInstaller);
  if (!keep) return false;
  auto operation = std::make_shared<Operation>();
  operation->profile = profile;
  operation->path = path;
  operation->parent = parent;
  operation->keep_alive = std::move(keep);
  operation->completion = std::move(completion);
  profile->AddObserver(operation.get());
  std::weak_ptr<Operation> weak = operation;
  operation->close_observer = [[NSNotificationCenter defaultCenter]
      addObserverForName:NSWindowWillCloseNotification object:parent
      queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
        if (auto current = weak.lock()) current->Cancel();
      }];
  Active().emplace(profile, operation);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](std::weak_ptr<Operation> weak) {
        if (auto current = weak.lock()) current->Show();
      }, weak));
  return true;
}
void CancelNativeUnpackedExtensionInstalls() {
  UI();
  auto copy = Active();
  for (const auto& [profile, operation] : copy) operation->Cancel();
}
}
