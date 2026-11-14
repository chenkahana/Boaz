#include "page_pdf.h"
#include <limits>
#include <optional>
#include <utility>
#include <variant>
#include "base/check.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/ref_counted_memory.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "printing/buildflags/buildflags.h"
#include "url/origin.h"
#if BUILDFLAG(ENABLE_PRINTING)
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/printing/browser/print_to_pdf/pdf_print_utils.h"
#include "components/printing/browser/print_to_pdf/pdf_print_job.h"
#include "components/printing/common/print.mojom.h"
#if BUILDFLAG(ENABLE_PRINT_PREVIEW)
#include "chrome/browser/printing/print_view_manager.h"
using ActivePrintManager = printing::PrintViewManager;
#else
#include "chrome/browser/printing/print_view_manager_basic.h"
using ActivePrintManager = printing::PrintViewManagerBasic;
#endif
#endif
namespace boaz {
PagePDF::PagePDF(content::WebContents* contents) : WebContentsObserver(contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(contents);
}
PagePDF::~PagePDF() { Close(); }
bool PagePDF::Valid() const {
  if (!pending_ || closed_ || !web_contents() || pending_->navigation != navigation_) return false;
  auto* frame = pending_->document.AsRenderFrameHostIfValid();
  return frame && frame == web_contents()->GetPrimaryMainFrame() &&
      frame->GetGlobalId() == pending_->frame && frame->IsActive() &&
      frame->IsRenderFrameLive() && content::WebContents::FromRenderFrameHost(frame) == web_contents();
}
BoazHostResult PagePDF::Capture(uint64_t request, Completion completion) {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) return BOAZ_HOST_WRONG_THREAD;
  if (!request || !completion) return BOAZ_HOST_INVALID_ARGUMENT;
  if (closed_ || !web_contents()) return BOAZ_HOST_CLOSING;
  if (pending_) return BOAZ_HOST_UNAVAILABLE;
  auto* frame = web_contents()->GetPrimaryMainFrame();
  if (!frame || !frame->IsActive() || !frame->IsRenderFrameLive() ||
      !frame->GetLastCommittedURL().SchemeIsHTTPOrHTTPS() ||
      frame->GetLastCommittedOrigin().opaque()) return BOAZ_HOST_UNAVAILABLE;
#if BUILDFLAG(ENABLE_PRINTING)
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(web_contents());
  auto* manager = ActivePrintManager::FromWebContents(web_contents());
  if (!browser || browser->GetTabStripModel()->GetActiveWebContents() != web_contents() ||
      !chrome::CanPrint(browser) || !manager) return BOAZ_HOST_UNAVAILABLE;
  auto params = print_to_pdf::GetPrintPagesParams(frame->GetLastCommittedURL(),
      false, false, true, 1.0, 210.0 / 25.4, 297.0 / 25.4,
      10.0 / 25.4, 10.0 / 25.4, 10.0 / 25.4, 10.0 / 25.4,
      std::nullopt, std::nullopt, false, true, false);
  if (!std::holds_alternative<printing::mojom::PrintPagesParamsPtr>(params)) return BOAZ_HOST_UNAVAILABLE;
  CHECK_LT(next_serial_, std::numeric_limits<uint64_t>::max());
  const auto serial = next_serial_++;
  pending_ = std::make_unique<Pending>();
  pending_->request = request;
  pending_->serial = serial;
  pending_->navigation = navigation_;
  pending_->document = frame->GetWeakDocumentPtr();
  pending_->frame = frame->GetGlobalId();
  pending_->completion = std::move(completion);
  pending_->timer.Start(FROM_HERE, base::Seconds(30),
      base::BindOnce(&PagePDF::Finish, weak_.GetWeakPtr(), Status::kTimeout, std::vector<uint8_t>()));
  manager->PrintToPdf(frame, "", std::move(std::get<printing::mojom::PrintPagesParamsPtr>(params)),
      base::BindOnce([](scoped_refptr<base::SingleThreadTaskRunner> runner,
                       base::WeakPtr<PagePDF> owner, uint64_t serial,
                       print_to_pdf::PdfPrintResult result,
                       scoped_refptr<base::RefCountedMemory> data) {
        Outcome outcome{Status::kFailed, {}};
        if (result == print_to_pdf::PdfPrintResult::kPrintingInProgress) outcome.status = Status::kBusy;
        if (result == print_to_pdf::PdfPrintResult::kPrintSuccess && data) {
          if (data->size() > 32 * 1024 * 1024) outcome.status = Status::kTooLarge;
          else if (data->size() > 0) {
            outcome.status = Status::kSuccess;
            const auto bytes = base::span<const uint8_t>(*data);
            outcome.bytes.assign(bytes.begin(), bytes.end());
          }
        }
        runner->PostTask(FROM_HERE, base::BindOnce(&PagePDF::Completed, owner, serial, std::move(outcome)));
      }, base::SingleThreadTaskRunner::GetCurrentDefault(), weak_.GetWeakPtr(), serial));
  return BOAZ_HOST_OK;
#else
  return BOAZ_HOST_UNAVAILABLE;
#endif
}
void PagePDF::Completed(uint64_t serial, Outcome outcome) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_ || pending_->serial != serial) return;
  if (!Valid()) { Finish(Status::kInvalid); return; }
  Finish(outcome.status, std::move(outcome.bytes));
}
void PagePDF::Finish(Status status, std::vector<uint8_t> bytes) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!pending_) return;
  auto completion = std::move(pending_->completion);
  pending_.reset();
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(completion), Outcome{status, std::move(bytes)}));
}
BoazHostResult PagePDF::Cancel(uint64_t request) {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI)) return BOAZ_HOST_WRONG_THREAD;
  if (!pending_ || !request || pending_->request != request) return BOAZ_HOST_INVALID_ARGUMENT;
  Finish(Status::kCancelled);
  return BOAZ_HOST_OK;
}
void PagePDF::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  Finish(Status::kClosed);
  weak_.InvalidateWeakPtrs();
  Observe(nullptr);
}
void PagePDF::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
    CHECK_LT(navigation_, std::numeric_limits<uint64_t>::max());
    ++navigation_;
    Finish(Status::kNavigation);
  }
}
void PagePDF::RenderFrameDeleted(content::RenderFrameHost* frame) {
  if (pending_ && pending_->frame == frame->GetGlobalId()) Finish(Status::kInvalid);
}
void PagePDF::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) { Finish(Status::kCrash); }
void PagePDF::WebContentsDestroyed() { Close(); }
}
