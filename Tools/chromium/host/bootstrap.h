#ifndef BOAZ_CHROMIUM_BOOTSTRAP_H_
#define BOAZ_CHROMIUM_BOOTSTRAP_H_
#include <memory>
#include <string>
#include <vector>
#include "chrome/browser/ui/browser_window_deleter.h"
namespace content { class RenderFrameHost; class WebContents; }
class BrowserWindow;
class BrowserWindowInterface;
class ChromeBrowserMainExtraParts;
namespace boaz {
void ReportNativePasswordSubmission(content::WebContents*, std::string origin, std::string username, std::string password);
void ReportProtectedMediaRequest(content::RenderFrameHost* frame, const std::string& key);
bool NativeHostEnabled();
bool ShouldDisableJavaScript(content::WebContents* contents);
bool ShouldRetainEmptyBrowser(BrowserWindowInterface* browser);
bool RouteExternalURLs(std::vector<std::string> urls);
std::unique_ptr<ChromeBrowserMainExtraParts> CreateNativeHostMainParts();
std::unique_ptr<BrowserWindow, BrowserWindowDeleter>
CreateNativeHostBrowserWindow(BrowserWindowInterface* browser);
bool IsNativeHostBrowser(BrowserWindowInterface* browser);
}
#endif
