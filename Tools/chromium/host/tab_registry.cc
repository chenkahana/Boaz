#include "page_print.h"
#include "tab_registry.h"
#include "base/compiler_specific.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "content/public/browser/media_session.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "net/base/net_errors.h"
#include <cstring>
#include "base/strings/string_util.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_types.h"
#include "components/zoom/zoom_controller.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "trusted_script_channel.h"

#include <limits>
#include <cmath>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/feature_list.h"
#include "chrome/browser/ui/tabs/features.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/tabs/split_tab_metrics.h"
#include "components/tabs/public/split_tab_data.h"
#include "components/split_tabs/split_tab_visual_data.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_removed_reason.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/referrer.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace boaz {
namespace {
uint64_t NextHandle() {
  static uint64_t next = 1;
  CHECK_LT(next, std::numeric_limits<uint64_t>::max());
  return next++;
}
}

struct TabRegistry::Impl {
  struct Page;
  struct Window;
  struct Snapshot {
    BoazHostPageState state{};
    std::string url;
    std::string title;
    std::string failed_url;
    uint64_t view_revision = 0;
  };

  BoazHostResult Check() const {
    if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI))
      return BOAZ_HOST_WRONG_THREAD;
    return in_callback ? BOAZ_HOST_UNAVAILABLE : BOAZ_HOST_OK;
  }
  Page* Find(BoazHostPage id) {
    auto it = pages.find(id);
    return it == pages.end() ? nullptr : it->second.get();
  }
  Window* FindWindow(BoazHostWindow id) {
    auto it = windows.find(id);
    return it == windows.end() ? nullptr : it->second.get();
  }
  Page* FindContents(content::WebContents* contents);
  Page* Track(Window& window, content::WebContents* contents);
  Snapshot Capture(Page& page);
  void Queue(Page& page, BoazHostPageEvent event);
  void Deliver(BoazHostPageEvent event, Snapshot snapshot);
  void Closing(Page& page);
  void Replace(Page& page, content::WebContents* replacement);
  void Destroyed(Page& page);
  void WindowDestroyed(BoazHostWindow id);

  BoazHostCallbacks callbacks{};
  bool in_callback = false;
  std::map<BoazHostPage, std::unique_ptr<Page>> pages;
  std::map<BoazHostWindow, std::unique_ptr<Window>> windows;
  base::WeakPtrFactory<Impl> weak{this};
};

struct TabRegistry::Impl::Page : content::WebContentsObserver, find_in_page::FindResultObserver {
  Page(Impl& owner, Window& window, content::WebContents* contents);
  ~Page() override { DetachFind(); }
  void DetachFind() {
    if (find_helper) find_helper->RemoveObserver(this);
    find_helper = nullptr;
    find_active = false;
    find_result = {};
  }
  void AttachFind() {
    if (!find_helper && web_contents()) {
      find_helper = find_in_page::FindTabHelper::FromWebContents(web_contents());
      if (find_helper) find_helper->AddObserver(this);
    }
  }
  void ResetFind() {
    find_active = false;
    find_result = {};
    if (find_helper) find_helper->StopFinding(find_in_page::SelectionAction::kClear);
  }
  void OnFindResultAvailable(content::WebContents* contents) override {
    if (!find_active || !find_helper || contents != web_contents()) return;
    const auto& result = find_helper->find_result();
    if (result.request_id() != find_helper->current_find_request_id()) return;
    find_result = result;
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper*) override {
    DetachFind();
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (!navigation->IsInPrimaryMainFrame()) return;
    latest_navigation = navigation->GetNavigationId();
    load_error = net::OK;
    failed_url.clear();
    if (!navigation->IsSameDocument()) ResetFind();
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (!navigation->IsInPrimaryMainFrame()) return;
    if (navigation->HasCommitted() && !navigation->IsSameDocument()) ++generation;
    if (navigation->GetNavigationId() == latest_navigation) {
      const auto error = navigation->GetNetErrorCode();
      if (error != net::OK && error != net::ERR_ABORTED) {
        load_error = error;
        failed_url = navigation->GetURL().spec();
      }
    }
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void TitleWasSet(content::NavigationEntry*) override {
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void DidStartLoading() override { owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED); }
  void DidStopLoading() override { owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED); }
  void OnAudioStateChanged(bool) override { owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED); }
  void DidUpdateAudioMutingState(bool) override { owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    find_active = false;
    find_result = {};
    owner->Queue(*this, BOAZ_HOST_PAGE_RENDERER_FAILED);
  }
  void DidToggleFullscreenModeForTab(bool, bool) override {
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void BeforeUnloadFired(bool proceed) override { if (!proceed) CancelClose(); }
  void BeforeUnloadDialogCancelled() override { CancelClose(); }
  void CancelClose() {
    if (!close_requested || closing || cancel_notified) return;
    cancel_notified = true;
    close_requested = false;
    owner->Queue(*this, BOAZ_HOST_PAGE_CLOSE_CANCELLED);
  }
  void WebContentsDestroyed() override { DetachFind(); owner->Destroyed(*this); }
  void ObserveReplacement(content::WebContents* contents) { DetachFind(); emulation.reset(); capture.reset(); scripts.reset(); latest_navigation = -1; load_error = net::OK; failed_url.clear(); Observe(contents); AttachFind(); }

  raw_ref<Impl> owner;
  BoazHostPage id = NextHandle();
  BoazHostWindow window;
  uint64_t generation = 0;
  std::optional<uint64_t> protected_media_generation;
  uint64_t view_revision = 0;
  int extension_window_id = -1;
  int64_t latest_navigation = -1;
  int load_error = net::OK;
  std::string failed_url;
  bool close_requested = false;
  bool cancel_notified = false;
  bool closing = false;
  bool destroyed = false;
  bool created_delivered = false;
  bool view_available = false;
  std::optional<Snapshot> final_snapshot;
  std::unique_ptr<TrustedScriptChannel> scripts;
  std::unique_ptr<VisiblePageCapture> capture;
  std::unique_ptr<PageEmulation> emulation;
  std::unique_ptr<PagePDF> pdf;
  raw_ptr<find_in_page::FindTabHelper> find_helper = nullptr;
  find_in_page::FindNotificationDetails find_result;
  bool find_active = false;
};

