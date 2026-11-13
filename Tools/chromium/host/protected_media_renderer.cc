#include "boaz/protected_media_renderer.h"

#include "base/strings/string_util.h"
#include "boaz/protected_media.mojom.h"
#include "content/public/renderer/render_frame.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/blink/public/common/browser_interface_broker_proxy.h"

namespace boaz {
namespace {

class ProtectedMediaObserver final
    : public content::RenderFrameObserver,
      public content::RenderFrameObserverTracker<ProtectedMediaObserver> {
 public:
  explicit ProtectedMediaObserver(content::RenderFrame* frame);
  ~ProtectedMediaObserver() override;

  void Requested(const std::string& key_system);
  void DidCommitProvisionalLoad(ui::PageTransition transition) override;
  void OnDestruct() override;

 private:
  mojo::Remote<mojom::EncryptedMediaObserver> remote_;
  bool requested_ = false;
};

ProtectedMediaObserver::ProtectedMediaObserver(content::RenderFrame* frame)
    : content::RenderFrameObserver(frame),
      content::RenderFrameObserverTracker<ProtectedMediaObserver>(frame) {}

ProtectedMediaObserver::~ProtectedMediaObserver() = default;

void ProtectedMediaObserver::Requested(const std::string& key_system) {
  if (requested_) {
    return;
  }
  requested_ = true;
  render_frame()->GetBrowserInterfaceBroker().GetInterface(
      remote_.BindNewPipeAndPassReceiver());
  remote_->Requested(key_system);
}

void ProtectedMediaObserver::DidCommitProvisionalLoad(ui::PageTransition) {
  remote_.reset();
  requested_ = false;
}

void ProtectedMediaObserver::OnDestruct() {
  delete this;
}

}  // namespace

void ObserveKeySystemRequest(content::RenderFrame* frame,
                             const std::string& key_system) {
  if (!frame || !frame->IsMainFrame() || frame->IsInFencedFrameTree() ||
      key_system.empty() || key_system.size() > 128 ||
      !base::IsStringASCII(key_system) ||
      (key_system != "com.widevine.alpha" &&
       !key_system.starts_with("com.microsoft.playready"))) {
    return;
  }
  auto* observer = ProtectedMediaObserver::Get(frame);
  if (!observer) {
    observer = new ProtectedMediaObserver(frame);
  }
  observer->Requested(key_system);
}

}  // namespace boaz
