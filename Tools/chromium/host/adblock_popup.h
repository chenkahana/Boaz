#ifndef BOAZ_ADBLOCK_POPUP_H_
#define BOAZ_ADBLOCK_POPUP_H_
#include <memory>
#include "base/functional/callback.h"
#include "url/gurl.h"
#include "url/origin.h"
namespace content { class WebContents; class NavigationThrottleRegistry; }
namespace boaz {
class AdblockProfileState;
// Called synchronously at browser-owned new-contents creation, before navigation.
// top_origin is browser-owned opener authority, canonicalized to a schemeful site.
// close_owned must weakly resolve native ownership; never capture raw contents.
bool AttachAdblockBlankPopup(content::WebContents*, const GURL& initial_target,
    GURL opener_url, url::Origin top_origin,
    std::shared_ptr<AdblockProfileState>, base::OnceClosure close_owned);
void AddAdblockPopupThrottle(content::NavigationThrottleRegistry&);
}
#endif