struct TabRegistry::Impl::Window : TabStripModelObserver {
  Window(Impl& owner, Browser* browser)
      : owner(owner), browser(browser),
        strip(browser->GetTabStripModel()) {
    strip->AddObserver(this);
  }
  ~Window() override { if (strip) strip->RemoveObserver(this); }
  void OnTabStripModelChanged(TabStripModel*, const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {
    if (change.type() == TabStripModelChange::kInserted) {
      for (const auto& item : change.GetInsert()->contents)
        owner->Track(*this, item.contents);
    } else if (change.type() == TabStripModelChange::kRemoved) {
      for (const auto& item : change.GetRemove()->contents) {
        if (auto* page = owner->FindContents(item.contents)) {
          if (TabRemoveReasonUtils::WillDeleteWebContents(item.remove_reason))
            owner->Closing(*page);
          // Transfer removals retain identity; the destination insertion updates it.
        }
      }
    } else if (change.type() == TabStripModelChange::kReplaced) {
      const auto* replacement = change.GetReplace();
      if (auto* page = owner->FindContents(replacement->old_contents))
        owner->Replace(*page, replacement->new_contents);
      else
        owner->Track(*this, replacement->new_contents);
    }
    if (selection.old_contents)
      if (auto* page = owner->FindContents(selection.old_contents))
        owner->Queue(*page, BOAZ_HOST_PAGE_CHANGED);
    if (selection.new_contents)
      if (auto* page = owner->FindContents(selection.new_contents))
        owner->Queue(*page, BOAZ_HOST_PAGE_CHANGED);
  }
  void OnSplitTabChanged(const SplitTabChange&) override {
    for (int i = 0; strip && i < strip->count(); ++i)
      if (auto* page = owner->FindContents(strip->GetWebContentsAt(i)))
        owner->Queue(*page, BOAZ_HOST_PAGE_CHANGED);
  }
  void OnTabCloseCancelled(const tabs::TabInterface* tab) override {
    if (auto* page = owner->FindContents(tab->GetContents())) page->CancelClose();
  }
  void OnTabStripModelDestroyed(TabStripModel*) override {
    // Model destruction precedes destruction of its owned tab collection.
    for (int i = 0; i < strip->count(); ++i)
      if (auto* page = owner->FindContents(strip->GetWebContentsAt(i)))
        owner->Closing(*page);
    strip = nullptr;
    browser = nullptr;
    owner->WindowDestroyed(id);
  }
  raw_ref<Impl> owner;
  BoazHostWindow id = NextHandle();
  raw_ptr<Browser> browser;
  raw_ptr<TabStripModel> strip;
};

TabRegistry::Impl::Page::Page(Impl& owner, Window& window,
                             content::WebContents* contents)
    : WebContentsObserver(), owner(owner), window(window.id),
      extension_window_id(extensions::ExtensionTabUtil::GetWindowId(window.browser)) {
  Observe(contents);
}

TabRegistry::Impl::Page* TabRegistry::Impl::FindContents(content::WebContents* contents) {
  for (auto& [id, page] : pages)
    if (!page->destroyed && page->web_contents() == contents) return page.get();
  return nullptr;
}
TabRegistry::Impl::Page* TabRegistry::Impl::Track(Window& window,
                                                content::WebContents* contents) {
  if (!contents || contents->GetBrowserContext() != window.browser->GetProfile()) return nullptr;
  if (auto* page = FindContents(contents)) {
    page->window = window.id;
    page->extension_window_id = extensions::ExtensionTabUtil::GetWindowId(window.browser);
    Queue(*page, BOAZ_HOST_PAGE_CHANGED);
    return page;
  }
  auto page = std::make_unique<Page>(*this, window, contents);
  auto* result = page.get();
  pages.emplace(result->id, std::move(page));
  Queue(*result, BOAZ_HOST_PAGE_CREATED);
  return result;
}
TabRegistry::Impl::Snapshot TabRegistry::Impl::Capture(Page& page) {
  Snapshot result;
  result.view_revision = page.view_revision;
  result.state.size = sizeof(BoazHostPageState);
  result.state.page = page.id;
  result.state.window = page.window;
  result.state.document_generation = page.generation;
  result.state.load_error = page.load_error;
  result.failed_url = page.failed_url;
  result.state.find_match_count = page.find_result.number_of_matches();
  result.state.find_active_match = page.find_result.active_match_ordinal();
  result.state.find_final = page.find_result.final_update();
  result.state.extension_tab_id = -1;
  result.state.extension_window_id = page.extension_window_id;
  if (auto* contents = page.web_contents()) {
    result.url = contents->GetLastCommittedURL().spec();
    result.title = base::UTF16ToUTF8(contents->GetTitle());
    result.state.extension_tab_id = extensions::ExtensionTabUtil::GetTabId(contents);
    result.state.loading = contents->IsLoading();
    result.state.audible = contents->IsCurrentlyAudible();
    result.state.muted = contents->IsAudioMuted();
    auto* window = FindWindow(page.window);
    result.state.active = window && window->strip &&
        window->strip->GetActiveWebContents() == contents;
    result.state.can_go_back = contents->GetController().CanGoBack();
    result.state.can_go_forward = contents->GetController().CanGoForward();
  }
  return result;
}
void TabRegistry::Impl::Queue(Page& page, BoazHostPageEvent event) {
  if (page.destroyed || (page.closing && event != BOAZ_HOST_PAGE_CLOSED)) return;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&Impl::Deliver, weak.GetWeakPtr(), event, Capture(page)));
}
void TabRegistry::Impl::Deliver(BoazHostPageEvent event, Snapshot snapshot) {
  auto* page = Find(snapshot.state.page);
  if (!page) return;
  if (event != BOAZ_HOST_PAGE_CLOSED && (page->closing || page->destroyed)) return;
  if (event == BOAZ_HOST_PAGE_CREATED) {
    if (page->created_delivered) return;
    snapshot = Capture(*page);
    page->created_delivered = true;
    page->view_available = true;
  } else if (event == BOAZ_HOST_PAGE_VIEW_CHANGED) {
    if (snapshot.view_revision != page->view_revision) return;
    snapshot = Capture(*page);
  } else if (event != BOAZ_HOST_PAGE_CLOSED &&
             snapshot.state.document_generation != page->generation) {
    return;
  }
  if (event == BOAZ_HOST_PAGE_VIEW_CHANGED) page->view_available = true;
  if (event == BOAZ_HOST_PAGE_CLOSE_CANCELLED) page->cancel_notified = false;
  snapshot.state.url = snapshot.url.c_str();
  snapshot.state.title = snapshot.title.c_str();
  snapshot.state.failed_url = snapshot.failed_url.c_str();
  in_callback = true;
  if (callbacks.page_event) callbacks.page_event(callbacks.context, event, &snapshot.state);
  in_callback = false;
  if (event == BOAZ_HOST_PAGE_CLOSED) {
    pages.erase(snapshot.state.page);
    WindowDestroyed(snapshot.state.window);
  }
}
void TabRegistry::Impl::Replace(Page& page, content::WebContents* replacement) {
  if (page.closing || page.destroyed || !replacement) return;
  auto snapshot = Capture(page);
  snapshot.state.url = snapshot.url.c_str();
  snapshot.state.title = snapshot.title.c_str();
  snapshot.state.failed_url = snapshot.failed_url.c_str();
  page.view_available = false;
  in_callback = true;
  if (callbacks.page_event)
    callbacks.page_event(callbacks.context, BOAZ_HOST_PAGE_VIEW_WILL_CHANGE, &snapshot.state);
  in_callback = false;
  page.ObserveReplacement(replacement);
  ++page.view_revision;
  ++page.generation;
  Queue(page, BOAZ_HOST_PAGE_VIEW_CHANGED);
}
void TabRegistry::Impl::Closing(Page& page) {
  if (page.closing) return;
  page.closing = true;
  if (page.scripts) page.scripts->Close();
  if (page.capture) page.capture->Close();
  if (page.emulation) page.emulation->Close();
  if (page.pdf) page.pdf->Close();
  auto snapshot = Capture(page);
  page.final_snapshot = snapshot;
  snapshot.state.url = snapshot.url.c_str();
  snapshot.state.title = snapshot.title.c_str();
  snapshot.state.failed_url = snapshot.failed_url.c_str();
  in_callback = true;
  if (callbacks.page_event)
    callbacks.page_event(callbacks.context, BOAZ_HOST_PAGE_CLOSING, &snapshot.state);
  in_callback = false;
}
void TabRegistry::Impl::Destroyed(Page& page) {
  if (page.destroyed) return;
  // Never query a half-destroyed WebContents. Its registered owner must have
  // supplied a removal or model-destruction barrier before this callback.
  CHECK(page.closing);
  CHECK(page.final_snapshot.has_value());
  auto snapshot = *page.final_snapshot;
  page.destroyed = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&Impl::Deliver, weak.GetWeakPtr(), BOAZ_HOST_PAGE_CLOSED,
                               std::move(snapshot)));
}
void TabRegistry::Impl::WindowDestroyed(BoazHostWindow id) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce([](base::WeakPtr<Impl> self, BoazHostWindow id) {
        if (!self) return;
        auto* window = self->FindWindow(id);
        if (!window || window->strip) return;
        for (const auto& [page_id, page] : self->pages)
          if (page->window == id) return;
        self->in_callback = true;
        if (self->callbacks.window_closed)
          self->callbacks.window_closed(self->callbacks.context, id);
        self->in_callback = false;
        self->windows.erase(id);
      }, weak.GetWeakPtr(), id));
}

