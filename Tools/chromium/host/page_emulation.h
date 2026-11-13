#ifndef BOAZ_CHROMIUM_PAGE_EMULATION_H_
#define BOAZ_CHROMIUM_PAGE_EMULATION_H_

#include <optional>
#include <string>
#include <vector>
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
  struct Media {
    enum class MediaType { kScreen, kPrint };
    enum class Preference { kDefault, kFirst, kSecond };
    enum class Vision { kNone, kBlurred, kReducedContrast, kAchromatopsia,
                        kDeuteranopia, kProtanopia, kTritanopia };
    MediaType type = MediaType::kScreen;
    Preference color_scheme = Preference::kDefault;
    Preference reduced_motion = Preference::kDefault;
    Preference contrast = Preference::kDefault;
    bool forced_colors = false;
    Vision vision = Vision::kNone;
  };
  struct Network {
    bool offline;
    double latency_ms;
    double download_bytes_per_second;
    double upload_bytes_per_second;
  };
  struct BrandVersion { std::string brand; std::string version; };
  struct UserAgentDefaults {
    std::string user_agent;
    std::string navigator_platform;
    std::vector<BrandVersion> brands;
    std::vector<BrandVersion> full_version_list;
    std::string full_version, platform, platform_version, architecture, model, bitness;
    bool mobile = false;
    bool wow64 = false;
    std::vector<std::string> form_factors;
  };
  static std::optional<UserAgentDefaults> GetDefaultUserAgent();
  enum class Result { kSuccess, kInvalid, kUnavailable, kProtocolError,
                      kTimeout, kNavigation, kClosed };
  using Completion = base::OnceCallback<void(Result)>;
  void ApplyNetwork(std::optional<Network> network, Completion completion);
  void ApplyCPU(double rate, Completion completion);
  void ApplyMedia(std::optional<Media> media, Completion completion);
  void ApplyUserAgent(std::optional<std::string> user_agent, Completion completion);
  explicit PageEmulation(content::WebContents* contents);
  ~PageEmulation() override;
  void Apply(Viewport viewport, Completion completion);
  void Clear(Completion completion);
  void Close();

 private:
  enum class Operation { kViewport, kUserAgent, kMedia, kNetwork, kCPU };
  void Start(bool clear, Operation operation, Completion completion);
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
  bool IsTrusted() override;
  bool MayReadLocalFiles() override;
  bool MayWriteLocalFiles() override;
  bool AllowUnsafeOperations() override;
  void DidStartNavigation(content::NavigationHandle*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;

  scoped_refptr<content::DevToolsAgentHost> host_;
  Viewport viewport_{};
  Media media_{};
  Network network_{};
  double cpu_rate_ = 1.0;
  std::string user_agent_;
  Operation operation_ = Operation::kViewport;
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
