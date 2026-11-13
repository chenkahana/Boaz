#ifndef BOAZ_CHROMIUM_PAGE_EMULATION_H_
#define BOAZ_CHROMIUM_PAGE_EMULATION_H_

#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/web_contents_observer.h"

namespace boaz {
class PageEmulation final : public content::WebContentsObserver,
                            public content::DevToolsAgentHostClient {
 public:
  struct Viewport {
    int width;
    int height;
    double dpr;
    bool mobile;
    bool touch;
    int max_touch_points;
    bool landscape;
  };
  enum class Result { kSuccess, kInvalid, kUnavailable, kProtocolError,
                      kTimeout, kNavigation, kClosed };
  using Completion = base::OnceCallback<void(Result)>;
  explicit PageEmulation(content::WebContents* contents);
  ~PageEmulation() override;
  void Apply(Viewport viewport, Completion completion);
  void Clear(Completion completion);
  void Close();

 private:
  void Start(bool clear, Completion completion);
  void SendNext();
  void Fail(Result result);
  void Finish(Result result);
  void Cancel(Result result);
  void Detach();
  static void Reply(Completion completion, Result result);
  void DispatchProtocolMessage(content::DevToolsAgentHost*, base::span<const uint8_t>) override;
  void AgentHostClosed(content::DevToolsAgentHost*) override;
  bool MayAttachToURL(const GURL&, bool is_webui) override;
  bool MayAttachToRenderFrameHost(content::RenderFrameHost*) override;
  bool IsTrusted() override { return false; }
  bool MayReadLocalFiles() override { return false; }
  bool MayWriteLocalFiles() override { return false; }
  bool AllowUnsafeOperations() override { return false; }
  void DidStartNavigation(content::NavigationHandle*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;

  scoped_refptr<content::DevToolsAgentHost> host_;
  Viewport viewport_{};
  Completion completion_;
  base::OneShotTimer timer_;
  int next_id_ = 0;
  int pending_id_ = 0;
  int step_ = 0;
  bool clearing_ = false;
  bool resetting_ = false;
  bool closed_ = false;
  Result failure_ = Result::kProtocolError;
  base::WeakPtrFactory<PageEmulation> weak_factory_{this};
};
}  // namespace boaz
#endif
