#include "page_scroll.h"
#include <cmath>
#include <optional>
#include <limits>
#include <string>
#include <string_view>
#include <utility>
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "base/values.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
namespace boaz {
PageScroll::PageScroll(content::WebContents* contents) : WebContentsObserver(contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}
PageScroll::~PageScroll() { Close(); }
bool PageScroll::IsTrusted() { return true; }
bool PageScroll::MayReadLocalFiles() { return false; }
bool PageScroll::MayWriteLocalFiles() { return false; }
bool PageScroll::AllowUnsafeOperations() { return false; }
void PageScroll::Read(Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto reject = [&](Result result) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(completion), result, 0.0, 0.0));
  };
  if (closed_) { reject(Result::kClosed); return; }
  if (completion_ || !web_contents() || DevToolsWindow::GetInstanceForInspectedWebContents(web_contents()) ||
      !MayAttachToRenderFrameHost(web_contents()->GetPrimaryMainFrame())) {
    reject(Result::kUnavailable); return;
  }
  auto host = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
  if (!host || host->GetWebContents() != web_contents() || !host->AttachClient(this)) {
    reject(Result::kUnavailable); return;
  }
  host_ = host;
  completion_ = std::move(completion);
  timer_.Start(FROM_HERE, base::Seconds(5),
      base::BindOnce(&PageScroll::Finish, weak_.GetWeakPtr(), Result::kTimeout, 0.0, 0.0));
  CHECK_LT(next_id_, std::numeric_limits<int>::max());
  base::DictValue request;
  request.Set("id", ++next_id_);
  request.Set("method", "Page.getLayoutMetrics");
  request.Set("params", base::DictValue());
  std::string json;
  if (!base::JSONWriter::Write(request, &json)) { Finish(Result::kProtocolError); return; }
  host->DispatchProtocolMessage(this, base::as_byte_span(json));
}
void PageScroll::Finish(Result result, double x, double y) {
  if (!completion_) return;
  auto completion = std::move(completion_);
  timer_.Stop();
  weak_.InvalidateWeakPtrs();
  if (auto host = std::move(host_)) host->DetachClient(this);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(completion), result, x, y));
}
void PageScroll::DispatchProtocolMessage(content::DevToolsAgentHost* host, base::span<const uint8_t> message) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (host != host_.get() || !completion_ || message.size() > 65536) return;
  auto reply = base::JSONReader::ReadDict(std::string_view(
      reinterpret_cast<const char*>(message.data()), message.size()), base::JSON_PARSE_RFC);
  if (!reply || reply->FindInt("id") != next_id_) return;
  auto* viewport = reply->FindDictByDottedPath("result.cssVisualViewport");
  const auto x = viewport ? viewport->FindDouble("pageX") : std::nullopt;
  const auto y = viewport ? viewport->FindDouble("pageY") : std::nullopt;
  if (!x || !y || !std::isfinite(*x) || !std::isfinite(*y)) { Finish(Result::kProtocolError); return; }
  Finish(Result::kSuccess, *x, *y);
}
void PageScroll::AgentHostClosed(content::DevToolsAgentHost* host) {
  if (host != host_.get()) return;
  host_ = nullptr;
  Finish(Result::kProtocolError);
}
bool PageScroll::MayAttachToURL(const GURL& url, bool is_webui) {
  return !closed_ && !is_webui && web_contents() && (url.SchemeIsHTTPOrHTTPS() || url.SchemeIsFile());
}
bool PageScroll::MayAttachToRenderFrameHost(content::RenderFrameHost* frame) {
  return frame && web_contents() && frame == web_contents()->GetPrimaryMainFrame() &&
      frame->IsActive() && frame->IsRenderFrameLive() && MayAttachToURL(frame->GetLastCommittedURL(), false);
}
void PageScroll::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  Finish(Result::kClosed);
  Observe(nullptr);
}
void PageScroll::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Finish(Result::kNavigation);
}
void PageScroll::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) { Finish(Result::kUnavailable); }
void PageScroll::WebContentsDestroyed() { Close(); }
}
