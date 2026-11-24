#ifndef BOAZ_CHROMIUM_PAGE_MHTML_H_
#define BOAZ_CHROMIUM_PAGE_MHTML_H_
#include <memory>
#include "boaz_host.h"
#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
namespace boaz {
// Writes the primary document, as presented, to an MHTML file: the last look of a tab Boaz is about to close.
class PageMHTML final : public content::WebContentsObserver {
 public:
  enum class Status { kSuccess, kInvalid, kNavigation, kClosed, kCrash, kTimeout, kFailed };
  struct Outcome { Status status; int64_t size; };
  using Completion = base::OnceCallback<void(Outcome)>;
  explicit PageMHTML(content::WebContents* contents);
  ~PageMHTML() override;
  BoazHostResult Save(uint64_t request, const base::FilePath& path, Completion completion);
  void Close();
 private:
  struct Pending {
    uint64_t serial;
    uint64_t navigation;
    content::WeakDocumentPtr document;
    content::GlobalRenderFrameHostId frame;
    Completion completion;
    base::OneShotTimer timer;
  };
  bool Valid() const;
  void Completed(uint64_t serial, int64_t size);
  void Finish(Status status, int64_t size = 0);
  void DidStartNavigation(content::NavigationHandle*) override;
  void RenderFrameDeleted(content::RenderFrameHost*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  std::unique_ptr<Pending> pending_;
  uint64_t next_serial_ = 1;
  uint64_t navigation_ = 1;
  bool closed_ = false;
  base::WeakPtrFactory<PageMHTML> weak_{this};
};
}
#endif
