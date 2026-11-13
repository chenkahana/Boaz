#include "tab_registry.h"

#include <limits>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/check.h"
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

struct TabRegistry::Impl::Page : content::WebContentsObserver {
  Page(Impl& owner, Window& window, content::WebContents* contents);
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame()) {
      if (!navigation->IsSameDocument()) ++generation;
      owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
    }
  }
  void TitleWasSet(content::NavigationEntry*) override {
    owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED);
  }
  void DidStartLoading() override { owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED); }
  void DidStopLoading() override { owner->Queue(*this, BOAZ_HOST_PAGE_CHANGED); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    owner->Queue(*this, BOAZ_HOST_PAGE_RENDERER_FAILED);
  }
  void BeforeUnloadFired(bool proceed) override { if (!proceed) CancelClose(); }
  void BeforeUnloadDialogCancelled() override { CancelClose(); }
  void CancelClose() {
    if (!close_requested || closing || cancel_notified) return;
    cancel_notified = true;
    close_requested = false;
    owner->Queue(*this, BOAZ_HOST_PAGE_CLOSE_CANCELLED);
  }
  void WebContentsDestroyed() override { owner->Destroyed(*this); }
  void ObserveReplacement(content::WebContents* contents) { Observe(contents); }

  raw_ref<Impl> owner;
  BoazHostPage id = NextHandle();
  BoazHostWindow window;
  uint64_t generation = 0;
  uint64_t view_revision = 0;
  int extension_window_id = -1;
  bool close_requested = false;
  bool cancel_notified = false;
  bool closing = false;
  bool destroyed = false;
  bool created_delivered = false;
  bool view_available = false;
  std::optional<Snapshot> final_snapshot;
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
  result.state.extension_tab_id = -1;
  result.state.extension_window_id = page.extension_window_id;
  if (auto* contents = page.web_contents()) {
    result.url = contents->GetLastCommittedURL().spec();
    result.title = base::UTF16ToUTF8(contents->GetTitle());
    result.state.extension_tab_id = extensions::ExtensionTabUtil::GetTabId(contents);
    result.state.loading = contents->IsLoading();
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
  auto snapshot = Capture(page);
  page.final_snapshot = snapshot;
  snapshot.state.url = snapshot.url.c_str();
  snapshot.state.title = snapshot.title.c_str();
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
BoazHostResult TabRegistry::Reload(BoazHostPage id) {
  BOAZ_FIND_PAGE();
  page->web_contents()->GetController().Reload(content::ReloadType::NORMAL, true);
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

}  // namespace boaz
