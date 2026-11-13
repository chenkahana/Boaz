#include "adblock_popup_host.h"
#include "adblock_popup.h"
#include "bootstrap.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "url/gurl.h"
namespace boaz {
void AttachNativePopupBlocking(BrowserWindowInterface* browser, content::WebContents* source,
    const content::GlobalRenderFrameHostId& opener_id, const GURL& target,
    content::WebContents* created) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!NativeHostEnabled() || !browser || !IsNativeHostBrowser(browser) ||
      !source || !created || source->GetBrowserContext() != created->GetBrowserContext() ||
      browser->GetProfile() != created->GetBrowserContext()) return;
  auto* opener = content::RenderFrameHost::FromID(opener_id);
  auto* top = source->GetPrimaryMainFrame();
  if (!opener || !opener->IsActive() || opener->IsNestedWithinFencedFrame() ||
      content::WebContents::FromRenderFrameHost(opener) != source || !top || !top->IsActive() ||
      opener->GetOutermostMainFrame() != top || opener->GetLastCommittedOrigin().opaque()) return;
  auto state = NativeBlockingState(browser->GetProfile());
  if (!state) return;
  AttachAdblockBlankPopup(created, target, opener->GetLastCommittedURL(),
      top->GetLastCommittedOrigin(), std::move(state),
      base::BindOnce([](base::WeakPtr<content::WebContents> contents) {
        if (!contents) return;
        auto* owner = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents.get());
        if (!owner || !IsNativeHostBrowser(owner)) return;
        auto* tabs = owner->GetTabStripModel();
        const int index = tabs->GetIndexOfWebContents(contents.get());
        if (index != TabStripModel::kNoTab)
          tabs->CloseWebContentsAt(index, TabCloseTypes::CLOSE_NONE);
      }, created->GetWeakPtr()));
}
}
