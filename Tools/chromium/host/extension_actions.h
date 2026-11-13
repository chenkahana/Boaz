#ifndef BOAZ_CHROMIUM_EXTENSION_ACTIONS_H_
#define BOAZ_CHROMIUM_EXTENSION_ACTIONS_H_
#include <memory>
#include <string>
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace gfx { class Rect; }
namespace boaz {
class NativeExtensionActions {
 public:
  enum class Result { kOk, kInvalidTarget, kUnavailable, kInvalidAnchor, kUnsupported };
  explicit NativeExtensionActions(BrowserWindowInterface* browser);
  ~NativeExtensionActions();
  // Only call directly from a real native action-button activation.
  Result Invoke(content::WebContents* expected_active, const std::string& extension_id,
                void* anchor_nsview, const gfx::Rect& anchor_bounds);
  void ClosePopup();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
#endif
