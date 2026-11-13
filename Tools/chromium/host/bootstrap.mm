#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <map>
#include <utility>
#include "bootstrap.h"
#include "boaz_host.h"
#include "native_window.h"
#include "extension_actions.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/common/extension.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/geometry/rect.h"
#include "tab_registry.h"
#include "base/auto_reset.h"
#include "base/check.h"
#include "base/check_op.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/memory/raw_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "content/public/browser/browser_thread.h"

namespace boaz {
namespace {
constexpr char kProfiles[] = "/Volumes/BoazBuild/cef/direct/profiles";
constexpr char kLibrary[] = "/Volumes/BoazBuild/cef/direct/ui/libBoazNativeUI.dylib";
struct Window {
  base::WeakPtr<BrowserWindowInterface> browser;
  BoazHostWindowOptions options;
  base::CallbackListSubscription cancelled;
  std::unique_ptr<NativeExtensionActions> actions;
  base::CallbackListSubscription closing;
};
struct State {
  raw_ptr<Profile> profile = nullptr;
  base::FilePath profile_path;
  std::unique_ptr<ScopedProfileKeepAlive> profile_keep_alive;
  std::unique_ptr<ScopedKeepAlive> process_keep_alive;
  std::unique_ptr<TabRegistry> tabs;
  BoazHostCallbacks callbacks{};
  raw_ptr<const BoazHostWindowOptions> pending = nullptr;
  std::map<BoazHostWindow, Window> windows;
  bool in_callback = false;
  bool exit_requested = false;
  bool finished = false;
  bool cleanup_pending = false;
};
State* state = nullptr;
BoazHostResult Check() {
  if (!content::BrowserThread::CurrentlyOn(content::BrowserThread::UI))
    return BOAZ_HOST_WRONG_THREAD;
  if (!state || !state->tabs || state->in_callback) return BOAZ_HOST_UNAVAILABLE;
  if (state->finished) return BOAZ_HOST_CLOSING;
  return BOAZ_HOST_OK;
}
template <typename F> auto Notify(F callback) {
  base::AutoReset<bool> guard(&state->in_callback, true);
  return callback();
}
bool ValidOptions(const BoazHostWindowOptions* o) {
  if (!o || o->size < sizeof(*o) || !o->native_nswindow || !o->context ||
      !o->content_view || !o->address_field || !o->focus_address ||
      !o->focus_toolbar || !o->handle_key || !o->exclusive_access_notice) return false;
  NSWindow* window = (__bridge NSWindow*)o->native_nswindow;
  return Notify([&] {
    NSView* view = (__bridge NSView*)o->content_view(o->context);
    NSTextField* field = (__bridge NSTextField*)o->address_field(o->context);
    return [window isKindOfClass:[NSWindow class]] && view.window == window &&
        [field isKindOfClass:[NSTextField class]] && field.window == window;
  });
}
void FinishIfDrained() {
  if (!state->exit_requested || !state->windows.empty() || state->finished) return;
  state->finished = true;
  Notify([] { state->callbacks.shutdown_ready(state->callbacks.context); });
  // Swift queues its cleanup on this same main dispatch queue first.
  state->cleanup_pending = true;
  dispatch_async(dispatch_get_main_queue(), ^{
    CHECK(state);
    state->cleanup_pending = false;
    state->profile = nullptr;
    state->profile_keep_alive.reset();
    state->process_keep_alive.reset();
  });
}
BoazHostResult SetCallbacks(const BoazHostCallbacks* callbacks) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  if (state->callbacks.page_event) return BOAZ_HOST_UNAVAILABLE;
  if (!callbacks || callbacks->size < sizeof(*callbacks) || !callbacks->page_event ||
      !callbacks->prepare_window || !callbacks->window_created ||
      !callbacks->window_closed || !callbacks->shutdown_ready) return BOAZ_HOST_INVALID_ARGUMENT;
  state->callbacks = *callbacks;
  BoazHostCallbacks proxy = *callbacks;
  proxy.context = state;
  proxy.page_event = [](void*, BoazHostPageEvent event, const BoazHostPageState* page) {
    Notify([&] { state->callbacks.page_event(state->callbacks.context, event, page); });
  };
  proxy.window_closed = [](void*, BoazHostWindow window) {
    Notify([&] { state->callbacks.window_closed(state->callbacks.context, window); });
    state->windows.erase(window);
    FinishIfDrained();
  };
  return state->tabs->SetCallbacks(&proxy);
}
BoazHostResult CreateWindow(const BoazHostWindowOptions* options, BoazHostWindow* output) {
  if (output) *output = 0;
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  if (!output || !ValidOptions(options)) return BOAZ_HOST_INVALID_ARGUMENT;
  if (state->pending || !state->callbacks.page_event || state->exit_requested)
    return BOAZ_HOST_UNAVAILABLE;
  base::AutoReset<raw_ptr<const BoazHostWindowOptions>> pending(
      &state->pending, raw_ptr<const BoazHostWindowOptions>(options));
  BrowserWindowCreateParams params(state->profile.get(), true);
  params.omit_from_session_restore = true;
  params.should_trigger_session_restore = false;
  BrowserWindowInterface* browser = ::CreateBrowserWindow(std::move(params));
  CHECK(browser);
  for (const auto& [id, window] : state->windows) {
    if (window.browser.get() == browser) { *output = id; return BOAZ_HOST_OK; }
  }
  CHECK(false) << "Native browser factory did not register its window";
}
BoazHostResult CloseWindow(BoazHostWindow id) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  auto it = state->windows.find(id);
  if (it == state->windows.end() || !it->second.browser) return BOAZ_HOST_INVALID_HANDLE;
  UnloadController::From(it->second.browser.get())->OnWindowClosing();
  return BOAZ_HOST_OK;
}
BoazHostResult Shutdown() {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  state->exit_requested = true;
  chrome::AttemptExit();
  FinishIfDrained();
  return BOAZ_HOST_OK;
}
#define FORWARD(name, signature, call) \
  BoazHostResult name signature { \
    if (auto r = Check(); r != BOAZ_HOST_OK) return r; \
    return state->tabs->call; \
  }
