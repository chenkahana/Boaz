#ifndef BOAZ_CHROMIUM_NATIVE_EXTENSION_DIALOGS_H_
#define BOAZ_CHROMIUM_NATIVE_EXTENSION_DIALOGS_H_
#include <memory>
#include <string>
#include <vector>
#include "base/memory/weak_ptr.h"
#include "ui/gfx/native_ui_types.h"
class BrowserWindowInterface;
class GlobalErrorWithStandardBubble;
namespace content { class WebContents; }
namespace gfx { class Rect; }
namespace ui { class DialogModel; }
namespace boaz {
// Chromium's extension dialogs that point at the toolbar (installed, reload to apply site access, remove several,
// new tab page changed), drawn natively at the extension's button or the extensions button of a Boaz window.
// Takes `model` and returns true; leaves it and returns false when it isn't a Boaz window or the dialog has fields
// Boaz doesn't draw.
bool ShowNativeExtensionDialog(gfx::NativeWindow parent, const std::vector<std::string>& extension_ids,
                               std::unique_ptr<ui::DialogModel>& model);
// Chromium's install failure message for the tab that started the install.
void ShowNativeExtensionInstallError(content::WebContents* contents, const std::u16string& message);
// A standard global error bubble (an extension disabled for new permissions, or installed by another program) as a
// sheet on a Boaz window. Returns false when the window isn't Boaz's.
bool ShowNativeGlobalErrorBubble(BrowserWindowInterface* browser, base::WeakPtr<GlobalErrorWithStandardBubble> error);
// Shows the profile's pending global error bubbles on `browser` when it is the key window, as Chrome's browser
// window does on activation. Owned by the window.
class NativeGlobalErrors {
 public:
  virtual ~NativeGlobalErrors() = default;
  static std::unique_ptr<NativeGlobalErrors> Create(BrowserWindowInterface* browser);
};
// Implemented by the window bridge: where a dialog for these extensions points in a Boaz window.
bool FindNativeExtensionAnchor(void* nswindow, const std::vector<std::string>& extension_ids, void** nsview,
                               gfx::Rect* bounds);
}
#endif
