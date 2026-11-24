#include "page_mhtml.h"
#include <limits>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/mhtml_generation_params.h"
#include "url/origin.h"
namespace boaz {
PageMHTML::PageMHTML(content::WebContents* contents) : WebContentsObserver(contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(contents);
}
PageMHTML::~PageMHTML() { Close(); }
bool PageMHTML::Valid() const {
  if (!pending_ || closed_ || !web_contents() || pending_->navigation != navigation_) return false;
  auto* frame = pending_->document.AsRenderFrameHostIfValid();
  return frame && frame == web_contents()->GetPrimaryMainFrame() &&
      frame->GetGlobalId() == pending_->frame && frame->IsActive() && frame->IsRenderFrameLive();
}
BoazHostResult PageMHTML::Save(uint64_t request, const base::FilePath& path, Completion completion) {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) return BOAZ_HOST_WRONG_THREAD;
  if (!request || !completion || !path.IsAbsolute() || path.Extension() != ".mhtml" ||
      path.ReferencesParent()) return BOAZ_HOST_INVALID_ARGUMENT;
  if (closed_ || !web_contents()) return BOAZ_HOST_CLOSING;
  if (pending_) return BOAZ_HOST_UNAVAILABLE;
  auto* frame = web_contents()->GetPrimaryMainFrame();
  if (!frame || !frame->IsActive() || !frame->IsRenderFrameLive() ||
      !frame->GetLastCommittedURL().SchemeIsHTTPOrHTTPS() ||
      frame->GetLastCommittedOrigin().opaque()) return BOAZ_HOST_UNAVAILABLE;
  CHECK_LT(next_serial_, std::numeric_limits<uint64_t>::max());
  const auto serial = next_serial_++;
  pending_ = std::make_unique<Pending>();
  pending_->serial = serial;
  pending_->navigation = navigation_;
  pending_->document = frame->GetWeakDocumentPtr();
  pending_->frame = frame->GetGlobalId();
  pending_->completion = std::move(completion);
  pending_->timer.Start(FROM_HERE, base::Seconds(30),
      base::BindOnce(&PageMHTML::Finish, weak_.GetWeakPtr(), Status::kTimeout, int64_t{0}));
  web_contents()->GenerateMHTML(content::MHTMLGenerationParams(path),
      base::BindOnce(&PageMHTML::Completed, weak_.GetWeakPtr(), serial));
  return BOAZ_HOST_OK;
}
void PageMHTML::Completed(uint64_t serial, int64_t size) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_ || pending_->serial != serial) return;
  if (!Valid()) { Finish(Status::kInvalid); return; }
  Finish(size > 0 ? Status::kSuccess : Status::kFailed, size > 0 ? size : 0);
}
void PageMHTML::Finish(Status status, int64_t size) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_) return;
  auto completion = std::move(pending_->completion);
  pending_.reset();
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(completion), Outcome{status, size}));
}
void PageMHTML::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  Finish(Status::kClosed);
  weak_.InvalidateWeakPtrs();
  Observe(nullptr);
}
void PageMHTML::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
    CHECK_LT(navigation_, std::numeric_limits<uint64_t>::max());
    ++navigation_;
    Finish(Status::kNavigation);
  }
}
void PageMHTML::RenderFrameDeleted(content::RenderFrameHost* frame) {
  if (pending_ && pending_->frame == frame->GetGlobalId()) Finish(Status::kInvalid);
}
void PageMHTML::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) { Finish(Status::kCrash); }
void PageMHTML::WebContentsDestroyed() { Close(); }
}
