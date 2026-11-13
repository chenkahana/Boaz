#include "trusted_execution.h"
#include <limits>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"

namespace boaz {
TrustedExecution::TrustedExecution(content::WebContents* contents)
    : WebContentsObserver(contents), profile_(contents->GetBrowserContext()) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}
TrustedExecution::~TrustedExecution() {
  Close();
}
std::optional<TrustedExecution::Target> TrustedExecution::CaptureTarget() const {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_ || !web_contents()) return std::nullopt;
  auto* frame = web_contents()->GetPrimaryMainFrame();
  if (!frame) return std::nullopt;
  Target target{frame->GetGlobalId(), frame->GetWeakDocumentPtr(),
                frame->GetLastCommittedOrigin(), epoch_};
  return Validate(target) ? std::make_optional(std::move(target)) : std::nullopt;
}
bool TrustedExecution::Validate(const Target& target) const {
  auto* frame = target.document.AsRenderFrameHostIfValid();
  return !closed_ && web_contents() && target.epoch == epoch_ && frame &&
      frame == content::RenderFrameHost::FromID(target.frame) &&
      frame == web_contents()->GetPrimaryMainFrame() &&
      content::WebContents::FromRenderFrameHost(frame) == web_contents() &&
      frame->GetBrowserContext() == profile_ &&
      web_contents()->GetBrowserContext() == profile_ && frame->IsRenderFrameLive() &&
      frame->IsActive() && !target.origin.opaque() &&
      frame->GetLastCommittedOrigin() == target.origin;
}
void TrustedExecution::Post(Completion completion, Outcome outcome) {
  if (completion)
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(completion), std::move(outcome)));
}
void TrustedExecution::Execute(Target target, std::u16string source,
                               base::DictValue arguments, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Post(std::move(completion), {Status::kClosed, {}}); return; }
  if (!Validate(target)) {
    Post(std::move(completion), {Status::kInvalidTarget, {}}); return;
  }
  if (pending_.size() >= 64) {
    Post(std::move(completion), {Status::kBusy, {}}); return;
  }
  constexpr size_t kLimit = 64 * 1024;
  auto json = base::WriteJson(arguments);
  if (source.empty() || source.size() > kLimit / sizeof(char16_t) ||
      !json || json->size() > kLimit) {
    Post(std::move(completion), {Status::kInvalidArgument, {}}); return;
  }
  // JSON.parse preserves data semantics even for keys such as __proto__.
  auto quoted = base::WriteJson(base::Value(*json));
  if (!quoted) {
    Post(std::move(completion), {Status::kInvalidArgument, {}}); return;
  }
  std::u16string script = u"(" + source + u")(JSON.parse(" +
                         base::UTF8ToUTF16(*quoted) + u"))";
  CHECK_NE(next_id_, std::numeric_limits<uint64_t>::max());
  const uint64_t id = next_id_++;
  pending_.emplace(id, Pending{target, std::move(completion)});
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE, base::BindOnce(&TrustedExecution::Finish,
          weak_factory_.GetWeakPtr(), id, Status::kTimeout, base::Value()),
      base::Seconds(5));
  auto result = mojo::WrapCallbackWithDropHandler(
      base::BindOnce(&TrustedExecution::Result, weak_factory_.GetWeakPtr(), id),
      base::BindOnce(&TrustedExecution::Finish, weak_factory_.GetWeakPtr(),
                     id, Status::kRendererFailed, base::Value()));
  target.document.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
      script, std::move(result), ISOLATED_WORLD_ID_BOAZ);
}
void TrustedExecution::Result(uint64_t id, base::Value result) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto it = pending_.find(id);
  if (it == pending_.end()) return;
  Finish(id, Validate(it->second.target) ? Status::kSuccess : Status::kInvalidTarget,
         std::move(result));
}
void TrustedExecution::Finish(uint64_t id, Status status, base::Value result) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto it = pending_.find(id);
  if (it == pending_.end()) return;
  auto completion = std::move(it->second.completion);
  pending_.erase(it);
  if (status != Status::kSuccess) result = base::Value();
  Post(std::move(completion), {status, std::move(result)});
}
void TrustedExecution::Cancel(Status status) {
  CHECK_NE(epoch_, std::numeric_limits<uint64_t>::max());
  ++epoch_;
  auto pending = std::move(pending_);
  pending_.clear();
  for (auto& [id, operation] : pending)
    Post(std::move(operation.completion), {status, {}});
}
void TrustedExecution::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  weak_factory_.InvalidateWeakPtrs();
  Cancel(Status::kClosed);
  Observe(nullptr);
}
void TrustedExecution::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument())
    Cancel(Status::kNavigation);
}
void TrustedExecution::RenderFrameDeleted(content::RenderFrameHost* frame) {
  for (const auto& [id, operation] : pending_) {
    if (operation.target.frame == frame->GetGlobalId()) {
      Cancel(Status::kRendererFailed);
      return;
    }
  }
}
void TrustedExecution::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  Cancel(Status::kRendererFailed);
}
void TrustedExecution::WebContentsDestroyed() { Close(); }
}  // namespace boaz
