#include "native_password_submission.h"
#include "bootstrap.h"
#include "base/strings/utf_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "url/origin.h"
namespace boaz {
namespace {
bool Owned(content::WebContents* contents) {
  return NativeHostEnabled() && contents && !contents->IsBeingDestroyed() &&
      !contents->GetBrowserContext()->IsOffTheRecord() &&
      IsNativeHostBrowser(GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents));
}
class SubmissionProof final : public content::WebContentsObserver,
                              public content::WebContentsUserData<SubmissionProof> {
 public:
  base::UnguessableToken Capture(content::RenderFrameHost* frame) {
    token_ = {};
    if (!Owned(web_contents()) || !frame || !frame->IsActive() || !frame->IsRenderFrameLive() ||
        content::WebContents::FromRenderFrameHost(frame) != web_contents() ||
        frame->GetBrowserContext() != web_contents()->GetBrowserContext() ||
        frame->IsNestedWithinFencedFrame() || frame->GetLastCommittedOrigin().opaque() ||
        !frame->GetLastCommittedURL().SchemeIsHTTPOrHTTPS()) return {};
    auto* root = frame;
    while (root->GetParent()) root = root->GetParent();
    if (root != web_contents()->GetPrimaryMainFrame()) return {};
    origin_ = frame->GetLastCommittedOrigin();
    expires_ = base::TimeTicks::Now() + base::Minutes(5);
    token_ = base::UnguessableToken::Create();
    return token_;
  }
  void Commit(const base::UnguessableToken& token,
              const std::u16string& username, const std::u16string& password) {
    if (token.is_empty() || token != token_) return;
    token_ = {};
    if (!Owned(web_contents()) || base::TimeTicks::Now() > expires_ ||
        username.size() > 16384 || password.empty() || password.size() > 16384 ||
        web_contents()->GetController().GetPendingEntry()) return;
    auto* frame = web_contents()->GetPrimaryMainFrame();
    if (!frame || !frame->IsActive() || !frame->IsRenderFrameLive() ||
        frame->GetLastCommittedOrigin().opaque() || !frame->GetLastCommittedURL().SchemeIsHTTPOrHTTPS()) return;
    auto user = base::UTF16ToUTF8(username);
    auto secret = base::UTF16ToUTF8(password);
    if (user.size() + secret.size() > 65536) return;
    ReportNativePasswordSubmission(web_contents(), origin_.Serialize(), std::move(user), std::move(secret));
  }
 private:
  friend class content::WebContentsUserData<SubmissionProof>;
  explicit SubmissionProof(content::WebContents* contents)
      : content::WebContentsObserver(contents), content::WebContentsUserData<SubmissionProof>(*contents) {}
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override { token_ = {}; }
  void WebContentsDestroyed() override { token_ = {}; }
  base::UnguessableToken token_;
  url::Origin origin_;
  base::TimeTicks expires_;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(SubmissionProof);
}
base::UnguessableToken CaptureNativePasswordSubmission(
    content::WebContents* contents, content::RenderFrameHost* frame) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!Owned(contents)) return {};
  SubmissionProof::CreateForWebContents(contents);
  return SubmissionProof::FromWebContents(contents)->Capture(frame);
}
void CommitNativePasswordSubmission(content::WebContents* contents,
    const base::UnguessableToken& token, const std::u16string& username, const std::u16string& password) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!Owned(contents)) return;
  if (auto* proof = SubmissionProof::FromWebContents(contents)) proof->Commit(token, username, password);
}
}
