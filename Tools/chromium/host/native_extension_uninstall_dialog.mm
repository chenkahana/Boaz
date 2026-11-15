#include "native_extension_uninstall_dialog.h"
#include "native_extension_prompt.h"
#import <AppKit/AppKit.h>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/grit/generated_resources.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/gfx/image/image.h"
#include "ui/strings/grit/ui_strings.h"
namespace boaz {
namespace {
class NativeUninstallDialog final : public extensions::ExtensionUninstallDialog {
 public:
  NativeUninstallDialog(Profile* profile, gfx::NativeWindow parent, Delegate* delegate)
      : ExtensionUninstallDialog(profile, parent, delegate), owner_(profile) {}
  ~NativeUninstallDialog() override {
    weak_factory_.InvalidateWeakPtrs();
    EndSheet();
  }

 private:
  void Show() override {
    CHECK_CURRENTLY_ON(content::BrowserThread::UI);
    NSWindow* window = parent().GetNativeNSWindow();
    if (!window || !window.isVisible || window.attachedSheet ||
        !IsNativeExtensionPromptContext(owner_, (__bridge void*)window)) {
      Report(CLOSE_ACTION_CANCELED);
      return;
    }
    alert_ = [[NSAlert alloc] init];
    alert_.alertStyle = NSAlertStyleWarning;
    alert_.messageText = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
        IDS_EXTENSION_PROMPT_UNINSTALL_TITLE,
        extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension()->name())));
    if (triggering_extension()) {
      alert_.informativeText = base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
          IDS_EXTENSION_PROMPT_UNINSTALL_TRIGGERED_BY_EXTENSION,
          extensions::ui_util::GetFixupExtensionNameForUIDisplay(triggering_extension()->name())));
    }
    if (!icon().isNull()) alert_.icon = gfx::Image(icon()).ToNSImage();
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(
        l10n_util::GetStringUTF16(IDS_EXTENSION_PROMPT_UNINSTALL_BUTTON))];
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(IDS_APP_CANCEL))]
        .keyEquivalent = @"\e";
    if (ShouldShowCheckbox()) {
      alert_.showsSuppressionButton = YES;
      alert_.suppressionButton.title = base::SysUTF16ToNSString(triggering_extension()
          ? l10n_util::GetStringFUTF16(IDS_EXTENSION_PROMPT_UNINSTALL_REPORT_ABUSE_FROM_EXTENSION,
                extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension()->name()))
          : l10n_util::GetStringUTF16(IDS_EXTENSION_PROMPT_UNINSTALL_REPORT_ABUSE));
      alert_.suppressionButton.state = NSControlStateValueOff;
    }
    base::WeakPtr<NativeUninstallDialog> weak = weak_factory_.GetWeakPtr();
    NSAlert* alert = alert_;
    [alert_ beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      const bool remove = response == NSAlertFirstButtonReturn;
      const bool report = remove && alert.showsSuppressionButton &&
          alert.suppressionButton.state == NSControlStateValueOn;
      // The delegate may delete this dialog; report once AppKit has finished the sheet.
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, base::BindOnce(
          &NativeUninstallDialog::Report, weak,
          remove ? (report ? CLOSE_ACTION_UNINSTALL_AND_CHECKBOX_CHECKED : CLOSE_ACTION_UNINSTALL)
                 : CLOSE_ACTION_CANCELED));
    }];
  }
  void Close() override { EndSheet(); }
  void EndSheet() {
    if (alert_.window.sheetParent) {
      [alert_.window.sheetParent endSheet:alert_.window returnCode:NSModalResponseCancel];
    }
  }
  void Report(CloseAction action) {
    if (reported_) return;
    reported_ = true;
    alert_ = nil;
    OnDialogClosed(action);
  }

  // Read only in Show(); the base cancels the dialog when the profile goes away.
  raw_ptr<Profile> owner_;
  NSAlert* __strong alert_ = nil;
  bool reported_ = false;
  base::WeakPtrFactory<NativeUninstallDialog> weak_factory_{this};
};
}  // namespace

std::unique_ptr<extensions::ExtensionUninstallDialog> CreateNativeExtensionUninstallDialog(
    Profile* profile, gfx::NativeWindow parent, extensions::ExtensionUninstallDialog::Delegate* delegate) {
  return std::make_unique<NativeUninstallDialog>(profile, parent, delegate);
}
}  // namespace boaz
