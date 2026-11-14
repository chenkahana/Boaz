#include "adblock_navigation.h"
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include "adblock_profile_state.h"
#include "bootstrap.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "net/base/net_errors.h"
#include "net/base/schemeful_site.h"
#include "url/origin.h"

namespace boaz {
namespace {
bool EligibleFrame(content::NavigationHandle& navigation) {
  if (navigation.IsSameDocument() || navigation.IsInFencedFrameTree() ||
      navigation.IsInPrerenderedMainFrame()) return false;
  if (navigation.IsInPrimaryMainFrame()) return true;
  auto* parent = navigation.GetParentFrame();
  return parent && parent->IsActive() && !parent->IsNestedWithinFencedFrame() &&
      parent->GetOutermostMainFrame() == navigation.GetWebContents()->GetPrimaryMainFrame();
}

class AdblockNavigation final : public content::NavigationThrottle {
 public:
  AdblockNavigation(content::NavigationThrottleRegistry& registry,
                    std::shared_ptr<AdblockProfileState> state, GURL source)
      : content::NavigationThrottle(registry), state_(std::move(state)),
        source_(std::move(source)) {}
  ~AdblockNavigation() override = default;
  ThrottleCheckResult WillStartRequest() override { return Check(); }
  ThrottleCheckResult WillRedirectRequest() override { return Check(); }
  const char* GetNameForLogging() override { return "BoazAdblockNavigation"; }

 private:
  ThrottleCheckResult Check() {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    auto& navigation = *navigation_handle();
    if (!EligibleFrame(navigation) || !navigation.GetURL().SchemeIsHTTPOrHTTPS())
      return PROCEED;
    std::optional<net::SchemefulSite> top;
    const bool main = navigation.IsInPrimaryMainFrame();
    if (main) {
      top.emplace(navigation.GetURL());
    } else {
      auto* primary = navigation.GetWebContents()->GetPrimaryMainFrame();
      if (!primary || !primary->IsActive()) return PROCEED;
      const auto& origin = primary->GetLastCommittedOrigin();
      if (origin.opaque() || !origin.GetURL().SchemeIsHTTPOrHTTPS()) return PROCEED;
      top.emplace(origin);
    }
    if (top->opaque()) return PROCEED;
    DCHECK(!pending_);
    pending_ = true;
    const bool posted = base::ThreadPool::PostTaskAndReplyWithResult(
        FROM_HERE,
        {base::TaskPriority::USER_VISIBLE, base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
        base::BindOnce([](std::shared_ptr<AdblockProfileState> state, GURL url,
                          GURL source, std::string method, bool main,
                          std::optional<net::SchemefulSite> top) {
          return state->Evaluate(url, source, main ? "document" : "subdocument", method, top);
        }, state_, navigation.GetURL(), source_, navigation.GetRequestMethod(), main, std::move(top)),
        base::BindOnce(&AdblockNavigation::Decided, weak_.GetWeakPtr()));
    if (!posted) {
      pending_ = false;
      return {CANCEL, net::ERR_ABORTED};
    }
    return DEFER;
  }
  void Decided(AdblockDecision decision) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!pending_) return;
    pending_ = false;
    if (decision.action == AdblockDecision::Action::kAllow &&
        !decision.rewritten_url && decision.replacement_data_url.empty()) {
      Resume();
      return;
    }
    CancelDeferredNavigation({CANCEL,
        decision.action == AdblockDecision::Action::kBlock
            ? net::ERR_BLOCKED_BY_CLIENT : net::ERR_NOT_IMPLEMENTED});
  }
  const std::shared_ptr<AdblockProfileState> state_;
  const GURL source_;
  bool pending_ = false;
  base::WeakPtrFactory<AdblockNavigation> weak_{this};
};
}

void AddAdblockNavigationThrottle(content::NavigationThrottleRegistry& registry) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto& navigation = registry.GetNavigationHandle();
  if (!NativeHostEnabled() || !EligibleFrame(navigation) ||
      !navigation.GetURL().SchemeIsHTTPOrHTTPS() ||
      registry.HasThrottle("BoazAdblockNavigation")) return;
  auto state = NativeBlockingState(Profile::FromBrowserContext(
      navigation.GetWebContents()->GetBrowserContext()));
  if (!state) return;
  GURL source;
  const auto& initiator = navigation.GetInitiatorOrigin();
  if (initiator) {
    if (initiator->opaque() || !initiator->GetURL().SchemeIsHTTPOrHTTPS()) return;
    source = initiator->GetURL();
  } else if (navigation.IsInPrimaryMainFrame() && !navigation.IsRendererInitiated()) {
    source = navigation.GetURL();
  } else {
    // Missing frame/worker authority cannot be substituted with a destination identity.
    return;
  }
  registry.AddThrottle(std::make_unique<AdblockNavigation>(registry, std::move(state), std::move(source)));
}
}
