#include "boaz/page_emulation.h"

#include <cmath>
#include "base/base64.h"
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
#include "components/embedder_support/user_agent_utils.h"
#include "third_party/blink/public/common/user_agent/user_agent_metadata.h"
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
// Typed locale/timezone commands require a trusted internal client.
bool PageEmulation::IsTrusted() { return true; }
bool PageEmulation::MayReadLocalFiles() { return false; }
bool PageEmulation::MayWriteLocalFiles() { return false; }
bool PageEmulation::AllowUnsafeOperations() { return false; }
void PageEmulation::Reply(Completion completion, Result result) {
  if (completion) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(completion), result));
}
void PageEmulation::Apply(Viewport viewport, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_ || capture_completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  if (viewport.width < 1 || viewport.width > 8192 || viewport.height < 1 ||
      viewport.height > 8192 || !std::isfinite(viewport.dpr) || viewport.dpr < 0.5 ||
      viewport.dpr > 4 || viewport.max_touch_points < 1 || viewport.max_touch_points > 10) {
    Reply(std::move(completion), Result::kInvalid); return;
  }
  viewport_ = viewport;
  Start(false, Operation::kViewport, std::move(completion));
}
void PageEmulation::Clear(Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  Start(true, Operation::kViewport, std::move(completion));
}
std::optional<PageEmulation::UserAgentDefaults> PageEmulation::GetDefaultUserAgent() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  const auto metadata = embedder_support::GetUserAgentMetadata();
  UserAgentDefaults result;
  result.user_agent = embedder_support::GetUserAgent();
  // Blink's macOS default in core/frame/navigator_id.cc; not the CPU architecture.
  result.navigator_platform = "MacIntel";
  result.full_version = metadata.full_version;
  result.platform = metadata.platform;
  result.platform_version = metadata.platform_version;
  result.architecture = metadata.architecture;
  result.model = metadata.model;
  result.bitness = metadata.bitness;
  result.mobile = metadata.mobile;
  result.wow64 = metadata.wow64;
  result.form_factors = metadata.form_factors;
  if (metadata.brand_version_list.size() > 16 || metadata.brand_full_version_list.size() > 16 ||
      result.form_factors.size() > 16) return std::nullopt;
  auto bounded = [](const std::string& value) {
    return value.size() <= 8192 && value.find_first_of(std::string("\r\n\0", 3)) == std::string::npos;
  };
  for (const auto* value : {&result.user_agent, &result.navigator_platform, &result.full_version,
       &result.platform, &result.platform_version, &result.architecture, &result.model, &result.bitness}) {
    if (!bounded(*value)) return std::nullopt;
  }
  for (const auto& value : result.form_factors) if (!bounded(value)) return std::nullopt;
  for (const auto& value : metadata.brand_version_list) {
    if (!bounded(value.brand) || !bounded(value.version)) return std::nullopt;
    result.brands.push_back({value.brand, value.version});
  }
  for (const auto& value : metadata.brand_full_version_list) {
    if (!bounded(value.brand) || !bounded(value.version)) return std::nullopt;
    result.full_version_list.push_back({value.brand, value.version});
  }
  return result;
}
void PageEmulation::ApplyUserAgent(std::optional<std::string> user_agent, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_ || capture_completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  if (user_agent && (user_agent->empty() || user_agent->size() > 8192 ||
      user_agent->find_first_of(std::string("\r\n\0", 3)) != std::string::npos)) {
    Reply(std::move(completion), Result::kInvalid); return;
  }
  user_agent_ = user_agent.value_or(std::string());
  Start(!user_agent.has_value(), Operation::kUserAgent, std::move(completion));
}
void PageEmulation::ApplyMedia(std::optional<Media> media, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_ || capture_completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  auto valid_preference = [](Media::Preference value) {
    return value == Media::Preference::kDefault ||
           value == Media::Preference::kFirst || value == Media::Preference::kSecond;
  };
  if (media && ((media->type != Media::MediaType::kScreen &&
                 media->type != Media::MediaType::kPrint) ||
                !valid_preference(media->color_scheme) ||
                !valid_preference(media->reduced_motion) ||
                !valid_preference(media->contrast) ||
                media->vision < Media::Vision::kNone ||
                media->vision > Media::Vision::kTritanopia)) {
    Reply(std::move(completion), Result::kInvalid); return;
  }
  media_ = media.value_or(Media{});
  Start(!media.has_value(), Operation::kMedia, std::move(completion));
}
void PageEmulation::ApplyNetwork(std::optional<Network> network, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_ || capture_completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  auto valid_throughput = [](double value) {
    return std::isfinite(value) && (value == -1 || (value >= 1 && value <= 1e9));
  };
  if (network && (!std::isfinite(network->latency_ms) || network->latency_ms < 0 ||
      network->latency_ms > 10000 || !valid_throughput(network->download_bytes_per_second) ||
      !valid_throughput(network->upload_bytes_per_second))) {
    Reply(std::move(completion), Result::kInvalid); return;
  }
  network_ = network.value_or(Network{false, 0, -1, -1});
  Start(!network.has_value(), Operation::kNetwork, std::move(completion));
}
void PageEmulation::ApplyCPU(double rate, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_ || capture_completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  if (!std::isfinite(rate) || rate < 1 || rate > 20) {
    Reply(std::move(completion), Result::kInvalid); return;
  }
  cpu_rate_ = rate;
  Start(rate == 1, Operation::kCPU, std::move(completion));
}
void PageEmulation::ApplySensors(std::optional<Sensors> sensors, Completion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (completion_ || capture_completion_) { Reply(std::move(completion), Result::kUnavailable); return; }
  auto valid_string = [](const std::string& value) {
    if (value.size() > 128) return false;
    for (unsigned char ch : value) if (ch < 32 || ch > 126) return false;
    return true;
  };
  if (sensors) {
    bool valid = valid_string(sensors->timezone) && valid_string(sensors->locale);
    if (sensors->location) {
      const auto& location = *sensors->location;
      valid = valid && std::isfinite(location.latitude) && std::isfinite(location.longitude) &&
          std::isfinite(location.accuracy) && location.latitude >= -90 && location.latitude <= 90 &&
          location.longitude >= -180 && location.longitude <= 180 &&
          location.accuracy >= 0 && location.accuracy <= 1e6;
    }
    if (!valid) { Reply(std::move(completion), Result::kInvalid); return; }
  }
  sensors_ = sensors.value_or(Sensors{});
  Start(!sensors.has_value(), Operation::kSensors, std::move(completion));
}
void PageEmulation::CaptureFullPage(uint64_t request, CaptureCompletion completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto reject = [&](Result result) {
    if (completion) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(completion), result, std::vector<uint8_t>()));
  };
  if (closed_) { reject(Result::kClosed); return; }
  if (!request || !completion) { reject(Result::kInvalid); return; }
  if (completion_ || capture_completion_ || !web_contents() ||
      DevToolsWindow::GetInstanceForInspectedWebContents(web_contents()) ||
      !MayAttachToRenderFrameHost(web_contents()->GetPrimaryMainFrame())) {
    reject(Result::kUnavailable); return;
  }
  if (!host_) {
    host_ = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
    if (!host_ || host_->GetWebContents() != web_contents() || !host_->AttachClient(this)) {
      host_ = nullptr;
      reject(Result::kUnavailable); return;
    }
  }
  capture_document_ = web_contents()->GetPrimaryMainFrame()->GetWeakDocumentPtr();
  capture_request_ = request;
  capture_step_ = 0;
  capture_completion_ = std::move(completion);
  timer_.Start(FROM_HERE, base::Seconds(30), base::BindOnce(
      &PageEmulation::FinishCapture, weak_factory_.GetWeakPtr(), Result::kTimeout,
      std::vector<uint8_t>()));
  SendCapture();
}
void PageEmulation::CancelFullPage(uint64_t request) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (capture_completion_ && capture_request_ == request) FinishCapture(Result::kUnavailable);
}
void PageEmulation::FinishCapture(Result result, std::vector<uint8_t> bytes) {
  if (!capture_completion_) return;
  auto completion = std::move(capture_completion_);
  weak_factory_.InvalidateWeakPtrs();
  timer_.Stop();
  pending_id_ = 0;
  capture_request_ = 0;
  capture_document_ = {};
  if (result != Result::kSuccess) {
    if (result != Result::kTimeout && result != Result::kNavigation && result != Result::kClosed)
      result = Result::kProtocolError;
    Detach();
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(std::move(completion), result, std::move(bytes)));
}
void PageEmulation::SendCapture() {
  if (!capture_completion_ || !host_) return;
  auto* frame = capture_document_.AsRenderFrameHostIfValid();
  if (!MayAttachToRenderFrameHost(frame)) { FinishCapture(Result::kNavigation); return; }
  if (next_id_ == std::numeric_limits<int>::max()) { FinishCapture(Result::kUnavailable); return; }
  base::DictValue params;
  if (capture_step_ == 1) {
    params.Set("format", "png");
    params.Set("fromSurface", true);
    params.Set("captureBeyondViewport", true);
  }
  base::DictValue request;
  pending_id_ = ++next_id_;
  request.Set("id", pending_id_);
  request.Set("method", capture_step_ == 0 ? "Page.getLayoutMetrics" : "Page.captureScreenshot");
  request.Set("params", std::move(params));
  std::string json;
  if (!base::JSONWriter::Write(request, &json)) { FinishCapture(Result::kProtocolError); return; }
  auto host = host_;
  host->DispatchProtocolMessage(this, base::as_byte_span(json));
}
void PageEmulation::Start(bool clear, Operation operation, Completion completion) {
  if (closed_) { Reply(std::move(completion), Result::kClosed); return; }
  if (!completion || completion_ || capture_completion_ || !web_contents() ||
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
  operation_ = operation;
  clearing_ = clear;
  resetting_ = false;
  step_ = 0;
  timer_.Start(FROM_HERE, base::Seconds(5), base::BindOnce(
      &PageEmulation::Fail, weak_factory_.GetWeakPtr(), Result::kTimeout));
  SendNext();
}
void PageEmulation::SendNext() {
  if (!completion_ || !host_) return;
  const int steps = operation_ == Operation::kSensors ? 3 :
      ((operation_ == Operation::kUserAgent || operation_ == Operation::kCPU) ? 1 : 2);
  if (step_ == steps) {
    if (resetting_) Cancel(failure_);
    else Finish(Result::kSuccess);
    return;
  }
  if (next_id_ == std::numeric_limits<int>::max()) { Cancel(Result::kUnavailable); return; }
  base::DictValue params;
  std::string method;
  if (operation_ == Operation::kUserAgent) {
    method = "Emulation.setUserAgentOverride";
    params.Set("userAgent", clearing_ ? std::string() : user_agent_);
  } else if (operation_ == Operation::kSensors) {
    if (step_ == 0) {
      if (!clearing_ && sensors_.location) {
        method = "Emulation.setGeolocationOverride";
        params.Set("latitude", sensors_.location->latitude);
        params.Set("longitude", sensors_.location->longitude);
        params.Set("accuracy", sensors_.location->accuracy);
      } else method = "Emulation.clearGeolocationOverride";
    } else if (step_ == 1) {
      method = "Emulation.setTimezoneOverride";
      params.Set("timezoneId", clearing_ ? std::string() : sensors_.timezone);
    } else {
      method = "Emulation.setLocaleOverride";
      params.Set("locale", clearing_ ? std::string() : sensors_.locale);
    }
  } else if (operation_ == Operation::kCPU) {
    method = "Emulation.setCPUThrottlingRate";
    params.Set("rate", clearing_ ? 1.0 : cpu_rate_);
  } else if (operation_ == Operation::kNetwork) {
    const auto network = clearing_ ? Network{false, 0, -1, -1} : network_;
    if (step_ == 0) {
      method = "Network.emulateNetworkConditionsByRule";
      params.Set("emulateOfflineServiceWorker", network.offline);
      base::ListValue rules;
      if (!clearing_) {
        base::DictValue rule;
        rule.Set("urlPattern", "");
        rule.Set("offline", network.offline);
        rule.Set("latency", network.latency_ms);
        rule.Set("downloadThroughput", network.download_bytes_per_second);
        rule.Set("uploadThroughput", network.upload_bytes_per_second);
        rules.Append(std::move(rule));
      }
      params.Set("matchedNetworkConditions", std::move(rules));
    } else {
      method = "Network.overrideNetworkState";
      params.Set("offline", network.offline);
      params.Set("latency", network.latency_ms);
      params.Set("downloadThroughput", network.download_bytes_per_second);
      params.Set("uploadThroughput", network.upload_bytes_per_second);
    }
  } else if (operation_ == Operation::kMedia) {
    if (step_ == 0) {
      method = "Emulation.setEmulatedMedia";
      params.Set("media", clearing_ ? "" :
          (media_.type == Media::MediaType::kPrint ? "print" : "screen"));
      base::ListValue features;
      auto add = [&features](const char* name, const char* value) {
        base::DictValue feature;
        feature.Set("name", name);
        feature.Set("value", value);
        features.Append(std::move(feature));
      };
      auto preference = [&add](const char* name, Media::Preference value,
                              const char* first, const char* second) {
        if (value != Media::Preference::kDefault)
          add(name, value == Media::Preference::kFirst ? first : second);
      };
      if (!clearing_) {
        preference("prefers-color-scheme", media_.color_scheme, "light", "dark");
        preference("prefers-reduced-motion", media_.reduced_motion, "no-preference", "reduce");
        preference("prefers-contrast", media_.contrast, "no-preference", "more");
        add("forced-colors", media_.forced_colors ? "active" : "none");
      }
      params.Set("features", std::move(features));
    } else {
      method = "Emulation.setEmulatedVisionDeficiency";
      const char* vision = "none";
      if (!clearing_) {
        switch (media_.vision) {
          case Media::Vision::kNone: break;
          case Media::Vision::kBlurred: vision = "blurredVision"; break;
          case Media::Vision::kReducedContrast: vision = "reducedContrast"; break;
          case Media::Vision::kAchromatopsia: vision = "achromatopsia"; break;
          case Media::Vision::kDeuteranopia: vision = "deuteranopia"; break;
          case Media::Vision::kProtanopia: vision = "protanopia"; break;
          case Media::Vision::kTritanopia: vision = "tritanopia"; break;
        }
      }
      params.Set("type", vision);
    }
  } else if (step_ == 0) {
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
  if (host != host_.get()) return;
  if (capture_completion_) {
    if (message.size() > 46u * 1024 * 1024) { FinishCapture(Result::kInvalid); return; }
    auto reply = base::JSONReader::ReadDict(std::string_view(
        reinterpret_cast<const char*>(message.data()), message.size()), base::JSON_PARSE_RFC);
    if (!reply || reply->FindInt("id") != pending_id_) return;
    pending_id_ = 0;
    auto* result = reply->FindDict("result");
    if (reply->contains("error") || !result) { FinishCapture(Result::kProtocolError); return; }
    if (!MayAttachToRenderFrameHost(capture_document_.AsRenderFrameHostIfValid())) {
      FinishCapture(Result::kNavigation); return;
    }
    auto valid_size = [](double width, double height) {
      return std::isfinite(width) && std::isfinite(height) && width > 0 && height > 0 &&
          width <= 32768 && height <= 32768 && width * height <= 32u * 1024 * 1024;
    };
    if (capture_step_ == 0) {
      auto* size = result->FindDict("cssContentSize");
      if (!size || !valid_size(size->FindDouble("width").value_or(0),
                               size->FindDouble("height").value_or(0))) {
        FinishCapture(Result::kInvalid); return;
      }
      capture_step_ = 1;
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
          base::BindOnce(&PageEmulation::SendCapture, weak_factory_.GetWeakPtr()));
      return;
    }
    const auto* data = result->FindString("data");
    std::string decoded;
    if (!data || data->size() > ((32u * 1024 * 1024 + 2) / 3) * 4 ||
        !base::Base64Decode(*data, &decoded) || decoded.size() > 32u * 1024 * 1024 ||
        decoded.size() < 33 || decoded.compare(0, 8, "\x89PNG\r\n\x1a\n", 8) != 0 ||
        decoded.compare(8, 8, "\0\0\0\x0dIHDR", 8) != 0) {
      FinishCapture(Result::kInvalid); return;
    }
    auto dimension = [&decoded](size_t offset) {
      uint32_t value = 0;
      for (size_t i = 0; i < 4; ++i) value = (value << 8) | static_cast<uint8_t>(decoded[offset + i]);
      return value;
    };
    if (!valid_size(dimension(16), dimension(20))) { FinishCapture(Result::kInvalid); return; }
    FinishCapture(Result::kSuccess, std::vector<uint8_t>(decoded.begin(), decoded.end()));
    return;
  }
  if (!completion_ || message.size() > 65536) return;
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
  weak_factory_.InvalidateWeakPtrs();
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
  weak_factory_.InvalidateWeakPtrs();
  timer_.Stop();
  pending_id_ = 0;
  Reply(std::move(completion_), result);
}
void PageEmulation::Detach() {
  auto host = std::move(host_);
  if (host) host->DetachClient(this);
}
void PageEmulation::Cancel(Result result) {
  FinishCapture(result);
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
  Cancel(Result::kProtocolError);
}
bool PageEmulation::MayAttachToURL(const GURL& url, bool is_webui) {
  return !closed_ && !is_webui && web_contents() && url.SchemeIsHTTPOrHTTPS();
}
bool PageEmulation::MayAttachToRenderFrameHost(content::RenderFrameHost* frame) {
  return frame && web_contents() && frame == web_contents()->GetPrimaryMainFrame() &&
      frame->IsActive() && frame->IsRenderFrameLive() &&
      !frame->GetLastCommittedOrigin().opaque() && MayAttachToURL(frame->GetLastCommittedURL(), false);
}
void PageEmulation::DidStartNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Cancel(Result::kNavigation);
}
void PageEmulation::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) { Cancel(Result::kUnavailable); }
void PageEmulation::WebContentsDestroyed() { Close(); }
}  // namespace boaz
