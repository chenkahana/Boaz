#include "visible_page_capture.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "base/task/thread_pool.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/codec/png_codec.h"
namespace boaz {
namespace {
constexpr int kMaxDimension = 2048;
constexpr int64_t kMaxPixels = 2 * 1024 * 1024;
constexpr size_t kMaxBytes = 8 * 1024 * 1024;
bool Bounded(const SkBitmap& bitmap) {
  return !bitmap.drawsNothing() && bitmap.width() > 0 && bitmap.height() > 0 &&
      bitmap.width() <= kMaxDimension && bitmap.height() <= kMaxDimension &&
      int64_t{bitmap.width()} * bitmap.height() <= kMaxPixels;
}
}
VisiblePageCapture::VisiblePageCapture(content::WebContents* contents)
    : WebContentsObserver(contents) { DCHECK_CURRENTLY_ON(content::BrowserThread::UI); CHECK(contents); }
VisiblePageCapture::~VisiblePageCapture() { Close(); }
bool VisiblePageCapture::Valid() const {
  if (!pending_ || closed_ || !web_contents()) return false;
  auto* frame = pending_->document.AsRenderFrameHostIfValid();
  return frame && frame == web_contents()->GetPrimaryMainFrame() &&
      frame->IsActive() && frame->IsRenderFrameLive() &&
      content::WebContents::FromRenderFrameHost(frame) == web_contents();
}
BoazHostResult VisiblePageCapture::Capture(uint64_t request, int width, int height,
                                         Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!request || !completion || width <= 0 || height <= 0 ||
      width > kMaxDimension || height > kMaxDimension ||
      int64_t{width} * height > kMaxPixels) return BOAZ_HOST_INVALID_ARGUMENT;
  if (closed_ || !web_contents()) return BOAZ_HOST_CLOSING;
  if (pending_) return BOAZ_HOST_UNAVAILABLE;
  auto* frame = web_contents()->GetPrimaryMainFrame();
  auto* view = web_contents()->GetRenderWidgetHostView();
  if (!frame || !frame->IsActive() || !frame->IsRenderFrameLive() || !view || !view->IsShowing() ||
      web_contents()->GetVisibility() != content::Visibility::VISIBLE)
    return BOAZ_HOST_UNAVAILABLE;
  const auto size = view->GetViewBounds().size();
  if (size.IsEmpty()) return BOAZ_HOST_UNAVAILABLE;
  const double scale = std::min(static_cast<double>(width) / size.width(),
                                static_cast<double>(height) / size.height());
  const gfx::Size output(std::max(1, static_cast<int>(std::floor(size.width() * scale))),
                         std::max(1, static_cast<int>(std::floor(size.height() * scale))));
  CHECK_LT(next_serial_, std::numeric_limits<uint64_t>::max());
  const auto serial = next_serial_++;
  pending_ = std::make_unique<Pending>();
  pending_->request = request;
  pending_->serial = serial;
  pending_->document = frame->GetWeakDocumentPtr();
  pending_->frame = frame->GetGlobalId();
  pending_->completion = std::move(completion);
  pending_->timer.Start(FROM_HERE, base::Seconds(5),
      base::BindOnce(&VisiblePageCapture::Finish, weak_factory_.GetWeakPtr(),
                     BOAZ_CAPTURE_TIMEOUT, std::vector<uint8_t>()));
  view->CopyFromSurface(gfx::Rect(), output, base::Seconds(4),
      base::BindOnce([](scoped_refptr<base::SingleThreadTaskRunner> runner,
                       base::WeakPtr<VisiblePageCapture> owner, uint64_t serial,
                       const content::CopyFromSurfaceResult& result) {
        BoazHostCaptureStatus status = BOAZ_CAPTURE_FAILED;
        SkBitmap bitmap;
        if (result.has_value()) {
          bitmap = result->bitmap;
          status = bitmap.drawsNothing() ? BOAZ_CAPTURE_FAILED
              : Bounded(bitmap) ? BOAZ_CAPTURE_SUCCESS : BOAZ_CAPTURE_TOO_LARGE;
        } else if (result.error() == content::CopyFromSurfaceError::kTimeout) {
          status = BOAZ_CAPTURE_TIMEOUT;
        }
        runner->PostTask(FROM_HERE, base::BindOnce(&VisiblePageCapture::Copied,
            owner, serial, status, std::move(bitmap)));
      }, base::SingleThreadTaskRunner::GetCurrentDefault(),
      weak_factory_.GetWeakPtr(), serial));
  return BOAZ_HOST_OK;
}
void VisiblePageCapture::Copied(uint64_t serial, BoazHostCaptureStatus status, SkBitmap bitmap) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_ || pending_->serial != serial) return;
  if (!Valid()) { Finish(BOAZ_CAPTURE_INVALID_TARGET); return; }
  if (status != BOAZ_CAPTURE_SUCCESS) { Finish(status); return; }
  base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
      {base::TaskPriority::USER_VISIBLE},
      base::BindOnce([](SkBitmap bitmap) -> Outcome {
        auto encoded = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
        if (!encoded) return {BOAZ_CAPTURE_FAILED, {}};
        if (encoded->size() > kMaxBytes) return {BOAZ_CAPTURE_TOO_LARGE, {}};
        return {BOAZ_CAPTURE_SUCCESS, std::move(*encoded)};
      }, std::move(bitmap)),
      base::BindOnce(&VisiblePageCapture::Encoded, weak_factory_.GetWeakPtr(), serial));
}
void VisiblePageCapture::Encoded(uint64_t serial, Outcome outcome) {
  if (!pending_ || pending_->serial != serial) return;
  if (!Valid()) { Finish(BOAZ_CAPTURE_INVALID_TARGET); return; }
  Finish(outcome.status, std::move(outcome.png));
}
void VisiblePageCapture::Finish(BoazHostCaptureStatus status, std::vector<uint8_t> png) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_) return;
  auto completion = std::move(pending_->completion);
  pending_.reset();
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(completion), Outcome{status, std::move(png)}));
}
BoazHostResult VisiblePageCapture::Cancel(uint64_t request) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!request || !pending_ || pending_->request != request) return BOAZ_HOST_INVALID_ARGUMENT;
  Finish(BOAZ_CAPTURE_CANCELLED);
  return BOAZ_HOST_OK;
}
void VisiblePageCapture::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  Finish(BOAZ_CAPTURE_CLOSED);
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
}
void VisiblePageCapture::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Finish(BOAZ_CAPTURE_NAVIGATION);
}
void VisiblePageCapture::RenderFrameDeleted(content::RenderFrameHost* frame) {
  if (pending_ && pending_->frame == frame->GetGlobalId()) Finish(BOAZ_CAPTURE_INVALID_TARGET);
}
void VisiblePageCapture::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  Finish(BOAZ_CAPTURE_RENDERER_FAILED);
}
void VisiblePageCapture::WebContentsDestroyed() { Close(); }
}
