#import <AppKit/AppKit.h>
#include "native_http_warning.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/gfx/native_ui_types.h"
namespace boaz {
namespace {
using Reason = security_interstitials::https_only_mode::InterstitialReason;
NSString* Text(int id) { return base::SysUTF16ToNSString(l10n_util::GetStringUTF16(id)); }
NSString* Description(Reason reason) {
  int id = 0;
  switch (reason) {
    case Reason::kSiteEngagementHeuristic: id = IDS_ABH_PROMPT_SITE_ENGAGEMENT_PRIMARY_PARAGRAPH; break;
    case Reason::kAdvancedProtection: id = IDS_ABH_PROMPT_ADVANCED_PROTECTION_PRIMARY_PARAGRAPH; break;
    case Reason::kTypicallySecureUserHeuristic: id = IDS_ABH_PROMPT_TYPICALLY_SECURE_BROWSING_PRIMARY_PARAGRAPH; break;
    case Reason::kIncognito: id = IDS_ABH_PROMPT_INCOGNITO_PRIMARY_PARAGRAPH; break;
    case Reason::kIsolatedMode: id = IDS_ABH_PROMPT_ISOLATED_MODE_PRIMARY_PARAGRAPH; break;
    case Reason::kPref:
    case Reason::kBalanced: id = IDS_ABH_PROMPT_SECONDARY_TEXT; break;
    default: return nil;
  }
  NSString* text = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
      id, l10n_util::GetStringUTF16(IDS_ABH_PROMPT_LEARN_MORE_LINK)));
  if (reason == Reason::kPref || reason == Reason::kBalanced)
    return [NSString stringWithFormat:@"• %@\n• %@\n\n%@",
        Text(IDS_ABH_PROMPT_BALANCED_MODE_FIRST_ITEM_TEXT),
        Text(IDS_ABH_PROMPT_BALANCED_MODE_SECOND_ITEM_TEXT), text];
  return text;
}
class Warning final : public NativeHttpWarning {
 public:
  Warning(content::WebContents* contents, Reason reason,
          base::OnceCallback<void(HttpWarningDecision)> callback)
      : contents_(contents->GetWeakPtr()), reason_(reason), callback_(std::move(callback)) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&Warning::Show, weak_factory_.GetWeakPtr()));
  }
  ~Warning() override {
    CHECK_CURRENTLY_ON(content::BrowserThread::UI);
    weak_factory_.InvalidateWeakPtrs();
    if (alert_.window.sheetParent)
      [alert_.window.sheetParent endSheet:alert_.window returnCode:NSModalResponseAbort];
    [alert_.window orderOut:nil];
  }
 private:
  void Finish(HttpWarningDecision decision) {
    if (!callback_) return;
    auto callback = std::move(callback_);
    std::move(callback).Run(decision);
  }
  void Show() {
    CHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK([NSThread isMainThread]);
    NSWindow* parent = contents_ ? contents_->GetTopLevelNativeWindow().GetNativeNSWindow() : nil;
    NSString* description = Description(reason_);
    if (!contents_ || contents_->GetVisibility() != content::Visibility::VISIBLE ||
        !parent || !parent.isVisible || parent.attachedSheet || !description) {
      Finish(HttpWarningDecision::kGoBack);
      return;
    }
    alert_ = [[NSAlert alloc] init];
    alert_.alertStyle = NSAlertStyleWarning;
    alert_.messageText = Text(IDS_ABH_PROMPT_TITLE);
    alert_.informativeText = description;
    NSButton* back = [alert_ addButtonWithTitle:Text(IDS_HTTPS_ONLY_MODE_BACK_BUTTON)];
    back.keyEquivalent = @"\e";
    NSButton* proceed = [alert_ addButtonWithTitle:Text(IDS_HTTPS_ONLY_MODE_SUBMIT_BUTTON)];
    proceed.keyEquivalent = @"";
    [alert_ addButtonWithTitle:Text(IDS_ABH_PROMPT_LEARN_MORE_LINK)];
    alert_.window.defaultButtonCell = nil;
    auto weak = weak_factory_.GetWeakPtr();
    [alert_ beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
      if (!weak) return;
      weak->Finish(response == NSAlertSecondButtonReturn ? HttpWarningDecision::kContinue :
                   response == NSAlertThirdButtonReturn ? HttpWarningDecision::kLearnMore :
                   HttpWarningDecision::kGoBack);
    }];
    [alert_.window makeFirstResponder:back];
  }
  base::WeakPtr<content::WebContents> contents_;
  Reason reason_;
  base::OnceCallback<void(HttpWarningDecision)> callback_;
  NSAlert* __strong alert_ = nil;
  base::WeakPtrFactory<Warning> weak_factory_{this};
};
}
std::unique_ptr<NativeHttpWarning> ShowNativeHttpWarning(
    content::WebContents* contents, Reason reason,
    base::OnceCallback<void(HttpWarningDecision)> callback) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(contents);
  return std::make_unique<Warning>(contents, reason, std::move(callback));
}
}