TabRegistry::TabRegistry() : impl_(std::make_unique<Impl>()) {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
}
TabRegistry::~TabRegistry() {
  CHECK(content::BrowserThread::CurrentlyOn(content::BrowserThread::UI));
  CHECK(impl_->pages.empty());
  CHECK(impl_->windows.empty());
  CHECK(!impl_->in_callback);
}
BoazHostResult TabRegistry::SetCallbacks(const BoazHostCallbacks* callbacks) {
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result;
  if (!callbacks || callbacks->size != sizeof(BoazHostCallbacks) || !callbacks->page_event)
    return BOAZ_HOST_INVALID_ARGUMENT;
  if (!impl_->pages.empty() || !impl_->windows.empty()) return BOAZ_HOST_UNAVAILABLE;
  impl_->callbacks = *callbacks;
  return BOAZ_HOST_OK;
}
BoazHostWindow TabRegistry::RegisterWindow(Browser* browser, void* native_window) {
  if (impl_->Check() != BOAZ_HOST_OK || !browser || !native_window || !impl_->callbacks.page_event)
    return 0;
  for (const auto& [id, window] : impl_->windows)
    if (window->browser == browser) return id;
  auto window = std::make_unique<Impl::Window>(*impl_, browser);
  auto* registered = window.get();
  auto id = registered->id;
  impl_->windows.emplace(id, std::move(window));
  for (int i = 0; i < registered->strip->count(); ++i)
    impl_->Track(*registered, registered->strip->GetWebContentsAt(i));
  return id;
}
BoazHostResult TabRegistry::CreatePage(BoazHostWindow window_id, const char* url, BoazHostPage* output) {
  if (output) *output = 0;
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result;
  if (!output || !url || !GURL(url).is_valid()) return BOAZ_HOST_INVALID_ARGUMENT;
  auto* window = impl_->FindWindow(window_id);
  if (!window || !window->browser) return BOAZ_HOST_INVALID_HANDLE;
  auto* contents = chrome::AddAndReturnTabAt(window->browser, GURL(url), -1, true);
  auto* page = contents ? impl_->Track(*window, contents) : nullptr;
  if (!page) return BOAZ_HOST_UNAVAILABLE;
  *output = page->id;
  return BOAZ_HOST_OK;
}
#define BOAZ_FIND_PAGE() \
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result; \
  auto* page = impl_->Find(id); \
  if (!page || page->destroyed || !page->web_contents()) return BOAZ_HOST_INVALID_HANDLE; \
  if (page->closing) return BOAZ_HOST_CLOSING

