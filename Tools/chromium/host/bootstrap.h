#ifndef BOAZ_CHROMIUM_BOOTSTRAP_H_
#define BOAZ_CHROMIUM_BOOTSTRAP_H_
#include <memory>
#include <string>
#include <vector>
#include "chrome/browser/ui/browser_window_deleter.h"
class BrowserWindow;
class BrowserWindowInterface;
class ChromeBrowserMainExtraParts;
namespace boaz {
bool NativeHostEnabled();
bool ShouldRetainEmptyBrowser(BrowserWindowInterface* browser);
bool RouteExternalURLs(std::vector<std::string> urls);
std::unique_ptr<ChromeBrowserMainExtraParts> CreateNativeHostMainParts();
std::unique_ptr<BrowserWindow, BrowserWindowDeleter>
CreateNativeHostBrowserWindow(BrowserWindowInterface* browser);
bool IsNativeHostBrowser(BrowserWindowInterface* browser);
}
#endif
