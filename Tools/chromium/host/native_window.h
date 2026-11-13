#ifndef BOAZ_CHROMIUM_NATIVE_WINDOW_H_
#define BOAZ_CHROMIUM_NATIVE_WINDOW_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "chrome/browser/ui/browser_window_deleter.h"

class BrowserWindow;
class BrowserWindowInterface;
namespace input { struct NativeWebKeyboardEvent; }

namespace boaz {
struct NativeWindowServices {
  base::RepeatingClosure request_close;
  base::RepeatingCallback<void*()> content_view;
  base::RepeatingCallback<void*()> address_field;
  base::RepeatingClosure focus_address;
  base::RepeatingClosure focus_toolbar;
  base::RepeatingCallback<bool(const input::NativeWebKeyboardEvent&)> handle_key;
  base::RepeatingCallback<void(const std::string&, bool)> exclusive_access_notice;
};

std::unique_ptr<BrowserWindow, BrowserWindowDeleter> CreateNativeBrowserWindow(
    BrowserWindowInterface* browser, void* nswindow,
    const NativeWindowServices& services);
}  // namespace boaz
#endif