BoazHostResult CreatePage(BoazHostWindow w, const char* u, BoazHostPage* p) {
  if (p) *p = 0;
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  return state->tabs->CreatePage(w, u, p);
}
FORWARD(Navigate, (BoazHostPage p, const char* u), Navigate(p,u))
FORWARD(Back, (BoazHostPage p), GoBack(p))
FORWARD(Forward, (BoazHostPage p), GoForward(p))
FORWARD(Reload, (BoazHostPage p), Reload(p))
FORWARD(Activate, (BoazHostPage p, uint8_t f), ActivatePage(p,f != 0))
BoazHostResult NativeView(BoazHostPage p, void** v) {
  if (v) *v = nullptr;
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  return state->tabs->GetNativeView(p, v);
}
FORWARD(ClosePage, (BoazHostPage p), ClosePage(p))
#undef FORWARD
BoazHostResult EnumerateExtensions(BoazHostWindow id,
    BoazHostExtensionVisitor visitor, void* context) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  if (!visitor) return BOAZ_HOST_INVALID_ARGUMENT;
  auto it = state->windows.find(id);
  if (it == state->windows.end() || !it->second.browser)
    return BOAZ_HOST_INVALID_HANDLE;
  auto* browser = it->second.browser.get();
  if (browser->IsDeleteScheduled()) return BOAZ_HOST_CLOSING;
  auto* registry = extensions::ExtensionRegistry::Get(browser->GetProfile());
  auto* manager = extensions::ExtensionActionManager::Get(browser->GetProfile());
  if (!registry || !manager) return BOAZ_HOST_UNAVAILABLE;
  for (const auto& extension : registry->enabled_extensions()) {
    if (!manager->GetExtensionAction(*extension)) continue;
    Notify([&] { visitor(context, extension->id().c_str(), extension->name().c_str()); });
  }
  return BOAZ_HOST_OK;
}
BoazHostResult InvokeExtension(BoazHostWindow id, BoazHostPage page,
    const char* extension_id, void* anchor, int32_t x, int32_t y,
    int32_t width, int32_t height) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  if (!extension_id || !anchor || width <= 0 || height <= 0)
    return BOAZ_HOST_INVALID_ARGUMENT;
  auto it = state->windows.find(id);
  if (it == state->windows.end() || !it->second.browser)
    return BOAZ_HOST_INVALID_HANDLE;
  auto* browser = it->second.browser.get();
  if (browser->IsDeleteScheduled()) return BOAZ_HOST_CLOSING;
  auto* active = browser->GetActiveTabInterface();
  void* expected_view = nullptr;
  auto result = state->tabs->GetNativeView(page, &expected_view);
  if (result != BOAZ_HOST_OK) return result;
  if (!active || !expected_view ||
      expected_view != NativeViewForContents(active->GetContents()))
    return BOAZ_HOST_INVALID_HANDLE;
  if (!it->second.actions)
    it->second.actions = std::make_unique<NativeExtensionActions>(browser);
  switch (it->second.actions->Invoke(active->GetContents(), extension_id,
                                     anchor, gfx::Rect(x, y, width, height))) {
    case NativeExtensionActions::Result::kOk: return BOAZ_HOST_OK;
    case NativeExtensionActions::Result::kInvalidTarget: return BOAZ_HOST_INVALID_HANDLE;
    case NativeExtensionActions::Result::kInvalidAnchor: return BOAZ_HOST_INVALID_ARGUMENT;
    case NativeExtensionActions::Result::kUnavailable:
    case NativeExtensionActions::Result::kUnsupported: return BOAZ_HOST_UNAVAILABLE;
  }
}
const BoazHostAPI kAPI = {sizeof(BoazHostAPI), BOAZ_HOST_ABI_VERSION,
  SetCallbacks, CreateWindow, CreatePage, Navigate, Back, Forward, Reload,
  Activate, NativeView, ClosePage, CloseWindow, Shutdown,
  EnumerateExtensions, InvokeExtension};

