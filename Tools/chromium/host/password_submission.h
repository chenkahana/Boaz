#ifndef BOAZ_CHROMIUM_PASSWORD_SUBMISSION_H_
#define BOAZ_CHROMIUM_PASSWORD_SUBMISSION_H_
#include <cstdint>
#include <optional>
#include <string>
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "url/origin.h"
namespace content { class BrowserContext; }
namespace boaz {
class PasswordSubmission final : public content::WebContentsObserver {
 public:
  struct Credential { std::string username; std::string password; };
  enum class Status { kConfirmed, kInvalidTarget, kPrivate, kInvalidArgument,
                      kBusy, kDuplicate, kDismissed, kNavigation, kRendererFailed,
                      kClosed };
  struct Outcome {
    Status status;
    std::optional<Credential> credential;
    std::optional<url::Origin> origin;
  };
  using Completion = base::OnceCallback<void(Outcome)>;
  // Prompt receives browser-authoritative origin and username, never password.
  using Prompt = base::OnceCallback<void(url::Origin, std::string,
                                        base::OnceCallback<void(bool)>)>;
  explicit PasswordSubmission(content::WebContents* contents);
  ~PasswordSubmission() override;
  void Submit(content::RenderFrameHost* frame, Credential credential,
              Prompt prompt, Completion completion);
  void Close();
 private:
  struct Pending {
    uint64_t id;
    uint64_t epoch;
    content::GlobalRenderFrameHostId frame;
    content::WeakDocumentPtr document;
    url::Origin origin;
    Credential credential;
    Completion completion;
  };
  bool Eligible(content::RenderFrameHost* frame) const;
  bool Valid() const;
  void Show(uint64_t id, Prompt prompt);
  void Confirm(uint64_t id, bool accepted);
  void Finish(Status status);
  void Cancel(Status status);
  static void Post(Completion completion, Outcome outcome);
  void DidStartNavigation(content::NavigationHandle*) override;
  void RenderFrameDeleted(content::RenderFrameHost*) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  raw_ptr<content::BrowserContext> profile_ = nullptr;
  std::optional<Pending> pending_;
  uint64_t epoch_ = 1;
  uint64_t next_id_ = 1;
  bool closed_ = false;
  base::WeakPtrFactory<PasswordSubmission> weak_factory_{this};
};
}
#endif
