#ifndef BOAZ_CHROMIUM_PAGE_SCROLL_H_
#define BOAZ_CHROMIUM_PAGE_SCROLL_H_
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/web_contents_observer.h"
namespace boaz {
// Reads where the primary document is scrolled from its layout, without running page script, so it also works on a
// saved MHTML page, whose sandbox has scripts off.
class PageScroll final : public content::WebContentsObserver,
                         public content::DevToolsAgentHostClient {
 public:
  enum class Result { kSuccess, kInvalid, kUnavailable, kProtocolError, kTimeout, kNavigation, kClosed };
  using Completion = base::OnceCallback<void(Result, double x, double y)>;
  explicit PageScroll(content::WebContents* contents);
  ~PageScroll() override;
  void Read(Completion completion);
  void Close();
 private:
  void Finish(Result result, double x = 0, double y = 0);
  void DispatchProtocolMessage(content::DevToolsAgentHost*, base::span<const uint8_t>) override;
  void AgentHostClosed(content::DevToolsAgentHost*) override;
  bool MayAttachToURL(const GURL&, bool is_webui) override;
  bool MayAttachToRenderFrameHost(content::RenderFrameHost*) override;
  bool IsTrusted() override;
  bool MayReadLocalFiles() override;
  bool MayWriteLocalFiles() override;
  bool AllowUnsafeOperations() override;
  void DidStartNavigation(content::NavigationHandle*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  scoped_refptr<content::DevToolsAgentHost> host_;
  Completion completion_;
  base::OneShotTimer timer_;
  int next_id_ = 0;
  bool closed_ = false;
  base::WeakPtrFactory<PageScroll> weak_{this};
};
}
#endif
