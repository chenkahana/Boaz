#ifndef BOAZ_CHROMIUM_VISIBLE_PAGE_CAPTURE_H_
#define BOAZ_CHROMIUM_VISIBLE_PAGE_CAPTURE_H_
#include <memory>
#include <vector>
#include "boaz_host.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/web_contents_observer.h"
#include "third_party/skia/include/core/SkBitmap.h"
namespace boaz {
class VisiblePageCapture final : public content::WebContentsObserver {
 public:
  struct Outcome { BoazHostCaptureStatus status; std::vector<uint8_t> png; };
  using Completion = base::OnceCallback<void(Outcome)>;
  explicit VisiblePageCapture(content::WebContents* contents);
  ~VisiblePageCapture() override;
  BoazHostResult Capture(uint64_t request, int width, int height, Completion completion);
  BoazHostResult Cancel(uint64_t request);
  void Close();
 private:
  struct Pending {
    uint64_t request;
    uint64_t serial;
    content::WeakDocumentPtr document;
    content::GlobalRenderFrameHostId frame;
    Completion completion;
    base::OneShotTimer timer;
  };
  bool Valid() const;
  void Copied(uint64_t serial, BoazHostCaptureStatus status, SkBitmap bitmap);
  void Encoded(uint64_t serial, Outcome outcome);
  void Finish(BoazHostCaptureStatus status, std::vector<uint8_t> png = {});
  void DidStartNavigation(content::NavigationHandle*) override;
  void RenderFrameDeleted(content::RenderFrameHost*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  std::unique_ptr<Pending> pending_;
  uint64_t next_serial_ = 1;
  bool closed_ = false;
  base::WeakPtrFactory<VisiblePageCapture> weak_factory_{this};
};
}
#endif
