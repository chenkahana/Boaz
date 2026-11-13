#include "boaz/page_emulation.h"

#include <cmath>
#include <limits>
#include <string>
#include <utility>
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "url/origin.h"

namespace boaz {
PageEmulation::PageEmulation(content::WebContents* contents)
    : content::WebContentsObserver(contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}
PageEmulation::~PageEmulation() { Close(); }
void PageEmulation::Reply(Completion completion, Result result) {
  if (completion) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(completion), result));
}
void PageEmulation::Apply(Viewport viewport, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  if (viewport.width < 1 || viewport.width > 8192 || viewport.height < 1 ||
      viewport.height > 8192 || !std::isfinite(viewport.dpr) || viewport.dpr < 0.5 ||
      viewport.dpr > 4 || viewport.max_touch_points < 1 || viewport.max_touch_points > 10) {
    Reply(std::move(completion), Result::kInvalid); return;
  }
  viewport_ = viewport;
  Start(false, std::move(completion));
}
void PageEmulation::Clear(Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Start(true, std::move(completion));
}
void PageEmulation::Start(bool clear, Completion completion) {
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (!completion || completion_ || !web_contents() ||
      DevToolsWindow::GetInstanceForInspectedWebContents(web_contents()) ||
      !MayAttachToRenderFrameHost(web_contents()->GetPrimaryMainFrame())) {
    Reply(std::move(completion), Result::kUnavailable); return;
  }
  if (!host_) {
    auto host = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
    if (!host || host->GetWebContents() != web_contents()) {
      Reply(std::move(completion), Result::kUnavailable); return;
    }
    host_ = host;
    if (!host_->AttachClient(this)) {
      host_ = nullptr;
      Reply(std::move(completion), Result::kUnavailable); return;
    }
  }
  completion_ = std::move(completion);
  clearing_ = clear;
  resetting_ = false;
  step_ = 0;
  timer_.Start(FROM_HERE, base::Seconds(5), base::BindOnce(
      &PageEmulation::Fail, weak_factory_.GetWeakPtr(), Result::kTimeout));
  SendNext();
}
void PageEmulation::SendNext() {
  if (!completion_ || !host_) return;
  if (step_ == 2) { Finish(resetting_ ? failure_ : Result::kSuccess); return; }
  if (next_id_ == std::numeric_limits<int>::max()) { Cancel(Result::kUnavailable); return; }
  base::DictValue params;
  std::string method;
  if (step_ == 0) {
    method = clearing_ ? "Emulation.clearDeviceMetricsOverride" : "Emulation.setDeviceMetricsOverride";
    if (!clearing_) {
      params.Set("width", viewport_.width);
      params.Set("height", viewport_.height);
      params.Set("deviceScaleFactor", viewport_.dpr);
      params.Set("mobile", viewport_.mobile);
      base::DictValue orientation;
      orientation.Set("type", viewport_.landscape ? "landscapePrimary" : "portraitPrimary");
      orientation.Set("angle", viewport_.landscape ? 90 : 0);
      params.Set("screenOrientation", std::move(orientation));
    }
  } else {
    method = "Emulation.setTouchEmulationEnabled";
    params.Set("enabled", !clearing_ && viewport_.touch);
    if (!clearing_ && viewport_.touch) params.Set("maxTouchPoints", viewport_.max_touch_points);
  }
  pending_id_ = ++next_id_;
  base::DictValue request;
  request.Set("id", pending_id_);
  request.Set("method", method);
  request.Set("params", std::move(params));
  std::string json;
  if (!base::JSONWriter::Write(request, &json)) { Fail(Result::kProtocolError); return; }
  auto host = host_;
  host->DispatchProtocolMessage(this, base::as_byte_span(json));
}
void PageEmulation::DispatchProtocolMessage(content::DevToolsAgentHost* host,
                                            base::span<const uint8_t> message) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (host != host_.get() || !completion_ || message.size() > 65536) return;
  auto reply = base::JSONReader::ReadDict(std::string_view(
      reinterpret_cast<const char*>(message.data()), message.size()), base::JSON_PARSE_RFC);
  if (!reply || reply->FindInt("id") != pending_id_) return;
  pending_id_ = 0;
  if (reply->contains("error") || !reply->contains("result")) { Fail(Result::kProtocolError); return; }
  ++step_;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&PageEmulation::SendNext, weak_factory_.GetWeakPtr()));
}
void PageEmulation::Fail(Result result) {
  if (!completion_) return;
  if (resetting_) { Cancel(failure_); return; }
  failure_ = result;
  resetting_ = true;
  clearing_ = true;
  step_ = 0;
  pending_id_ = 0;
  timer_.Start(FROM_HERE, base::Seconds(5), base::BindOnce(
      &PageEmulation::Cancel, weak_factory_.GetWeakPtr(), result));
  SendNext();
}
void PageEmulation::Finish(Result result) {
  timer_.Stop();
  pending_id_ = 0;
  Reply(std::move(completion_), result);
}
void PageEmulation::Detach() {
  auto host = std::move(host_);
  if (host) host->DetachClient(this);
}
void PageEmulation::Cancel(Result result) {
  weak_factory_.InvalidateWeakPtrs();
  Finish(result);
  Detach();
}
void PageEmulation::Close() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) return;
  closed_ = true;
  Cancel(Result::kClosed);
  Observe(nullptr);
}
void PageEmulation::AgentHostClosed(content::DevToolsAgentHost* host) {
  if (host != host_.get()) return;
  host_ = nullptr;
  Cancel(Result::kUnavailable);
}
bool PageEmulation::MayAttachToURL(const GURL& url, bool is_webui) {
  return !closed_ && !is_webui && web_contents() && url.SchemeIsHTTPOrHTTPS();
}
bool PageEmulation::MayAttachToRenderFrameHost(content::RenderFrameHost* frame) {
  return frame && web_contents() && frame == web_contents()->GetPrimaryMainFrame() &&
      !frame->GetLastCommittedOrigin().opaque() && MayAttachToURL(frame->GetLastCommittedURL(), false);
}
void PageEmulation::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Cancel(Result::kNavigation);
}
void PageEmulation::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) { Cancel(Result::kUnavailable); }
void PageEmulation::WebContentsDestroyed() { Close(); }
}  // namespace boaz
