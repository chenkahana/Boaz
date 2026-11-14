#ifndef BOAZ_CHROMIUM_PAGE_PDF_H_
#define BOAZ_CHROMIUM_PAGE_PDF_H_
#include <memory>
#include <vector>
#include "boaz_host.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
namespace boaz {
class PagePDF final : public content::WebContentsObserver {
 public:
  enum class Status { kSuccess, kInvalid, kNavigation, kClosed, kCrash,
                      kTimeout, kBusy, kTooLarge, kFailed, kCancelled };
  struct Outcome { Status status; std::vector<uint8_t> bytes; };
  using Completion = base::OnceCallback<void(Outcome)>;
  explicit PagePDF(content::WebContents* contents);
  ~PagePDF() override;
  BoazHostResult Capture(uint64_t request, Completion completion);
  BoazHostResult Cancel(uint64_t request);
  void Close();
 private:
  struct Pending {
    uint64_t request;
    uint64_t serial;
    uint64_t navigation;
    content::WeakDocumentPtr document;
    content::GlobalRenderFrameHostId frame;
    Completion completion;
    base::OneShotTimer timer;
  };
  bool Valid() const;
  void Completed(uint64_t serial, Outcome outcome);
  void Finish(Status status, std::vector<uint8_t> bytes = {});
  void DidStartNavigation(content::NavigationHandle*) override;
  void RenderFrameDeleted(content::RenderFrameHost*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  std::unique_ptr<Pending> pending_;
  uint64_t next_serial_ = 1;
  uint64_t navigation_ = 1;
  bool closed_ = false;
  base::WeakPtrFactory<PagePDF> weak_{this};
};
}
#endif
