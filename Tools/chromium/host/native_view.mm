#import <AppKit/AppKit.h>

#include "tab_registry.h"
#include "native_devtools.h"

#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"

namespace boaz {

void* NativeViewForContents(content::WebContents* contents) {
  if (!contents ||
      !content::BrowserThread::CurrentlyOn(content::BrowserThread::UI) ||
      ![NSThread isMainThread]) {
    return nullptr;
  }
  return NativePageContainer(contents);
}

}  // namespace boaz
