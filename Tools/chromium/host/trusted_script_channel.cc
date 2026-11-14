#include "trusted_script_channel.h"
#include <limits>
#include <algorithm>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"

namespace boaz {
namespace {
void CheckUI() {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
}
uint64_t NextToken() {
  CheckUI();
  static uint64_t next = 1;
  // Never wrap or reuse a token, including after a channel is destroyed.
  CHECK(next < std::numeric_limits<uint64_t>::max());
  return next++;
}
void Post(TrustedExecution::Completion completion, TrustedExecution::Status status) {
  if (completion) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(completion),
            TrustedExecution::Outcome{status, base::Value()}));
  }
}
}  // namespace

TrustedScriptChannel::TrustedScriptChannel(content::WebContents* contents)
    : WebContentsObserver(contents), executor_(contents) {
  CheckUI();
  CHECK(contents);
}
TrustedScriptChannel::~TrustedScriptChannel() { Close(); }

std::optional<uint64_t> TrustedScriptChannel::Capture(std::string* origin, bool focused) {
  CheckUI();
  if (origin) origin->clear();
  std::erase_if(targets_, [this](const auto& entry) { return !executor_.IsValid(entry.second); });
  if (closed_ || targets_.size() >= 64) return std::nullopt;
  auto target = executor_.CaptureTarget(focused);
  if (!target) return std::nullopt;
  if (origin) *origin = target->origin.Serialize();
  const uint64_t token = NextToken();
  targets_.emplace(token, std::move(*target));
  return token;
}

std::optional<uint64_t> TrustedScriptChannel::Clone(uint64_t token) {
  CheckUI();
  std::erase_if(targets_, [this](const auto& entry) { return !executor_.IsValid(entry.second); });
  auto found = targets_.find(token);
  if (closed_ || targets_.size() >= 64 || found == targets_.end()) return std::nullopt;
  const auto clone = NextToken();
  targets_.emplace(clone, found->second);
  return clone;
}

bool TrustedScriptChannel::Release(uint64_t token) {
  CheckUI();
  return !closed_ && targets_.erase(token) != 0;
}

void TrustedScriptChannel::Execute(uint64_t token, std::u16string source,
                                   base::DictValue arguments,
                                   TrustedExecution::Completion completion) {
  CheckUI();
  if (closed_) {
    Post(std::move(completion), TrustedExecution::Status::kClosed);
    return;
  }
  auto entry = targets_.extract(token);
  if (entry.empty()) {
    Post(std::move(completion), TrustedExecution::Status::kInvalidTarget);
    return;
  }
  // Consume before dispatch, including invalid arguments, stale target or busy.
  executor_.Execute(std::move(entry.mapped()), std::move(source),
                    std::move(arguments), std::move(completion));
}

void TrustedScriptChannel::Close() {
  CheckUI();
  if (closed_) return;
  closed_ = true;
  targets_.clear();
  Observe(nullptr);
  executor_.Close();
}

void TrustedScriptChannel::DidStartNavigation(content::NavigationHandle* navigation) {
  CheckUI();
  if (navigation->IsSameDocument()) return;
  const auto node = navigation->GetFrameTreeNodeId();
  std::erase_if(targets_, [node](const auto& entry) {
    auto& validity = entry.second.validity;
    if (std::ranges::find(validity->ancestors, node) == validity->ancestors.end()) return false;
    validity->valid = false;
    return true;
  });
}
void TrustedScriptChannel::RenderFrameDeleted(content::RenderFrameHost* frame) {
  CheckUI();
  for (auto it = targets_.begin(); it != targets_.end();) {
    if (std::ranges::find(it->second.validity->frames, frame->GetGlobalId()) !=
        it->second.validity->frames.end()) {
      it->second.validity->valid = false;
      it = targets_.erase(it);
    }
    else ++it;
  }
}
void TrustedScriptChannel::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  CheckUI();
  targets_.clear();
}
void TrustedScriptChannel::WebContentsDestroyed() { Close(); }
}  // namespace boaz