class MainParts final : public ChromeBrowserMainExtraParts {
 public:
  void PreEarlyInitialization() override {
    CHECK(!state);
    state = new State;
    auto* command = base::CommandLine::ForCurrentProcess();
    CHECK(command->HasSwitch("no-startup-window"));
    CHECK(command->HasSwitch("no-first-run"));
    CHECK_EQ(command->GetSwitchValueASCII("profile-directory"), "Default");
    auto path = command->GetSwitchValuePath("user-data-dir");
    CHECK(path.IsAbsolute());
    CHECK(base::DirectoryExists(path));
    CHECK_EQ(base::MakeAbsoluteFilePath(path), path);
    CHECK(base::FilePath(kProfiles).IsParent(path));
    // Canonical spelling rejects symlinks in every existing path component.
    state->profile_path = path.AppendASCII("Default");
    CHECK(!base::IsLink(state->profile_path));
    if (base::PathExists(state->profile_path))
      CHECK_EQ(base::MakeAbsoluteFilePath(state->profile_path), state->profile_path);
  }
  void PostProfileInit(Profile* profile, bool initial) override {
    if (!initial) return;
    CHECK(profile->IsRegularProfile());
    CHECK_EQ(profile->GetPath(), state->profile_path);
    CHECK(!state->profile);
    state->profile = profile;
    state->profile_keep_alive = ScopedProfileKeepAlive::TryAcquire(
        profile, ProfileKeepAliveOrigin::kBrowserWindow);
    CHECK(state->profile_keep_alive);
    state->process_keep_alive = std::make_unique<ScopedKeepAlive>(
        KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
  }
  void PostMainMessageLoopRun() override {
    CHECK(state);
    CHECK(state->finished);
    CHECK(state->windows.empty());
    CHECK(!state->cleanup_pending);
    CHECK(!state->profile);
    CHECK(!state->profile_keep_alive);
    CHECK(!state->process_keep_alive);
    state->tabs.reset();
    delete std::exchange(state, nullptr);
  }
  void PostBrowserStart() override {
    CHECK(state->profile);
    state->tabs = std::make_unique<TabRegistry>();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([] {
          const base::FilePath library(kLibrary);
          CHECK_EQ(base::MakeAbsoluteFilePath(library), library);
          void* handle = dlopen(kLibrary, RTLD_NOW | RTLD_LOCAL);
          CHECK(handle) << "Native UI library could not load";
          auto start = reinterpret_cast<BoazNativeUIStart>(dlsym(handle, "BoazNativeUIStart"));
          CHECK(start);
          CHECK_EQ(start(&kAPI), BOAZ_HOST_OK);
        }));
  }
};
}  // namespace

