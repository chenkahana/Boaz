#ifndef BOAZ_ADBLOCK_POPUP_HOST_H_
#define BOAZ_ADBLOCK_POPUP_HOST_H_
#include "content/public/browser/global_routing_id.h"
class BrowserWindowInterface;
class GURL;
namespace content { class WebContents; }
namespace boaz {
void AttachNativePopupBlocking(BrowserWindowInterface*, content::WebContents* source,
    const content::GlobalRenderFrameHostId& opener, const GURL& target,
    content::WebContents* created);
}
#endif
