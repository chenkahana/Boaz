#include "native_extension_prompt.h"
#import <AppKit/AppKit.h>
#include <map>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/install_prompt_data.h"
namespace boaz {
namespace {
using Client = extensions::ExtensionInstallPromptClient;
void UI() { CHECK_CURRENTLY_ON(content::BrowserThread::UI); CHECK([NSThread isMainThread]); }
class Prompt;
using Prompts = std::map<Prompt*, std::shared_ptr<Prompt>>;
Prompts& Active() { static base::NoDestructor<Prompts> prompts; return *prompts; }
class Prompt final : public content::WebContentsObserver, public ProfileObserver,
                     public std::enable_shared_from_this<Prompt> {
 public:
  Prompt(uint64_t token, std::unique_ptr<ExtensionInstallPromptShowParams> params,
         Client::DoneCallback callback,
         std::unique_ptr<extensions::InstallPromptData> data)
      : token_(token), params_(std::move(params)), callback_(std::move(callback)), data_(std::move(data)) {}
  uint64_t token() const { return token_; }
  void Start() {
    UI();
    if (finishing_) return;
    if (!params_ || !data_ || !callback_ || params_->WasParentDestroyed()) { Finish(Client::Result::ABORTED); return; }
    Profile* profile = params_->profile();
    NSWindow* parent = params_->GetParentWindow().GetNativeNSWindow();
    if (!profile || profile->IsOffTheRecord() || !parent || !parent.isVisible || parent.attachedSheet ||
        !IsNativeExtensionPromptContext(profile, (__bridge void*)parent) ||
        (data_->type() != extensions::InstallPromptData::INSTALL_PROMPT &&
         data_->type() != extensions::InstallPromptData::RE_ENABLE_PROMPT &&
         data_->type() != extensions::InstallPromptData::PERMISSIONS_PROMPT) ||
        data_->requires_parent_permission() || data_->ShouldWithheldPermissionsOnDialogAccept()) {
      Finish(Client::Result::ABORTED); return;
    }
    keep_alive_ = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kCrxInstaller);
    if (!keep_alive_) { Finish(Client::Result::ABORTED); return; }
    profile_observation_.Observe(profile);
    Observe(params_->GetParentWebContents());
    parent_ = parent;
    std::weak_ptr<Prompt> weak = shared_from_this();
    close_observer_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:parent queue:nil usingBlock:^(NSNotification*) {
      if (auto prompt = weak.lock()) prompt->Finish(Client::Result::ABORTED);
    }];
    alert_ = [[NSAlert alloc] init];
    alert_.messageText = base::SysUTF16ToNSString(data_->GetDialogTitle());
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(data_->GetAcceptButtonLabel())];
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(data_->GetAbortButtonLabel())];
    NSMutableString* text = [base::SysUTF16ToNSString(data_->GetPermissionsHeading()) mutableCopy];
    auto permissions = data_->GetPermissions();
    for (size_t i = 0; i < permissions.permissions.size(); ++i) {
      [text appendFormat:@"\n\n%@", base::SysUTF16ToNSString(permissions.permissions[i])];
      if (i < permissions.details.size()) [text appendFormat:@"\n%@", base::SysUTF16ToNSString(permissions.details[i])];
    }
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 220)];
    scroll.hasVerticalScroller = YES;
    NSTextView* view = [[NSTextView alloc] initWithFrame:scroll.bounds];
    view.editable = NO; view.selectable = YES; view.verticallyResizable = YES;
    view.autoresizingMask = NSViewWidthSizable; view.textContainer.widthTracksTextView = YES;
    view.string = text; [view setAccessibilityLabel:@"Requested extension permissions"];
    scroll.documentView = view; alert_.accessoryView = scroll;
    [alert_ beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
      if (auto prompt = weak.lock()) prompt->Finish(response == NSAlertFirstButtonReturn ? Client::Result::ACCEPTED : Client::Result::USER_CANCELED);
    }];
  }
  void Finish(Client::Result result) {
    UI();
    if (finishing_) { if (result == Client::Result::ABORTED) aborted_ = true; return; }
    finishing_ = true;
    aborted_ = result == Client::Result::ABORTED;
    if (alert_.window.sheetParent) [alert_.window.sheetParent endSheet:alert_.window returnCode:NSModalResponseCancel];
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Prompt> self, Client::Result result) { self->Complete(result); }, shared_from_this(), result));
  }
 private:
  void Complete(Client::Result result) {
    UI();
    if (aborted_ || !params_ || params_->WasParentDestroyed() ||
        !parent_ || !IsNativeExtensionPromptContext(params_->profile(), (__bridge void*)parent_)) result = Client::Result::ABORTED;
    if (close_observer_) [[NSNotificationCenter defaultCenter] removeObserver:close_observer_];
    close_observer_ = nil; Observe(nullptr); profile_observation_.Reset();
    if (data_) {
      if (result == Client::Result::ACCEPTED) data_->OnDialogAccepted();
      else data_->OnDialogCanceled();
    }
    if (aborted_) result = Client::Result::ABORTED;
    if (callback_) std::move(callback_).Run(Client::DoneCallbackPayload(result));
    data_.reset(); params_.reset(); keep_alive_.reset();
    Active().erase(this);
    NativeExtensionPromptsChanged();
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Finish(Client::Result::ABORTED);
  }
  void WebContentsDestroyed() override { Finish(Client::Result::ABORTED); Observe(nullptr); }
  void OnProfileWillBeDestroyed(Profile*) override { profile_observation_.Reset(); Finish(Client::Result::ABORTED); }
  const uint64_t token_;
  std::unique_ptr<ExtensionInstallPromptShowParams> params_;
  Client::DoneCallback callback_;
  std::unique_ptr<extensions::InstallPromptData> data_;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  NSWindow* __weak parent_ = nil;
  NSAlert* __strong alert_ = nil;
  id __strong close_observer_ = nil;
  bool finishing_ = false;
  bool aborted_ = false;
};
}
uint64_t ShowNativeExtensionPrompt(std::unique_ptr<ExtensionInstallPromptShowParams> params,
                              Client::DoneCallback callback,
                              std::unique_ptr<extensions::InstallPromptData> data) {
  UI();
  static uint64_t next_token = 0;
  CHECK_NE(++next_token, 0u);
  const uint64_t token = next_token;
  auto prompt = std::make_shared<Prompt>(token, std::move(params), std::move(callback), std::move(data));
  Active().emplace(prompt.get(), prompt);
  NativeExtensionPromptsChanged();
  prompt->Start();
  return token;
}
void CancelNativeExtensionPrompt(uint64_t token) {
  UI();
  for (const auto& [key, prompt] : Active()) {
    if (prompt->token() == token) { prompt->Finish(Client::Result::ABORTED); return; }
  }
}
void CancelNativeExtensionPrompts() {
  UI(); auto copy = Active();
  for (const auto& [key, prompt] : copy) prompt->Finish(Client::Result::ABORTED);
}
size_t PendingNativeExtensionPrompts() { UI(); return Active().size(); }
}