bool NativeHostEnabled() {
  return base::CommandLine::ForCurrentProcess()->HasSwitch("boaz-native-host");
}
std::unique_ptr<ChromeBrowserMainExtraParts> CreateNativeHostMainParts() {
  CHECK(NativeHostEnabled());
  return std::make_unique<MainParts>();
}
bool IsNativeHostBrowser(BrowserWindowInterface* browser) {
  if (!state) return false;
  for (const auto& [id, window] : state->windows)
    if (window.browser.get() == browser) return true;
  return false;
}
std::unique_ptr<BrowserWindow, BrowserWindowDeleter>
CreateNativeHostBrowserWindow(BrowserWindowInterface* browser) {
  CHECK_EQ(Check(), BOAZ_HOST_OK);
  CHECK_EQ(browser->GetProfile(), state->profile);
  BoazHostWindowOptions options{};
  if (state->pending) {
    options = *state->pending;
    state->pending = nullptr;
  }
  else {
    CHECK(state->callbacks.prepare_window);
    CHECK_EQ(Notify([&] { return state->callbacks.prepare_window(
        state->callbacks.context, &options); }), BOAZ_HOST_OK);
  }
  CHECK(ValidOptions(&options));
  auto weak = browser->GetWeakPtr();
  NativeWindowServices services;
  services.request_close = base::BindRepeating([](base::WeakPtr<BrowserWindowInterface> b) {
    if (b) UnloadController::From(b.get())->OnWindowClosing();
  }, weak);
  services.content_view = base::BindRepeating([](BoazHostWindowOptions options) {
    return Notify([&] { return options.content_view(options.context); });
  }, options);
  services.address_field = base::BindRepeating([](BoazHostWindowOptions options) {
    return Notify([&] { return options.address_field(options.context); });
  }, options);
  services.focus_address = base::BindRepeating([](BoazHostWindowOptions options) {
    Notify([&] { options.focus_address(options.context); });
  }, options);
  services.focus_toolbar = base::BindRepeating([](BoazHostWindowOptions options) {
    Notify([&] { options.focus_toolbar(options.context); });
  }, options);
  services.handle_key = base::BindRepeating([](BoazHostWindowOptions options, const input::NativeWebKeyboardEvent& event) {
    if (event.skip_if_unhandled || !event.os_event.Get()) return false;
    return Notify([&] { return options.handle_key(options.context,
        (__bridge void*)event.os_event.Get()) != 0; });
  }, options);
  services.exclusive_access_notice = base::BindRepeating([](BoazHostWindowOptions options, const std::string& text, bool visible) {
    Notify([&] { options.exclusive_access_notice(options.context, text.c_str(), visible); });
  }, options);
  auto window = CreateNativeBrowserWindow(browser, options.native_nswindow, services);
  CHECK(window);
  auto id = state->tabs->RegisterWindow(static_cast<Browser*>(browser), options.native_nswindow);
  CHECK(id);
  Window record{weak, options, browser->RegisterBrowserCloseCancelled(base::BindRepeating(
      [](BrowserWindowInterface*, BrowserWindowInterface::ClosingStatus) {
        state->exit_requested = false;
      })), nullptr, {}};
  record.closing = browser->RegisterBrowserDidClose(base::BindRepeating(
      [](BoazHostWindow id, BrowserWindowInterface*) {
        auto it = state->windows.find(id);
        if (it != state->windows.end()) it->second.actions.reset();
      }, id));
  CHECK(state->windows.emplace(id, std::move(record)).second);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](BoazHostWindow id) {
        auto it = state->windows.find(id);
        if (it == state->windows.end() || !it->second.browser) return;
        Notify([&] { state->callbacks.window_created(state->callbacks.context,
            id, it->second.options.context); });
      }, id));
  return window;
}
}  // namespace boaz
