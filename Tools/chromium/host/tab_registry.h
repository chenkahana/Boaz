#ifndef BOAZ_CHROMIUM_TAB_REGISTRY_H_
#define BOAZ_CHROMIUM_TAB_REGISTRY_H_

#include <memory>
#include <optional>
#include "boaz_host.h"
#include "visible_page_capture.h"
#include "page_emulation.h"
#include "page_pdf.h"
#include "trusted_execution.h"

class Browser;
namespace content { class WebContents; class RenderFrameHost; }

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
  void ReportPasswordSubmission(content::WebContents*, std::string origin, std::string username, std::string password);
  BoazHostResult SetDevToolsDockPreferences(BoazHostWindow window, int32_t current, int32_t last);
  BoazHostResult CreatePage(BoazHostWindow window, const char* url,
                            BoazHostPage* page);
  BoazHostResult Navigate(BoazHostPage page, const char* url);
  BoazHostResult GoBack(BoazHostPage page);
  BoazHostResult GoForward(BoazHostPage page);
  BoazHostResult SetJavaScriptDisabled(BoazHostPage page, bool disabled);
  bool IsJavaScriptDisabled(content::WebContents* contents) const;
  BoazHostResult Reload(BoazHostPage page);
  BoazHostResult ReloadFromOrigin(BoazHostPage page);
  BoazHostResult CapturePDF(BoazHostPage page, uint64_t request, PagePDF::Completion completion);
  BoazHostResult CancelPDF(BoazHostPage page, uint64_t request);
  bool TakeProtectedMediaRequest(content::RenderFrameHost* frame, BoazHostPage* page, uint64_t* navigation);
  BoazHostResult Print(BoazHostPage page);
  BoazHostResult ShowDevTools(BoazHostPage page, BoazHostDevToolsAction action);
  BoazHostResult StopLoading(BoazHostPage page);
  BoazHostResult EnumerateHistory(BoazHostPage page,
      BoazHostHistoryVisitor visitor, void* context);
  BoazHostResult GoToHistoryEntry(BoazHostPage page, int32_t entry_id);
  BoazHostResult FindText(BoazHostPage page, const char* text, bool forward);
  BoazHostResult StopFind(BoazHostPage page);
  BoazHostResult TogglePictureInPicture(BoazHostPage page);
  BoazHostResult SetAudioMuted(BoazHostPage page, bool muted);
  BoazHostResult IsBusyForResidency(BoazHostPage page, uint8_t* busy);
  BoazHostResult GetUserAgentDefaults(BoazHostPage page, std::optional<PageEmulation::UserAgentDefaults>* output);
  BoazHostResult ApplySensors(BoazHostPage page, std::optional<PageEmulation::Sensors> sensors,
      PageEmulation::Completion completion);
  BoazHostResult ApplyNetwork(BoazHostPage page, std::optional<PageEmulation::Network> network,
      PageEmulation::Completion completion);
  BoazHostResult ApplyCPU(BoazHostPage page, double rate, PageEmulation::Completion completion);
  BoazHostResult ApplyMedia(BoazHostPage page, std::optional<PageEmulation::Media> media,
      PageEmulation::Completion completion);
  BoazHostResult ApplyUserAgent(BoazHostPage page, std::optional<std::string> user_agent,
      PageEmulation::Completion completion);
  BoazHostResult ApplyViewport(BoazHostPage page, std::optional<PageEmulation::Viewport> viewport,
      PageEmulation::Completion completion);
  BoazHostResult GetZoomFactor(BoazHostPage page, double* factor);
  BoazHostResult SetZoomFactor(BoazHostPage page, double factor);
  BoazHostResult ActivatePage(BoazHostPage page, bool focus);
  BoazHostResult GetNativeView(BoazHostPage page, void** native_view);
  BoazHostResult CaptureDocumentOrigin(BoazHostPage page, BoazHostDocument* document, char* origin, size_t capacity, bool focused = false);
  BoazHostResult CloneDocument(BoazHostPage page, BoazHostDocument document, BoazHostDocument* clone);
  BoazHostResult CaptureVisible(BoazHostPage page, uint64_t request, int width, int height,
                                VisiblePageCapture::Completion completion);
  BoazHostResult CaptureFullPage(BoazHostPage page, uint64_t request,
      PageEmulation::CaptureCompletion completion);
  BoazHostResult CancelFullPage(BoazHostPage page, uint64_t request);
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
