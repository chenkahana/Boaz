#include "adblock_popup.h"
#include <optional>
#include <set>
#include <string>
#include <utility>
#include "adblock_profile_state.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/task/thread_pool.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "net/base/net_errors.h"
#include "net/base/schemeful_site.h"
namespace boaz {
namespace {
bool IsBlank(const GURL& url) { return url.is_empty() || url.IsAboutBlank(); }
class Popup final : public content::WebContentsObserver,
                    public content::WebContentsUserData<Popup> {
 public:
  ~Popup() override = default;
  base::WeakPtr<Popup> Claim(content::NavigationHandle& navigation) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!navigation.IsInPrimaryMainFrame() || navigation.IsSameDocument()) return {};
    if (denied_) return weak_.GetWeakPtr();
    if (retired_) return {};
    if (!navigation.GetURL().SchemeIsHTTPOrHTTPS()) {
      return {};
    }
    active_navigations_.insert(navigation.GetNavigationId());
    if (!current_navigation_) current_navigation_ = navigation.GetNavigationId();
    return weak_.GetWeakPtr();
  }
  content::NavigationThrottle::ThrottleCheckResult Check(content::NavigationHandle& navigation) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    using Throttle = content::NavigationThrottle;
    if (denied_) return {Throttle::CANCEL, net::ERR_BLOCKED_BY_CLIENT};
    if (retired_ || !active_navigations_.contains(navigation.GetNavigationId())) return Throttle::PROCEED;
    if (!navigation.GetURL().SchemeIsHTTPOrHTTPS()) {
      return Throttle::PROCEED;
    }
    if (current_navigation_ != navigation.GetNavigationId())
      return {Throttle::CANCEL, net::ERR_ABORTED};
    return Throttle::DEFER;
  }
  struct Input {
    std::shared_ptr<AdblockProfileState> state;
    GURL opener;
    std::optional<net::SchemefulSite> top;
  };
  Input Capture() const { return {state_, opener_url_, top_level_site_}; }
  content::NavigationThrottle::ThrottleCheckResult Apply(
      content::NavigationHandle& navigation, const AdblockDecision& result) {
    using Throttle = content::NavigationThrottle;
    const auto eligibility = Check(navigation);
    if (eligibility.action() != Throttle::DEFER) return eligibility;
    if (result.action == AdblockDecision::Action::kAllow &&
        !result.rewritten_url && result.replacement_data_url.empty()) return Throttle::PROCEED;
    const bool blocked = result.action == AdblockDecision::Action::kBlock;
    denied_ = true;
    auto close = std::move(close_owned_);
    Retire();
    if (close) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, std::move(close));
    return {Throttle::CANCEL, blocked ? net::ERR_BLOCKED_BY_CLIENT : net::ERR_NOT_IMPLEMENTED};
  }
 private:
  friend class content::WebContentsUserData<Popup>;
  Popup(content::WebContents* contents, GURL opener, net::SchemefulSite top,
        std::shared_ptr<AdblockProfileState> state, base::OnceClosure close)
      : content::WebContentsObserver(contents), content::WebContentsUserData<Popup>(*contents),
        opener_url_(std::move(opener)), top_level_site_(std::move(top)),
        state_(std::move(state)), close_owned_(std::move(close)) {}
  void Retire() {
    retired_ = true;
    active_navigations_.clear();
    close_owned_.Reset();
    state_.reset();
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void WebContentsDestroyed() override;
  GURL opener_url_;
  const std::optional<net::SchemefulSite> top_level_site_;
  std::shared_ptr<AdblockProfileState> state_;
  base::OnceClosure close_owned_;
  std::set<int64_t> active_navigations_;
  std::optional<int64_t> current_navigation_;
  bool retired_ = false;
  bool denied_ = false;
  base::WeakPtrFactory<Popup> weak_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(Popup);
void Popup::DidStartNavigation(content::NavigationHandle* navigation) {
  if (retired_ || !navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) return;
  current_navigation_ = navigation->GetNavigationId();
  if (navigation->GetURL().SchemeIsHTTPOrHTTPS()) {
    // Track replacements before throttle construction without retiring older pending work.
    active_navigations_.insert(navigation->GetNavigationId());
  }
}
void Popup::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (retired_ || !navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) return;
  const bool tracked = active_navigations_.erase(navigation->GetNavigationId()) != 0;
  if (IsBlank(navigation->GetURL())) return;
  // An aborted older request cannot retire another pending request. A committed
  // nonblank document (including an error document) ends blank-popup provenance.
  if (navigation->HasCommitted() || (tracked && active_navigations_.empty())) Retire();
}
void Popup::WebContentsDestroyed() { Retire(); weak_.InvalidateWeakPtrs(); }

