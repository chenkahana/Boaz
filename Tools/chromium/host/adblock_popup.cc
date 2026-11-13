#include "adblock_popup.h"
#include <optional>
#include <utility>
#include "adblock_profile_state.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
namespace boaz {
namespace {
bool IsBlank(const GURL& url) { return url.is_empty() || url.IsAboutBlank(); }
class Popup final : public content::WebContentsObserver,
                    public content::WebContentsUserData<Popup> {
 public:
  ~Popup() override = default;
  base::WeakPtr<Popup> Claim(content::NavigationHandle& navigation) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    if (retired_ || !navigation.IsInPrimaryMainFrame() || navigation.IsSameDocument()) return {};
    if (!navigation.GetURL().SchemeIsHTTPOrHTTPS()) {
      if (!IsBlank(navigation.GetURL())) Retire();
      return {};
    }
    if (navigation_id_ && *navigation_id_ != navigation.GetNavigationId()) return {};
    navigation_id_ = navigation.GetNavigationId();
    return weak_.GetWeakPtr();
  }
  content::NavigationThrottle::ThrottleCheckResult Check(content::NavigationHandle& navigation) {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    using Throttle = content::NavigationThrottle;
    if (retired_ || navigation_id_ != navigation.GetNavigationId()) return Throttle::PROCEED;
    if (!navigation.GetURL().SchemeIsHTTPOrHTTPS()) {
      if (!IsBlank(navigation.GetURL())) Retire();
      return Throttle::PROCEED;
    }
    const auto result = state_->Evaluate(navigation.GetURL(), opener_url_, "popup",
                                         navigation.GetRequestMethod(), top_origin_);
    if (result.action == AdblockDecision::Action::kAllow &&
        !result.rewritten_url && result.replacement_data_url.empty()) return Throttle::PROCEED;
    const bool blocked = result.action == AdblockDecision::Action::kBlock;
    auto close = std::move(close_owned_);
    Retire();
    if (close) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, std::move(close));
    return {Throttle::CANCEL, blocked ? net::ERR_BLOCKED_BY_CLIENT : net::ERR_NOT_IMPLEMENTED};
  }
 private:
  friend class content::WebContentsUserData<Popup>;
  Popup(content::WebContents* contents, GURL opener, url::Origin top,
        std::shared_ptr<AdblockProfileState> state, base::OnceClosure close)
      : content::WebContentsObserver(contents), content::WebContentsUserData<Popup>(*contents),
        opener_url_(std::move(opener)), top_origin_(std::move(top)),
        state_(std::move(state)), close_owned_(std::move(close)) {}
  void Retire() {
    retired_ = true;
    close_owned_.Reset();
    state_.reset();
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void WebContentsDestroyed() override;
  GURL opener_url_;
  url::Origin top_origin_;
  std::shared_ptr<AdblockProfileState> state_;
  base::OnceClosure close_owned_;
  std::optional<int64_t> navigation_id_;
  bool retired_ = false;
  base::WeakPtrFactory<Popup> weak_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(Popup);
void Popup::DidFinishNavigation(content::NavigationHandle* navigation) {
    if (retired_ || !navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) return;
    if ((navigation_id_ && *navigation_id_ == navigation->GetNavigationId()) ||
        !IsBlank(navigation->GetURL())) Retire();
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
  ThrottleCheckResult Check() { return popup_ ? popup_->Check(*navigation_handle()) : PROCEED; }
  base::WeakPtr<Popup> popup_;
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
  Popup::CreateForWebContents(contents, std::move(opener), std::move(top), std::move(state), std::move(close));
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