BoazHostResult TabRegistry::Navigate(BoazHostPage id, const char* url) {
  BOAZ_FIND_PAGE();
  if (!url || !GURL(url).is_valid()) return BOAZ_HOST_INVALID_ARGUMENT;
  page->web_contents()->GetController().LoadURL(GURL(url), content::Referrer(),
      ui::PAGE_TRANSITION_TYPED, std::string());
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::GoBack(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  auto& navigation = page->web_contents()->GetController();
  if (!navigation.CanGoBack()) return BOAZ_HOST_UNAVAILABLE;
  navigation.GoBack();
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::GoForward(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  auto& navigation = page->web_contents()->GetController();
  if (!navigation.CanGoForward()) return BOAZ_HOST_UNAVAILABLE;
  navigation.GoForward();
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ReloadFromOrigin(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  page->web_contents()->GetController().Reload(content::ReloadType::BYPASSING_CACHE, true);
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::Reload(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  page->web_contents()->GetController().Reload(content::ReloadType::NORMAL, true);
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::CapturePDF(BoazHostPage id, uint64_t request, PagePDF::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->pdf) page->pdf = std::make_unique<PagePDF>(page->web_contents());
  return page->pdf->Capture(request, std::move(completion));
}
BoazHostResult TabRegistry::CancelPDF(BoazHostPage id, uint64_t request) {
  BOAZ_FIND_PAGE();
  return page->pdf ? page->pdf->Cancel(request) : BOAZ_HOST_INVALID_ARGUMENT;
}
bool TabRegistry::TakeProtectedMediaRequest(content::RenderFrameHost* frame,
    BoazHostPage* output, uint64_t* navigation) {
  if (!output || !navigation || impl_->Check() != BOAZ_HOST_OK || !frame) return false;
  auto* contents = content::WebContents::FromRenderFrameHost(frame);
  auto* page = contents ? impl_->FindContents(contents) : nullptr;
  if (!page || page->closing || page->destroyed || contents->GetPrimaryMainFrame() != frame ||
      contents->GetController().GetPendingEntry() ||
      !frame->IsActive() || !frame->IsRenderFrameLive() ||
      !frame->GetLastCommittedURL().SchemeIsHTTPOrHTTPS() || frame->GetLastCommittedOrigin().opaque() ||
      page->protected_media_generation == page->generation) return false;
  page->protected_media_generation = page->generation;
  *output = page->id;
  *navigation = page->generation;
  return true;
}
BoazHostResult TabRegistry::Print(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  return PrintPage(page->web_contents());
}
BoazHostResult TabRegistry::ShowDevTools(BoazHostPage id, BoazHostDevToolsAction action) {
  BOAZ_FIND_PAGE();
  auto* contents = page->web_contents();
  if (!DevToolsWindow::AllowDevToolsFor(
          Profile::FromBrowserContext(contents->GetBrowserContext()), contents))
    return BOAZ_HOST_UNAVAILABLE;
  switch (action) {
    case BOAZ_DEVTOOLS_SHOW:
      DevToolsWindow::OpenDevToolsWindow(contents, DevToolsToggleAction::Show(),
          DevToolsOpenedByAction::kMainMenuOrMainShortcut);
      break;
    case BOAZ_DEVTOOLS_CONSOLE:
      DevToolsWindow::OpenDevToolsWindow(contents, DevToolsToggleAction::ShowConsolePanel(),
          DevToolsOpenedByAction::kConsoleShortcut);
      break;
    case BOAZ_DEVTOOLS_INSPECT:
      DevToolsWindow::OpenDevToolsWindow(contents, DevToolsToggleAction::Inspect(),
          DevToolsOpenedByAction::kInspectorModeShortcut);
      break;
    default:
      return BOAZ_HOST_INVALID_ARGUMENT;
  }
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::StopLoading(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  page->web_contents()->Stop();
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::EnumerateHistory(BoazHostPage id,
    BoazHostHistoryVisitor visitor, void* context) {
  BOAZ_FIND_PAGE();
  if (!visitor) return BOAZ_HOST_INVALID_ARGUMENT;
  struct Entry {
    int32_t id;
    int32_t offset;
    std::string url;
    std::string title;
  };
  auto& navigation = page->web_contents()->GetController();
  const int count = navigation.GetEntryCount();
  const int current = navigation.GetCurrentEntryIndex();
  std::vector<Entry> entries;
  entries.reserve(count);
  for (int index = 0; index < count; ++index) {
    const auto* entry = navigation.GetEntryAtIndex(index);
    if (!entry) return BOAZ_HOST_UNAVAILABLE;
    entries.push_back({entry->GetUniqueID(), index - current,
        entry->GetURL().spec(), base::UTF16ToUTF8(entry->GetTitle())});
  }
  base::AutoReset<bool> callback_guard(&impl_->in_callback, true);
  for (const auto& entry : entries) {
    visitor(context, entry.id, entry.offset, entry.url.c_str(), entry.title.c_str());
  }
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::GoToHistoryEntry(BoazHostPage id, int32_t entry_id) {
  BOAZ_FIND_PAGE();
  auto& navigation = page->web_contents()->GetController();
  const int count = navigation.GetEntryCount();
  for (int index = 0; index < count; ++index) {
    const auto* entry = navigation.GetEntryAtIndex(index);
    if (entry && entry->GetUniqueID() == entry_id) {
      navigation.GoToIndex(index);
      return BOAZ_HOST_OK;
    }
  }
  return BOAZ_HOST_UNAVAILABLE;
}
BoazHostResult TabRegistry::SetAudioMuted(BoazHostPage id, bool muted) {
  BOAZ_FIND_PAGE();
  auto* contents = page->web_contents();
  const bool unchanged = contents->IsAudioMuted() == muted;
  contents->SetAudioMuted(muted);
  // Changed values queue through the synchronous muting observer.
  if (unchanged) impl_->Queue(*page, BOAZ_HOST_PAGE_CHANGED);
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::IsBusyForResidency(BoazHostPage id, uint8_t* busy) {
  if (busy) *busy = 1;
  BOAZ_FIND_PAGE();
  if (!busy) return BOAZ_HOST_INVALID_ARGUMENT;
  auto* contents = page->web_contents();
  auto capture = MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator();
  auto* session = content::MediaSession::Get(contents);
  auto info = session ? session->GetMediaSessionInfoSync() : nullptr;
  if (!capture || !info) return BOAZ_HOST_UNAVAILABLE;
  *busy = contents->IsCurrentlyAudible() || contents->GetCurrentlyPlayingVideoCount() > 0 ||
      info->playback_state == media_session::mojom::MediaPlaybackState::kPlaying ||
      contents->IsFullscreen() || contents->HasPictureInPictureVideo() ||
      contents->HasPictureInPictureDocument() || contents->IsBeingCaptured() ||
      capture->IsCapturingUserMedia(contents) || capture->IsCapturingTab(contents) ||
      capture->IsCapturingWindow(contents) || capture->IsCapturingDisplay(contents) ||
      capture->IsBeingMirrored(contents);
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::GetUserAgentDefaults(BoazHostPage id,
    std::optional<PageEmulation::UserAgentDefaults>* output) {
  BOAZ_FIND_PAGE();
  if (!output) return BOAZ_HOST_INVALID_ARGUMENT;
  *output = PageEmulation::GetDefaultUserAgent();
  return output->has_value() ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
BoazHostResult TabRegistry::ApplySensors(BoazHostPage id,
    std::optional<PageEmulation::Sensors> sensors, PageEmulation::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->emulation) page->emulation = std::make_unique<PageEmulation>(page->web_contents());
  page->emulation->ApplySensors(std::move(sensors), std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ApplyNetwork(BoazHostPage id,
    std::optional<PageEmulation::Network> network, PageEmulation::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->emulation) page->emulation = std::make_unique<PageEmulation>(page->web_contents());
  page->emulation->ApplyNetwork(std::move(network), std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ApplyCPU(BoazHostPage id, double rate, PageEmulation::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->emulation) page->emulation = std::make_unique<PageEmulation>(page->web_contents());
  page->emulation->ApplyCPU(rate, std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ApplyMedia(BoazHostPage id,
    std::optional<PageEmulation::Media> media, PageEmulation::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->emulation) page->emulation = std::make_unique<PageEmulation>(page->web_contents());
  page->emulation->ApplyMedia(std::move(media), std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ApplyUserAgent(BoazHostPage id,
    std::optional<std::string> user_agent, PageEmulation::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->emulation) page->emulation = std::make_unique<PageEmulation>(page->web_contents());
  page->emulation->ApplyUserAgent(std::move(user_agent), std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ApplyViewport(BoazHostPage id,
    std::optional<PageEmulation::Viewport> viewport, PageEmulation::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->emulation) page->emulation = std::make_unique<PageEmulation>(page->web_contents());
  if (viewport) page->emulation->Apply(*viewport, std::move(completion));
  else page->emulation->Clear(std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::GetZoomFactor(BoazHostPage id, double* factor) {
  if (factor) *factor = 0;
  BOAZ_FIND_PAGE();
  if (!factor) return BOAZ_HOST_INVALID_ARGUMENT;
  auto* controller = zoom::ZoomController::FromWebContents(page->web_contents());
  if (!controller) return BOAZ_HOST_UNAVAILABLE;
  const double actual = blink::ZoomLevelToZoomFactor(controller->GetZoomLevel());
  if (!std::isfinite(actual) || actual <= 0) return BOAZ_HOST_UNAVAILABLE;
  *factor = actual;
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::SetZoomFactor(BoazHostPage id, double factor) {
  BOAZ_FIND_PAGE();
  if (!std::isfinite(factor) || factor < 0.5 || factor > 3.0)
    return BOAZ_HOST_INVALID_ARGUMENT;
  auto* controller = zoom::ZoomController::FromWebContents(page->web_contents());
  if (!controller) return BOAZ_HOST_UNAVAILABLE;
  return controller->SetZoomLevel(blink::ZoomFactorToZoomLevel(factor))
      ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
BoazHostResult TabRegistry::FindText(BoazHostPage id, const char* text, bool forward) {
  BOAZ_FIND_PAGE();
  if (!text) return BOAZ_HOST_INVALID_ARGUMENT;
  // The native ABI requires a NUL-terminated string; bound the accepted query size.
  const size_t length = UNSAFE_BUFFERS(strnlen(text, 8193));
  if (length > 8192 || !base::IsStringUTF8(std::string_view(text, length)))
    return BOAZ_HOST_INVALID_ARGUMENT;
  if (!length) return StopFind(id);
  page->AttachFind();
  if (!page->find_helper) return BOAZ_HOST_UNAVAILABLE;
  page->find_result = {};
  page->find_active = true;
  impl_->Queue(*page, BOAZ_HOST_PAGE_CHANGED);
  page->find_helper->StartFinding(base::UTF8ToUTF16(std::string_view(text, length)), forward, false, true);
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::StopFind(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  page->AttachFind();
  if (!page->find_helper) return BOAZ_HOST_UNAVAILABLE;
  page->ResetFind();
  impl_->Queue(*page, BOAZ_HOST_PAGE_CHANGED);
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ActivatePage(BoazHostPage id, bool focus) {
  BOAZ_FIND_PAGE();
  auto* window = impl_->FindWindow(page->window);
  if (!window || !window->strip) return BOAZ_HOST_UNAVAILABLE;
  int index = window->strip->GetIndexOfWebContents(page->web_contents());
  if (index == TabStripModel::kNoTab) return BOAZ_HOST_UNAVAILABLE;
  window->strip->ActivateTabAt(index);
  if (focus) page->web_contents()->Focus();
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::GetNativeView(BoazHostPage id, void** output) {
  if (output) *output = nullptr;
  BOAZ_FIND_PAGE();
  if (!output) return BOAZ_HOST_INVALID_ARGUMENT;
  if (!page->view_available) return BOAZ_HOST_UNAVAILABLE;
  *output = NativeViewForContents(page->web_contents());
  return *output ? BOAZ_HOST_OK : BOAZ_HOST_UNAVAILABLE;
}
BoazHostResult TabRegistry::CaptureVisible(BoazHostPage id, uint64_t request,
    int width, int height, VisiblePageCapture::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->view_available) return BOAZ_HOST_UNAVAILABLE;
  if (!page->capture) page->capture = std::make_unique<VisiblePageCapture>(page->web_contents());
  return page->capture->Capture(request, width, height, std::move(completion));
}
BoazHostResult TabRegistry::CancelCapture(BoazHostPage id, uint64_t request) {
  BOAZ_FIND_PAGE();
  return page->capture ? page->capture->Cancel(request) : BOAZ_HOST_INVALID_ARGUMENT;
}
BoazHostResult TabRegistry::CaptureDocument(BoazHostPage id, BoazHostDocument* output) {
  if (output) *output = 0;
  BOAZ_FIND_PAGE();
  if (!output) return BOAZ_HOST_INVALID_ARGUMENT;
  if (!page->scripts) page->scripts = std::make_unique<TrustedScriptChannel>(page->web_contents());
  auto token = page->scripts->Capture();
  if (!token) return BOAZ_HOST_UNAVAILABLE;
  *output = *token;
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::CaptureDocumentOrigin(BoazHostPage id,
    BoazHostDocument* output, char* origin, size_t capacity) {
  if (output) *output = 0;
  if (origin && capacity) origin[0] = '\0';
  BOAZ_FIND_PAGE();
  if (!output || !origin || capacity == 0) return BOAZ_HOST_INVALID_ARGUMENT;
  if (!page->scripts) page->scripts = std::make_unique<TrustedScriptChannel>(page->web_contents());
  std::string serialized;
  auto token = page->scripts->Capture(&serialized);
  if (!token) return BOAZ_HOST_UNAVAILABLE;
  if (serialized.empty() || serialized.size() >= capacity || serialized.size() >= 2048) {
    page->scripts->Release(*token);
    return BOAZ_HOST_INVALID_ARGUMENT;
  }
  // The caller supplies capacity writable bytes; the check above includes the terminator.
  UNSAFE_BUFFERS(std::memcpy(origin, serialized.c_str(), serialized.size() + 1));
  *output = *token;
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ReleaseDocument(BoazHostPage id, BoazHostDocument token) {
  BOAZ_FIND_PAGE();
  return page->scripts && page->scripts->Release(token) ? BOAZ_HOST_OK : BOAZ_HOST_INVALID_HANDLE;
}
BoazHostResult TabRegistry::ExecuteTrusted(BoazHostPage id, BoazHostDocument token,
    std::u16string source, base::DictValue arguments, TrustedExecution::Completion completion) {
  BOAZ_FIND_PAGE();
  if (!page->scripts) return BOAZ_HOST_INVALID_HANDLE;
  page->scripts->Execute(token, std::move(source), std::move(arguments), std::move(completion));
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ClosePage(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  if (page->close_requested) return BOAZ_HOST_CLOSING;
  auto* window = impl_->FindWindow(page->window);
  if (!window || !window->strip) return BOAZ_HOST_UNAVAILABLE;
  int index = window->strip->GetIndexOfWebContents(page->web_contents());
  if (index == TabStripModel::kNoTab) return BOAZ_HOST_UNAVAILABLE;
  page->close_requested = true;
  page->cancel_notified = false;
  window->strip->CloseWebContentsAt(index, TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
  return BOAZ_HOST_OK;
}
#undef BOAZ_FIND_PAGE
BoazHostResult TabRegistry::CloseWindow(BoazHostWindow id) {
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result;
  auto* window = impl_->FindWindow(id);
  if (!window || !window->strip) return BOAZ_HOST_INVALID_HANDLE;
  for (auto& [page_id, page] : impl_->pages) {
    if (page->window == id && !page->closing && !page->destroyed) {
      page->close_requested = true;
      page->cancel_notified = false;
    }
  }
  window->strip->CloseAllTabs();
  return BOAZ_HOST_OK;
}

BoazHostResult TabRegistry::GetWindowLayout(BoazHostWindow id, BoazHostWindowLayout* output) {
  if (!output || output->size < sizeof(*output)) return BOAZ_HOST_INVALID_ARGUMENT;
  const size_t size = output->size;
  *output = {};
  output->size = size;
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result;
  auto* window = impl_->FindWindow(id);
  if (!window || !window->strip) return BOAZ_HOST_INVALID_HANDLE;
  BoazHostWindowLayout layout{};
  layout.size = size;
  layout.window = id;
  layout.first_ratio = 0.5;
  auto* manager = window->browser ? ExclusiveAccessManager::From(window->browser.get()) : nullptr;
  if (manager && manager->fullscreen_controller()->IsTabFullscreen()) {
    auto* page = impl_->FindContents(manager->fullscreen_controller()->exclusive_access_tab());
    if (!page || page->destroyed || page->closing || page->window != id)
      return BOAZ_HOST_UNAVAILABLE;
    layout.first = page->id;
    layout.active = page->id;
    layout.content_fullscreen = 1;
    *output = layout;
    return BOAZ_HOST_OK;
  }
  auto foreground = window->strip->GetForegroundTabs();
  if (foreground.size() > 2) return BOAZ_HOST_UNAVAILABLE;
  for (size_t i = 0; i < foreground.size(); ++i) {
    auto* page = impl_->FindContents(foreground[i]->GetContents());
    if (!page || page->destroyed || page->closing || page->window != id)
      return BOAZ_HOST_UNAVAILABLE;
    (i == 0 ? layout.first : layout.second) = page->id;
    if (foreground[i] == window->strip->GetActiveTab()) layout.active = page->id;
  }
  if (foreground.size() == 2) {
    auto split = foreground[0]->GetSplit();
    if (!split || foreground[1]->GetSplit() != split) return BOAZ_HOST_UNAVAILABLE;
    auto* data = window->strip->GetSplitData(*split);
    if (!data) return BOAZ_HOST_UNAVAILABLE;
    layout.vertical = data->visual_data()->split_layout() == split_tabs::SplitTabLayout::kStacked;
    layout.first_ratio = data->visual_data()->split_ratio();
  }
  *output = layout;
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::SetSplit(BoazHostWindow id, BoazHostPage first,
    BoazHostPage second, bool vertical, double ratio) {
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result;
  if (first == second || !std::isfinite(ratio) || ratio < 0.1 || ratio > 0.9)
    return BOAZ_HOST_INVALID_ARGUMENT;
  auto* window = impl_->FindWindow(id);
  if (!window || !window->browser || !window->strip) return BOAZ_HOST_INVALID_HANDLE;
  auto* manager = ExclusiveAccessManager::From(window->browser.get());
  if (manager && manager->fullscreen_controller()->IsTabFullscreen()) return BOAZ_HOST_UNAVAILABLE;
  auto* a = impl_->Find(first);
  auto* b = impl_->Find(second);
  if (!a || !b || a->destroyed || b->destroyed || !a->web_contents() || !b->web_contents() ||
      a->window != id || b->window != id) return BOAZ_HOST_INVALID_HANDLE;
  if (a->closing || b->closing || a->close_requested || b->close_requested)
    return BOAZ_HOST_CLOSING;
  auto* strip = window->strip.get();
  if (strip->closing_all() ||
      a->web_contents()->GetBrowserContext() != window->browser->GetProfile() ||
      b->web_contents()->GetBrowserContext() != window->browser->GetProfile())
    return BOAZ_HOST_UNAVAILABLE;
  int ai = strip->GetIndexOfWebContents(a->web_contents());
  int bi = strip->GetIndexOfWebContents(b->web_contents());
  if (ai == TabStripModel::kNoTab || bi == TabStripModel::kNoTab)
    return BOAZ_HOST_UNAVAILABLE;
  if (strip->GetTabGroupForTab(ai) != strip->GetTabGroupForTab(bi) ||
      strip->IsTabPinned(ai) != strip->IsTabPinned(bi) ||
      strip->IsTabCollapsed(ai) || strip->IsTabCollapsed(bi) ||
      (strip->GetFocusedGroup() && strip->GetFocusedGroup() != strip->GetTabGroupForTab(ai)) ||
      (vertical && !base::FeatureList::IsEnabled(tabs::kSplitViewHorizontal)))
    return BOAZ_HOST_UNAVAILABLE;
  auto split = strip->GetSplitForTab(ai);
  auto other = strip->GetSplitForTab(bi);
  if (split != other) return BOAZ_HOST_UNAVAILABLE;
  const auto layout = vertical ? split_tabs::SplitTabLayout::kStacked
                               : split_tabs::SplitTabLayout::kSideBySide;
  const bool creating = !split.has_value();
  if (creating) {
    split = strip->AddToNewSplit({ai, bi}, split_tabs::SplitTabVisualData(layout, ratio),
                                 split_tabs::SplitTabCreatedSource::kToolbarButton);
  }
  auto* data = strip->GetSplitData(*split);
  if (!data || data->ListTabs().size() != 2) return BOAZ_HOST_UNAVAILABLE;
  if (data->ListTabs()[0]->GetContents() != a->web_contents()) strip->ReverseTabsInSplit(*split);
  strip->UpdateSplitLayout(*split, layout);
  strip->UpdateSplitRatio(*split, ratio);
  if (creating) {
    strip->ActivateTabAt(strip->GetIndexOfWebContents(a->web_contents()));
    a->web_contents()->Focus();
  }
  return BOAZ_HOST_OK;
}
BoazHostResult TabRegistry::ClearSplit(BoazHostWindow id) {
  if (auto result = impl_->Check(); result != BOAZ_HOST_OK) return result;
  auto* window = impl_->FindWindow(id);
  if (!window || !window->strip) return BOAZ_HOST_INVALID_HANDLE;
  if (window->strip->closing_all()) return BOAZ_HOST_CLOSING;
  auto* manager = window->browser ? ExclusiveAccessManager::From(window->browser.get()) : nullptr;
  if (manager && manager->fullscreen_controller()->IsTabFullscreen()) return BOAZ_HOST_UNAVAILABLE;
  for (auto* tab : window->strip->GetForegroundTabs()) {
    auto* page = impl_->FindContents(tab->GetContents());
    if (!page || page->destroyed) return BOAZ_HOST_UNAVAILABLE;
    if (page->closing || page->close_requested) return BOAZ_HOST_CLOSING;
  }
  auto* active = window->strip->GetActiveTab();
  if (active && active->GetSplit()) window->strip->RemoveSplit(*active->GetSplit());
  return BOAZ_HOST_OK;
}

}  // namespace boaz