class PopupThrottle final : public content::NavigationThrottle {
 public:
  PopupThrottle(content::NavigationThrottleRegistry& registry, base::WeakPtr<Popup> popup)
      : content::NavigationThrottle(registry), popup_(std::move(popup)) {}
  ThrottleCheckResult WillStartRequest() override;
  ThrottleCheckResult WillRedirectRequest() override;
  const char* GetNameForLogging() override;
 private:
  ThrottleCheckResult Check() {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!popup_) return PROCEED;
    const auto eligibility = popup_->Check(*navigation_handle());
    if (eligibility.action() != DEFER) return eligibility;
    DCHECK(!pending_);
    pending_ = true;
    const GURL target = navigation_handle()->GetURL();
    const int64_t id = navigation_handle()->GetNavigationId();
    const bool posted = base::ThreadPool::PostTaskAndReplyWithResult(
        FROM_HERE,
        {base::TaskPriority::USER_VISIBLE, base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
        base::BindOnce([](Popup::Input input, GURL target, std::string method) {
          return input.state->Evaluate(target, input.opener, "popup", method, input.top);
        }, popup_->Capture(), target, navigation_handle()->GetRequestMethod()),
        base::BindOnce(&PopupThrottle::Decided, weak_.GetWeakPtr(), id, target));
    if (!posted) { pending_ = false; return {CANCEL, net::ERR_ABORTED}; }
    return DEFER;
  }
  void Decided(int64_t id, const GURL& target, AdblockDecision result) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (!pending_) return;
    pending_ = false;
    if (!popup_ || navigation_handle()->GetNavigationId() != id ||
        navigation_handle()->GetURL() != target) {
      CancelDeferredNavigation({CANCEL, net::ERR_ABORTED});
      return;
    }
    const auto decision = popup_->Apply(*navigation_handle(), result);
    if (decision.action() == PROCEED) { Resume(); return; }
    CancelDeferredNavigation(decision);
  }
  base::WeakPtr<Popup> popup_;
  bool pending_ = false;
  base::WeakPtrFactory<PopupThrottle> weak_{this};
};
content::NavigationThrottle::ThrottleCheckResult PopupThrottle::WillStartRequest() { return Check(); }
content::NavigationThrottle::ThrottleCheckResult PopupThrottle::WillRedirectRequest() { return Check(); }
const char* PopupThrottle::GetNameForLogging() { return "BoazAdblockPopup"; }
}
bool AttachAdblockBlankPopup(content::WebContents* contents, const GURL& target,
    GURL opener, url::Origin top, std::shared_ptr<AdblockProfileState> state,
    base::OnceClosure close) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!contents || !IsBlank(target) || !opener.SchemeIsHTTPOrHTTPS() || top.opaque() ||
      !top.GetURL().SchemeIsHTTPOrHTTPS() || !state || !close || Popup::FromWebContents(contents)) return false;
  Popup::CreateForWebContents(contents, std::move(opener), net::SchemefulSite(top), std::move(state), std::move(close));
  return true;
}
void AddAdblockPopupThrottle(content::NavigationThrottleRegistry& registry) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto& navigation = registry.GetNavigationHandle();
  auto* popup = Popup::FromWebContents(navigation.GetWebContents());
  if (!popup || registry.HasThrottle("BoazAdblockPopup")) return;
  auto claimed = popup->Claim(navigation);
  if (claimed) registry.AddThrottle(std::make_unique<PopupThrottle>(registry, std::move(claimed)));
}
}
