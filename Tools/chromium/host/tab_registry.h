#ifndef BOAZ_CHROMIUM_TAB_REGISTRY_H_
#define BOAZ_CHROMIUM_TAB_REGISTRY_H_

#include <memory>
#include <optional>
#include "boaz_host.h"
#include "visible_page_capture.h"
#include "page_emulation.h"
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
  BoazHostResult ShowDevTools(BoazHostPage page, BoazHostDevToolsAction action);
  BoazHostResult StopLoading(BoazHostPage page);
  BoazHostResult EnumerateHistory(BoazHostPage page,
      BoazHostHistoryVisitor visitor, void* context);
  BoazHostResult GoToHistoryEntry(BoazHostPage page, int32_t entry_id);
  BoazHostResult FindText(BoazHostPage page, const char* text, bool forward);
  BoazHostResult StopFind(BoazHostPage page);
  BoazHostResult SetAudioMuted(BoazHostPage page, bool muted);
  BoazHostResult IsBusyForResidency(BoazHostPage page, uint8_t* busy);
  BoazHostResult ApplyViewport(BoazHostPage page, std::optional<PageEmulation::Viewport> viewport,
      PageEmulation::Completion completion);
  BoazHostResult GetZoomFactor(BoazHostPage page, double* factor);
  BoazHostResult SetZoomFactor(BoazHostPage page, double factor);
  BoazHostResult ActivatePage(BoazHostPage page, bool focus);
  BoazHostResult GetNativeView(BoazHostPage page, void** native_view);
  BoazHostResult CaptureDocumentOrigin(BoazHostPage page, BoazHostDocument* document, char* origin, size_t capacity);
  BoazHostResult CaptureVisible(BoazHostPage page, uint64_t request, int width, int height,
                                VisiblePageCapture::Completion completion);
  BoazHostResult CancelCapture(BoazHostPage page, uint64_t request);
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
