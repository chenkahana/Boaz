#ifndef BOAZ_CHROMIUM_TRUSTED_SCRIPT_CHANNEL_H_
#define BOAZ_CHROMIUM_TRUSTED_SCRIPT_CHANNEL_H_
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include "trusted_execution.h"
#include "content/public/browser/web_contents_observer.h"

namespace boaz {
// UI-thread only. Sources come from trusted application code, never page input.
// Close/destruction posts pending completions; shutdown must drain those tasks.
class TrustedScriptChannel final : public content::WebContentsObserver {
 public:
  explicit TrustedScriptChannel(content::WebContents* contents);
  ~TrustedScriptChannel() override;
  std::optional<uint64_t> Capture(std::string* origin = nullptr, bool focused = false);
  std::optional<uint64_t> Clone(uint64_t token);
  bool Release(uint64_t token);
  void Execute(uint64_t token, std::u16string trusted_function_source,
               base::DictValue arguments, TrustedExecution::Completion completion);
  void Close();
 private:
  void DidStartNavigation(content::NavigationHandle*) override;
  void RenderFrameDeleted(content::RenderFrameHost*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  TrustedExecution executor_;
  std::map<uint64_t, TrustedExecution::Target> targets_;
  bool closed_ = false;
};
}  // namespace boaz
#endif
