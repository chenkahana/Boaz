#include "native_external_protocol_dialog.h"
#import <AppKit/AppKit.h>
#include "base/check.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/types/optional_util.h"
#include "chrome/browser/external_protocol/external_protocol_handler.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "chrome/grit/generated_resources.h"
#include "components/prefs/pref_service.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/gfx/text_elider.h"
#include "url/gurl.h"
namespace boaz {
namespace {
// Owns itself until answered, like the upstream dialog. Accepting does what
// ExternalProtocolDialog::OnDialogAccepted does.
class Dialog final : public content::WebContentsObserver {
 public:
  Dialog(content::WebContents* contents, const GURL& url, const std::u16string& program_name,
         const std::optional<url::Origin>& origin, content::WeakDocumentPtr initiator)
      : WebContentsObserver(contents), url_(url), program_name_(program_name),
        origin_(origin), initiator_(std::move(initiator)) {}
  ~Dialog() override {
    if (close_observer_) [[NSNotificationCenter defaultCenter] removeObserver:close_observer_];
  }
  // Waits for a hidden tab to be shown, as web-modal dialogs do.
  void Start() {
    if (web_contents()->GetVisibility() != content::Visibility::HIDDEN) Show();
  }

 private:
  void Show() {
    CHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (alert_ || done_) return;
    NSWindow* parent = web_contents()->GetTopLevelNativeWindow().GetNativeNSWindow();
    if (!parent || !parent.isVisible || parent.attachedSheet) { Done(false, false); return; }
    Profile* profile = Profile::FromBrowserContext(web_contents()->GetBrowserContext());
    std::u16string program;
    gfx::ElideString(program_name_, 32, &program);
    alert_ = [[NSAlert alloc] init];
    alert_.messageText = base::SysUTF16ToNSString(
        l10n_util::GetStringFUTF16(IDS_EXTERNAL_PROTOCOL_TITLE, program));
    alert_.informativeText = base::SysUTF16ToNSString(!origin_ || origin_->opaque()
        ? l10n_util::GetStringUTF16(IDS_EXTERNAL_PROTOCOL_MESSAGE)
        : l10n_util::GetStringFUTF16(IDS_EXTERNAL_PROTOCOL_MESSAGE_WITH_INITIATING_ORIGIN,
                                     url_formatter::FormatOriginForSecurityDisplay(*origin_)));
    // Upstream defaults to Cancel; Return must not launch an app.
    NSButton* open = [alert_ addButtonWithTitle:base::SysUTF16ToNSString(
        l10n_util::GetStringFUTF16(IDS_EXTERNAL_PROTOCOL_OK_BUTTON_TEXT, program_name_))];
    open.keyEquivalent = @"";
    NSButton* cancel = [alert_ addButtonWithTitle:base::SysUTF16ToNSString(
        l10n_util::GetStringUTF16(IDS_EXTERNAL_PROTOCOL_CANCEL_BUTTON_TEXT))];
    cancel.keyEquivalent = @"\e";
    alert_.window.defaultButtonCell = nil;
    if (profile->GetPrefs()->GetBoolean(prefs::kExternalProtocolDialogShowAlwaysOpenCheckbox) &&
        ExternalProtocolHandler::MayRememberAllowDecisionsForThisOrigin(base::OptionalToPtr(origin_))) {
      alert_.showsSuppressionButton = YES;
      alert_.suppressionButton.title = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
          IDS_EXTERNAL_PROTOCOL_CHECKBOX_PER_ORIGIN_TEXT,
          url_formatter::FormatOriginForSecurityDisplay(
              *origin_, url_formatter::SchemeDisplay::OMIT_CRYPTOGRAPHIC)));
      alert_.suppressionButton.state = NSControlStateValueOff;
    }
    base::WeakPtr<Dialog> weak = weak_factory_.GetWeakPtr();
    close_observer_ = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowWillCloseNotification object:parent queue:nil
                usingBlock:^(NSNotification*) { if (weak) weak->End(); }];
    NSAlert* alert = alert_;
    [alert_ beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
      if (weak) weak->Done(response == NSAlertFirstButtonReturn,
                           alert.showsSuppressionButton &&
                               alert.suppressionButton.state == NSControlStateValueOn);
    }];
    [alert_.window makeFirstResponder:cancel];
  }
  void End() {
    if (alert_.window.sheetParent)
      [alert_.window.sheetParent endSheet:alert_.window returnCode:NSModalResponseCancel];
    Done(false, false);
  }
  void Done(bool accepted, bool remember) {
    if (done_) return;
    done_ = true;
    weak_factory_.InvalidateWeakPtrs();
    alert_ = nil;
    ExternalProtocolHandler::RecordHandleStateMetrics(
        accepted && remember, accepted ? ExternalProtocolHandler::DONT_BLOCK
                                       : ExternalProtocolHandler::BLOCK);
    if (accepted && web_contents()) {
      if (remember) {
        ExternalProtocolHandler::SetBlockState(
            url_.GetScheme(), *origin_, ExternalProtocolHandler::DONT_BLOCK,
            Profile::FromBrowserContext(web_contents()->GetBrowserContext()));
      }
      ExternalProtocolHandler::LaunchUrlWithoutSecurityCheck(url_, web_contents(), initiator_);
    }
    Observe(nullptr);
    base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::HIDDEN) Show();
  }
  void WebContentsDestroyed() override { End(); }

  const GURL url_;
  const std::u16string program_name_;
  const std::optional<url::Origin> origin_;
  const content::WeakDocumentPtr initiator_;
  NSAlert* __strong alert_ = nil;
  id __strong close_observer_ = nil;
  bool done_ = false;
  base::WeakPtrFactory<Dialog> weak_factory_{this};
};
}  // namespace

void ShowNativeExternalProtocolDialog(content::WebContents* contents, const GURL& url,
                                      const std::u16string& program_name,
                                      const std::optional<url::Origin>& initiating_origin,
                                      content::WeakDocumentPtr initiator_document) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(contents);
  (new Dialog(contents, url, program_name, initiating_origin, std::move(initiator_document)))->Start();
}
}  // namespace boaz
