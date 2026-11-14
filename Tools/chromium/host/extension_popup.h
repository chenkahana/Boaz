#ifndef BOAZ_CHROMIUM_EXTENSION_POPUP_H_
#define BOAZ_CHROMIUM_EXTENSION_POPUP_H_
#include <memory>
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"
class BrowserWindowInterface;
namespace extensions { class ExtensionViewHost; }
namespace boaz {
// UI-thread only. Caller owns this object, including after Close().
class NativeExtensionPopup {
 public:
  static std::unique_ptr<NativeExtensionPopup> Create(
      std::unique_ptr<extensions::ExtensionViewHost> host,
      BrowserWindowInterface* browser, void* anchor_nsview,
      gfx::Rect anchor_rect, PopupShowAction show_action,
      ShowPopupCallback callback);
  ~NativeExtensionPopup();
  void Close();
  bool IsShowing() const;
  gfx::NativeView GetNativeView() const;
 private:
  class Impl;
  explicit NativeExtensionPopup(std::unique_ptr<Impl> impl);
  std::unique_ptr<Impl> impl_;
};
}  // namespace boaz
#endif
