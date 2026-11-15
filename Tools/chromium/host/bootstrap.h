#ifndef BOAZ_CHROMIUM_BOOTSTRAP_H_
#define BOAZ_CHROMIUM_BOOTSTRAP_H_
#include <memory>
#include <string>
#include <vector>
#include "chrome/browser/ui/browser_window_deleter.h"
namespace content { class RenderFrameHost; class WebContents; }
class GURL;
class Profile;
class BrowserWindow;
class BrowserWindowInterface;
class ChromeBrowserMainExtraParts;
namespace boaz {
class AdblockProfileState;
std::shared_ptr<AdblockProfileState> NativeBlockingState(Profile*);
void ReportNativePasswordSubmission(content::WebContents*, std::string origin, std::string username, std::string password);
void ReportProtectedMediaRequest(content::RenderFrameHost* frame, const std::string& key);
bool PageAssistantEnabled(content::WebContents* contents);
void AskAboutPage(content::WebContents* contents, const std::u16string& selection);
// Boaz's own context-menu items that Boaz runs itself (RunContextMenuCommand): Share… for a page or link, Share… for
// an image, and Send to Your Devices. Free ids in the content range.
inline constexpr int kShareCommandId = 50903;
inline constexpr int kShareImageCommandId = 50904;
inline constexpr int kSendToDevicesCommandId = 50905;
// Context-menu commands that Boaz runs itself on the native host: Chromium's Open Link in Incognito, Open Link in
// Split View and Create QR Code, and Boaz's items above. Run returns false when Chromium should run the command.
bool ContextMenuCommandAvailable(content::WebContents* contents, int command);
bool RunContextMenuCommand(content::WebContents* contents, int command, const GURL& url, const std::u16string& text);
// The context menu's Google Lens items: Google Lens results for an image or the visible page in a new tab, whatever
// the default search engine is.
void SearchImageWithGoogleLens(content::WebContents* contents, content::RenderFrameHost* frame, const GURL& image_url);
void SearchPageWithGoogleLens(content::WebContents* contents);
bool NativeHostEnabled();
bool AutomaticPictureInPictureEnabled();
bool IsNativeExtensionPromptContext(Profile*, void* native_window);
void NativeExtensionPromptsChanged();
bool ShouldDisableJavaScript(content::WebContents* contents);
bool ShouldRetainEmptyBrowser(BrowserWindowInterface* browser);
bool RouteExternalURLs(std::vector<std::string> urls);
bool RouteNativeReopen();
std::unique_ptr<ChromeBrowserMainExtraParts> CreateNativeHostMainParts();
std::unique_ptr<BrowserWindow, BrowserWindowDeleter>
CreateNativeHostBrowserWindow(BrowserWindowInterface* browser);
bool IsNativeHostBrowser(BrowserWindowInterface* browser);
}
#endif
