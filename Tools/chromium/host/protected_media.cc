#include "protected_media.h"
#include "bootstrap.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/self_deleting.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_util.h"
#include "base/task/single_thread_task_runner.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/document_service.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
namespace boaz {
namespace {
bool Eligible(content::RenderFrameHost* frame) {
  auto* contents = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  return NativeHostEnabled() && contents && !contents->IsBeingDestroyed() &&
      frame == contents->GetPrimaryMainFrame() && !contents->GetController().GetPendingEntry() && frame->IsActive() &&
      frame->IsRenderFrameLive() && frame->GetLastCommittedURL().SchemeIsHTTPOrHTTPS() &&
      !frame->GetLastCommittedOrigin().opaque();
}
class Observer final : public content::DocumentService<mojom::EncryptedMediaObserver> {
 public:
  Observer(content::RenderFrameHost& frame,
      mojo::PendingReceiver<mojom::EncryptedMediaObserver> receiver, base::SelfDeletingPassKey key);
  void Requested(const std::string& key) override;
 private:
  ~Observer() override;
  void Deliver(std::string key);
  bool requested_ = false;
  base::WeakPtrFactory<Observer> weak_{this};
};
Observer::Observer(content::RenderFrameHost& frame,
    mojo::PendingReceiver<mojom::EncryptedMediaObserver> receiver, base::SelfDeletingPassKey key)
    : DocumentService(frame, std::move(receiver), key) {}
Observer::~Observer() = default;
void Observer::Requested(const std::string& key) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (requested_ || !Eligible(&render_frame_host()) || key.size() > 128 ||
      !base::IsStringASCII(key) ||
      !(key == "com.widevine.alpha" || key == "com.microsoft.playready" ||
        key.starts_with("com.microsoft.playready."))) return;
  requested_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&Observer::Deliver, weak_.GetWeakPtr(), key));
}
void Observer::Deliver(std::string key) {
  if (Eligible(&render_frame_host())) ReportProtectedMediaRequest(&render_frame_host(), key);
}
}
void BindProtectedMediaObserver(content::RenderFrameHost* frame,
    mojo::PendingReceiver<mojom::EncryptedMediaObserver> receiver) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (Eligible(frame)) base::MakeSelfDeleting<Observer>(*frame, std::move(receiver));
}
}
