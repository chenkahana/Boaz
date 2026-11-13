#include "native_extension_store_dialogs.h"
#include "native_extension_prompt.h"
#import <AppKit/AppKit.h>
#include <map>
#include <memory>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/common/url_constants.h"
#include "chrome/grit/generated_resources.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/ui_util.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
namespace boaz {
namespace {
void UI() { CHECK_CURRENTLY_ON(content::BrowserThread::UI); CHECK([NSThread isMainThread]); }
class Dialog;
using Dialogs = std::map<Dialog*, std::shared_ptr<Dialog>>;
Dialogs& Active() { static base::NoDestructor<Dialogs> dialogs; return *dialogs; }
class Dialog final : public content::WebContentsObserver, public ProfileObserver,
                     public std::enable_shared_from_this<Dialog> {
 public:
  Dialog(content::WebContents* contents, base::OnceCallback<void(bool)> callback)
      : contents_(contents ? contents->GetWeakPtr() : base::WeakPtr<content::WebContents>()), callback_(std::move(callback)) {}
  void Start(bool friction, const std::string& name, const std::string& id,
             const std::u16string& admin_message) {
    UI();
    if (finishing_) return;
    if (!contents_) { Finish(false, false, true); return; }
    Profile* profile = Profile::FromBrowserContext(contents_->GetBrowserContext());
    NSWindow* parent = contents_->GetTopLevelNativeWindow().GetNativeNSWindow();
    if (!profile || profile->IsOffTheRecord() || profile->ShutdownStarted() ||
        !parent || !parent.isVisible || parent.attachedSheet ||
        !IsNativeExtensionPromptContext(profile, (__bridge void*)parent)) {
      Finish(false, false, true); return;
    }
    keep_alive_ = ScopedProfileKeepAlive::TryAcquire(profile, ProfileKeepAliveOrigin::kCrxInstaller);
    if (!keep_alive_) { Finish(false, false, true); return; }
    profile_observation_.Observe(profile); Observe(contents_.get()); parent_ = parent;
    std::weak_ptr<Dialog> weak = shared_from_this();
    close_observer_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:parent queue:nil usingBlock:^(NSNotification*) {
      if (auto dialog = weak.lock()) dialog->Finish(false, false, true);
    }];
    alert_ = [[NSAlert alloc] init];
    alert_.alertStyle = NSAlertStyleWarning;
    if (friction) {
      alert_.messageText = base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_EXTENSION_PROMPT_INSTALL_FRICTION_TITLE));
      alert_.informativeText = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
          IDS_EXTENSION_PROMPT_INSTALL_FRICTION_WARNING_TEXT, l10n_util::GetStringUTF16(IDS_LEARN_MORE)));
      NSButton* cancel = [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_CLOSE))];
      cancel.keyEquivalent = @"\e";
      alert_.window.defaultButtonCell = cancel.cell;
      NSButton* proceed = [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_EXTENSION_PROMPT_INSTALL_FRICTION_CONTINUE_BUTTON))];
      proceed.keyEquivalent = @"";
      [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_LEARN_MORE))];
    } else {
      alert_.messageText = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
          IDS_EXTENSION_BLOCKED_BY_POLICY_PROMPT_TITLE,
          extensions::ui_util::GetFixupExtensionNameForUIDisplay(name), base::UTF8ToUTF16(id)));
      alert_.informativeText = base::SysUTF16ToNSString(admin_message);
      [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_CLOSE))];
    }
    [alert_ beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
      if (auto dialog = weak.lock()) dialog->Finish(
          friction && response == NSAlertSecondButtonReturn,
          friction && response == NSAlertThirdButtonReturn, false);
    }];
  }
  void Finish(bool accepted, bool learn_more, bool cancelled) {
    UI();
    if (finishing_) { cancelled_ |= cancelled; return; }
    finishing_ = true; cancelled_ = cancelled;
    if (alert_.window.sheetParent) [alert_.window.sheetParent endSheet:alert_.window returnCode:NSModalResponseCancel];
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Dialog> self, bool accepted, bool learn_more) {
          self->Complete(accepted, learn_more);
        }, shared_from_this(), accepted, learn_more));
  }
 private:
  void Complete(bool accepted, bool learn_more) {
    UI();
    bool valid = !cancelled_ && contents_ && parent_ &&
        IsNativeExtensionPromptContext(Profile::FromBrowserContext(contents_->GetBrowserContext()), (__bridge void*)parent_);
    if (close_observer_) [[NSNotificationCenter defaultCenter] removeObserver:close_observer_];
    close_observer_ = nil;
    if (callback_) std::move(callback_).Run(valid && accepted);
    // The upstream cancellation callback may navigate or destroy the source.
    if (valid && learn_more && !cancelled_ && contents_ && parent_ &&
        IsNativeExtensionPromptContext(Profile::FromBrowserContext(contents_->GetBrowserContext()), (__bridge void*)parent_)) {
      auto params = content::OpenURLParams::CreateBrowserInitiated(
          GURL(chrome::kCwsEnhancedSafeBrowsingLearnMoreURL),
          WindowOpenDisposition::NEW_FOREGROUND_TAB, ui::PAGE_TRANSITION_LINK);
      contents_->OpenURL(params, {});
    }
    Observe(nullptr); profile_observation_.Reset(); keep_alive_.reset();
    Active().erase(this); NativeExtensionPromptsChanged();
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Finish(false, false, true);
  }
  void WebContentsDestroyed() override { Finish(false, false, true); Observe(nullptr); }
  void OnProfileWillBeDestroyed(Profile*) override { profile_observation_.Reset(); Finish(false, false, true); }
  base::WeakPtr<content::WebContents> contents_;
  base::OnceCallback<void(bool)> callback_;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  NSWindow* __weak parent_ = nil;
  NSAlert* __strong alert_ = nil;
  id __strong close_observer_ = nil;
  bool finishing_ = false;
  bool cancelled_ = false;
};
void Show(content::WebContents* contents, bool friction, std::string name,
          std::string id, std::u16string message, base::OnceCallback<void(bool)> callback) {
  UI();
  auto dialog = std::make_shared<Dialog>(contents, std::move(callback));
  Active().emplace(dialog.get(), dialog); NativeExtensionPromptsChanged();
  dialog->Start(friction, name, id, message);
}
}
void ShowNativeExtensionBlocked(content::WebContents* contents, std::string name,
                               std::string id, std::u16string admin_message,
                               base::OnceClosure callback) {
  Show(contents, false, std::move(name), std::move(id), std::move(admin_message),
       base::BindOnce([](base::OnceClosure done, bool) { if (done) std::move(done).Run(); }, std::move(callback)));
}
void ShowNativeExtensionFriction(content::WebContents* contents, base::OnceCallback<void(bool)> callback) {
  Show(contents, true, {}, {}, {}, std::move(callback));
}
size_t PendingNativeExtensionStoreDialogs() { UI(); return Active().size(); }
void CancelNativeExtensionStoreDialogs() {
  UI(); auto copy = Active();
  for (const auto& [key, dialog] : copy) dialog->Finish(false, false, true);
}
}
