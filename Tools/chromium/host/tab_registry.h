#ifndef BOAZ_CHROMIUM_TAB_REGISTRY_H_
#define BOAZ_CHROMIUM_TAB_REGISTRY_H_

#include <memory>
#include "boaz_host.h"
#include "trusted_execution.h"

class Browser;
namespace content { class WebContents; }

namespace boaz {

// Implemented by the AppKit bridge; does not transfer native-view ownership.
void* NativeViewForContents(content::WebContents* contents);

// UI-thread adapter. Chromium retains Browser, TabStripModel and WebContents.
class TabRegistry {
 public:
  TabRegistry();
  ~TabRegistry();
  TabRegistry(const TabRegistry&) = delete;
  TabRegistry& operator=(const TabRegistry&) = delete;

  BoazHostResult SetCallbacks(const BoazHostCallbacks* callbacks);
  BoazHostWindow RegisterWindow(Browser* browser, void* native_window);
  BoazHostResult CreatePage(BoazHostWindow window, const char* url,
                            BoazHostPage* page);
  BoazHostResult Navigate(BoazHostPage page, const char* url);
  BoazHostResult GoBack(BoazHostPage page);
  BoazHostResult GoForward(BoazHostPage page);
  BoazHostResult Reload(BoazHostPage page);
  BoazHostResult SetAudioMuted(BoazHostPage page, bool muted);
  BoazHostResult ActivatePage(BoazHostPage page, bool focus);
  BoazHostResult GetNativeView(BoazHostPage page, void** native_view);
  BoazHostResult CaptureDocument(BoazHostPage page, BoazHostDocument* document);
  BoazHostResult ReleaseDocument(BoazHostPage page, BoazHostDocument document);
  BoazHostResult ExecuteTrusted(BoazHostPage page, BoazHostDocument document,
      std::u16string source, base::DictValue arguments, TrustedExecution::Completion completion);
  BoazHostResult ClosePage(BoazHostPage page);
  BoazHostResult CloseWindow(BoazHostWindow window);
  BoazHostResult GetWindowLayout(BoazHostWindow window, BoazHostWindowLayout* layout);
  BoazHostResult SetSplit(BoazHostWindow window, BoazHostPage first,
      BoazHostPage second, bool vertical, double first_ratio);
  BoazHostResult ClearSplit(BoazHostWindow window);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace boaz
#endif  // BOAZ_CHROMIUM_TAB_REGISTRY_H_
