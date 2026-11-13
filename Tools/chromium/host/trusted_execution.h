#ifndef BOAZ_CHROMIUM_TRUSTED_EXECUTION_H_
#define BOAZ_CHROMIUM_TRUSTED_EXECUTION_H_
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "url/origin.h"
namespace content { class BrowserContext; }
namespace boaz {
class TrustedExecution final : public content::WebContentsObserver {
 public:
  enum class Status { kSuccess, kInvalidTarget, kNavigation, kClosed,
                      kRendererFailed, kTimeout, kInvalidArgument, kBusy };
  struct Outcome { Status status; base::Value value; };
  struct Target {
    content::GlobalRenderFrameHostId frame;
    content::WeakDocumentPtr document;
    url::Origin origin;
    uint64_t epoch;
  };
  using Completion = base::OnceCallback<void(Outcome)>;
  explicit TrustedExecution(content::WebContents* contents);
  ~TrustedExecution() override;
  std::optional<Target> CaptureTarget() const;
  void Execute(Target target, std::u16string trusted_function_source,
               base::DictValue arguments, Completion completion);
  void Close();
 private:
  struct Pending { Target target; Completion completion; };
  bool Validate(const Target& target) const;
  static void Post(Completion completion, Outcome outcome);
  void Finish(uint64_t id, Status status, base::Value result = base::Value());
  void Result(uint64_t id, base::Value result);
  void Cancel(Status status);
  void DidStartNavigation(content::NavigationHandle*) override;
  void RenderFrameDeleted(content::RenderFrameHost*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  raw_ptr<content::BrowserContext> profile_;
  uint64_t epoch_ = 1;
  uint64_t next_id_ = 1;
  bool closed_ = false;
  std::map<uint64_t, Pending> pending_;
  base::WeakPtrFactory<TrustedExecution> weak_factory_{this};
};
}
#endif
