#include "password_submission.h"
#include <limits>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/string_util.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
namespace boaz {
PasswordSubmission::PasswordSubmission(content::WebContents* contents)
    : WebContentsObserver(contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(contents);
  profile_ = contents->GetBrowserContext();
}
PasswordSubmission::~PasswordSubmission() { Close(); }
void PasswordSubmission::Post(Completion completion, Outcome outcome) {
  if (completion)
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(completion), std::move(outcome)));
}
bool PasswordSubmission::Eligible(content::RenderFrameHost* frame) const {
  return !closed_ && web_contents() && frame &&
      frame == web_contents()->GetPrimaryMainFrame() &&
      content::WebContents::FromRenderFrameHost(frame) == web_contents() &&
      frame->GetBrowserContext() == profile_ &&
      web_contents()->GetBrowserContext() == profile_ &&
      frame->IsActive() && frame->IsRenderFrameLive() &&
      !frame->GetLastCommittedOrigin().opaque();
}
bool PasswordSubmission::Valid() const {
  if (!pending_ || closed_ || !profile_ || profile_->IsOffTheRecord()) return false;
  auto* frame = pending_->document.AsRenderFrameHostIfValid();
  return pending_->epoch == epoch_ && Eligible(frame) &&
      frame == content::RenderFrameHost::FromID(pending_->frame) &&
      frame->GetLastCommittedOrigin() == pending_->origin;
}
void PasswordSubmission::Submit(content::RenderFrameHost* frame,
    Credential credential, Prompt prompt, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto reject = [&](Status status) {
    Post(std::move(completion), {status, std::nullopt, std::nullopt});
  };
  if (closed_) { reject(Status::kClosed); return; }
  if (profile_->IsOffTheRecord()) { reject(Status::kPrivate); return; }
  if (!Eligible(frame)) { reject(Status::kInvalidTarget); return; }
  constexpr size_t kLimit = 64 * 1024;
  if (!prompt || credential.username.size() > kLimit ||
      credential.password.size() > kLimit - credential.username.size() ||
      !base::IsStringUTF8(credential.username) ||
      !base::IsStringUTF8(credential.password)) {
    reject(Status::kInvalidArgument); return;
  }
  if (pending_) {
    reject(pending_->frame == frame->GetGlobalId() &&
                   pending_->origin == frame->GetLastCommittedOrigin() &&
                   pending_->credential.username == credential.username &&
                   pending_->credential.password == credential.password
               ? Status::kDuplicate : Status::kBusy);
    return;
  }
  CHECK_NE(next_id_, std::numeric_limits<uint64_t>::max());
  uint64_t id = next_id_++;
  pending_.emplace(Pending{id, epoch_, frame->GetGlobalId(), frame->GetWeakDocumentPtr(),
      frame->GetLastCommittedOrigin(), std::move(credential), std::move(completion)});
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&PasswordSubmission::Show,
          weak_factory_.GetWeakPtr(), id, std::move(prompt)));
}
void PasswordSubmission::Show(uint64_t id, Prompt prompt) {
  if (!pending_ || pending_->id != id) return;
  if (!Valid()) { Finish(Status::kInvalidTarget); return; }
  auto confirmation = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      base::BindOnce(&PasswordSubmission::Confirm, weak_factory_.GetWeakPtr(), id),
      false);
  auto origin = pending_->origin;
  auto username = pending_->credential.username;
  std::move(prompt).Run(std::move(origin), std::move(username), std::move(confirmation));
}
void PasswordSubmission::Confirm(uint64_t id, bool accepted) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_ || pending_->id != id) return;
  if (!Valid()) { Finish(Status::kInvalidTarget); return; }
  Finish(accepted ? Status::kConfirmed : Status::kDismissed);
}
void PasswordSubmission::Finish(Status status) {
  if (!pending_) return;
  auto operation = std::move(*pending_);
  pending_.reset();
  Outcome outcome{status, std::nullopt, std::nullopt};
  if (status == Status::kConfirmed) {
    outcome.credential = std::move(operation.credential);
    outcome.origin = std::move(operation.origin);
  }
  Post(std::move(operation.completion), std::move(outcome));
}
void PasswordSubmission::Cancel(Status status) {
  CHECK_NE(epoch_, std::numeric_limits<uint64_t>::max());
  ++epoch_;
  Finish(status);
}
void PasswordSubmission::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  weak_factory_.InvalidateWeakPtrs();
  Cancel(Status::kClosed);
  Observe(nullptr);
  profile_ = nullptr;
}
void PasswordSubmission::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument())
    Cancel(Status::kNavigation);
}
void PasswordSubmission::RenderFrameDeleted(content::RenderFrameHost* frame) {
  if (pending_ && pending_->frame == frame->GetGlobalId())
    Cancel(Status::kRendererFailed);
}
void PasswordSubmission::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  Cancel(Status::kRendererFailed);
}
void PasswordSubmission::WebContentsDestroyed() { Close(); }
}  // namespace boaz
