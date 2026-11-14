#ifndef BOAZ_CHROMIUM_NATIVE_DEVTOOLS_H_
#define BOAZ_CHROMIUM_NATIVE_DEVTOOLS_H_
#include <optional>
#include <string>
#include "base/functional/callback.h"
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace boaz {
void RegisterNativeDevToolsPreferences(BrowserWindowInterface*, base::RepeatingCallback<void(int, int)>);
void UnregisterNativeDevToolsPreferences(BrowserWindowInterface*);
bool SetNativeDevToolsPreferences(BrowserWindowInterface*, int current, int last);
std::optional<std::string> GetNativeDevToolsPreference(content::WebContents*, const std::string& name);
bool SetNativeDevToolsPreference(content::WebContents*, const std::string& name, const std::string& value);
bool RemoveNativeDevToolsPreference(content::WebContents*, const std::string& name);
std::optional<int> NativeDevToolsDockSide(content::WebContents*);
void* NativePageContainer(content::WebContents* contents);
bool CanDockNativeDevTools(content::WebContents* contents);
void UpdateNativeDevTools(content::WebContents* contents);
void DetachNativeDevTools(content::WebContents* contents);
}
#endif
