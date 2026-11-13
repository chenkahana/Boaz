#import <AppKit/AppKit.h>
#include "native_permission_prompt.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_util.h"
#include "components/permissions/request_type.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "url/origin.h"

namespace boaz {
namespace {
class NativePermissionPrompt final : public permissions::PermissionPrompt {
 public:
  explicit NativePermissionPrompt(Delegate* delegate)
      : delegate_(delegate->GetWeakPtr()) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&NativePermissionPrompt::Show,
                                 weak_factory_.GetWeakPtr()));
  }
  ~NativePermissionPrompt() override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    weak_factory_.InvalidateWeakPtrs();
    if (alert_.window.sheetParent)
      [alert_.window.sheetParent endSheet:alert_.window
                             returnCode:NSModalResponseAbort];
    [alert_.window orderOut:nil];
  }
  bool UpdateAnchor() override {
    return delegate_ && (!alert_ || alert_.window.sheetParent == Window());
  }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return TabSwitchingBehavior::kDestroyPromptButKeepRequestPending;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition() const override {
    return alert_ ? permissions::PermissionPromptDisposition::CUSTOM_MODAL_DIALOG
                  : permissions::PermissionPromptDisposition::NONE_VISIBLE;
  }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    if (!alert_ || !alert_.window.visible) return std::nullopt;
    return gfx::ScreenRectFromNSRect(alert_.window.frame);
  }
  std::vector<permissions::ElementAnchoredBubbleVariant>
  GetPromptVariants() const override { return {}; }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override { return std::nullopt; }

 private:
  NSWindow* Window() const {
    auto* contents = delegate_ ? delegate_->GetAssociatedWebContents() : nullptr;
    return contents ? contents->GetTopLevelNativeWindow().GetNativeNSWindow() : nil;
  }
  enum class Decision { kAllow, kOnce, kDeny, kDismiss, kIgnore };
  void Finish(Decision decision) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (completed_ || !delegate_)
      return;
    completed_ = true;
    auto delegate = delegate_;
    switch (decision) {
      case Decision::kAllow: delegate->Accept(std::monostate()); return;
      case Decision::kOnce: delegate->AcceptThisTime(std::monostate()); return;
      case Decision::kDeny: delegate->Deny(std::monostate()); return;
      case Decision::kDismiss: delegate->Dismiss(std::monostate()); return;
      case Decision::kIgnore: delegate->Ignore(std::monostate()); return;
    }
  }
  void Show() {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    CHECK([NSThread isMainThread]);
    if (!delegate_ || delegate_->GetCurrentPrompt() != this)
      return;
    NSWindow* window = Window();
    if (!window || window.attachedSheet ||
        delegate_->ShouldCurrentRequestUseQuietUI() ||
        delegate_->ShouldDropCurrentRequestIfCannotShowQuietly() ||
        delegate_->GetGeolocationPromptType().has_value()) {
      Finish(Decision::kIgnore);
      return;
    }
    const auto requesting = url::Origin::Create(delegate_->GetRequestingOrigin());
    const auto embedding = url::Origin::Create(delegate_->GetEmbeddingOrigin());
    if (requesting.opaque() || embedding.opaque() || delegate_->Requests().empty()) {
      Finish(Decision::kIgnore);
      return;
    }
    NSMutableArray<NSString*>* labels = [NSMutableArray array];
    bool temporary = true;
    for (const auto& request : delegate_->Requests()) {
      const auto type = request->request_type();
      if (request->IsEmbeddedPermissionElementInitiated() ||
          (type != permissions::RequestType::kCameraStream &&
           type != permissions::RequestType::kMicStream &&
           type != permissions::RequestType::kNotifications)) {
        LOG(WARNING) << "Boaz native permission unsupported request type: "
                     << permissions::PermissionKeyForRequestType(type);
        Finish(Decision::kIgnore);
        return;
      }
      [labels addObject:base::SysUTF16ToNSString(request->GetMessageTextFragment())];
      const auto setting = permissions::RequestTypeToContentSettingsType(type);
      temporary &= setting.has_value() &&
          permissions::PermissionUtil::DoesSupportTemporaryGrants(*setting);
    }
    alert_ = [[NSAlert alloc] init];
    alert_.messageText = @"Website permission";
    alert_.informativeText = [NSString stringWithFormat:
        @"Requesting origin: %@\nEmbedding origin: %@\n\n%@",
        base::SysUTF8ToNSString(requesting.Serialize()),
        base::SysUTF8ToNSString(embedding.Serialize()),
        [labels componentsJoinedByString:@"\n"]];
    [alert_ addButtonWithTitle:@"Not Now"];
    [alert_ addButtonWithTitle:@"Block"];
    [alert_ addButtonWithTitle:@"Allow"];
    if (temporary)
      [alert_ addButtonWithTitle:@"Allow Once"];
    auto weak = weak_factory_.GetWeakPtr();
    [alert_ beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
      if (!weak)
        return;
      Decision decision = Decision::kDismiss;
      if (result == NSAlertSecondButtonReturn) decision = Decision::kDeny;
      if (result == NSAlertThirdButtonReturn) decision = Decision::kAllow;
      if (temporary && result == NSAlertFirstButtonReturn + 3)
        decision = Decision::kOnce;
      weak->Finish(decision);
    }];
  }
  base::WeakPtr<Delegate> delegate_;
  NSAlert* __strong alert_ = nil;
  bool completed_ = false;
  base::WeakPtrFactory<NativePermissionPrompt> weak_factory_{this};
};
}  // namespace
std::unique_ptr<permissions::PermissionPrompt> CreateNativePermissionPrompt(
    content::WebContents* contents, permissions::PermissionPrompt::Delegate* delegate) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK([NSThread isMainThread]);
  CHECK(contents);
  CHECK(delegate);
  CHECK_EQ(contents, delegate->GetAssociatedWebContents());
  return std::make_unique<NativePermissionPrompt>(delegate);
}
}  // namespace boaz
