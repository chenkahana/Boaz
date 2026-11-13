#ifndef BOAZ_CHROMIUM_NATIVE_DEVTOOLS_H_
#define BOAZ_CHROMIUM_NATIVE_DEVTOOLS_H_
namespace content { class WebContents; }
namespace boaz {
void* NativePageContainer(content::WebContents* contents);
bool CanDockNativeDevTools(content::WebContents* contents);
void UpdateNativeDevTools(content::WebContents* contents);
void DetachNativeDevTools(content::WebContents* contents);
}
#endif
