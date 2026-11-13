#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <map>
#include <limits>
#include <optional>
#include <string_view>
#include <utility>
#include "bootstrap.h"
#include "launch.h"
#include "base/path_service.h"
#include "chrome/common/chrome_paths.h"
#include "boaz_host.h"
#include "native_window.h"
#include "native_profiles.h"
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
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
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
  uint64_t pending_scripts = 0;
  uint64_t pending_captures = 0;
  uint64_t pending_profiles = 0;
  std::unique_ptr<NativeProfiles> profiles;
  bool in_callback = false;
  bool exit_requested = false;
  bool finished = false;
  bool cleanup_pending = false;
};
State* state = nullptr;
auto& PendingExternalURLs() {
  static base::NoDestructor<std::vector<std::vector<std::string>>> urls;
  return *urls;
}
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
void DeliverExternalURLs() {
  if (!state || state->finished || !state->callbacks.external_urls) return;
  auto batches = std::exchange(PendingExternalURLs(), {});
  for (const auto& batch : batches) {
    std::vector<const char*> values;
    values.reserve(batch.size());
    for (const auto& url : batch) values.push_back(url.c_str());
    Notify([&] { state->callbacks.external_urls(state->callbacks.context,
        values.data(), values.size()); });
  }
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
        [field isKindOfClass:[NSTextField class]] && (!field.window || field.window == window);
  });
}
void FinishIfDrained() {
  if (!state->exit_requested || !state->windows.empty() ||
      state->pending_scripts || state->pending_captures || state->pending_profiles || state->finished) return;
  state->finished = true;
  Notify([] { state->callbacks.shutdown_ready(state->callbacks.context); });
  // Swift queues its cleanup on this same main dispatch queue first.
  state->cleanup_pending = true;
  dispatch_async(dispatch_get_main_queue(), ^{
    CHECK(state);
    state->cleanup_pending = false;
    state->profiles.reset();
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
  auto result = state->tabs->SetCallbacks(&proxy);
  if (result == BOAZ_HOST_OK) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&DeliverExternalURLs));
  }
  return result;
}
BoazHostResult CreateWindowWithProfile(Profile* profile, const BoazHostWindowOptions* options, BoazHostWindow* output) {
  if (output) *output = 0;
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  if (!profile || !output || !ValidOptions(options)) return BOAZ_HOST_INVALID_ARGUMENT;
  if (state->pending || !state->callbacks.page_event || state->exit_requested)
    return BOAZ_HOST_UNAVAILABLE;
  base::AutoReset<raw_ptr<const BoazHostWindowOptions>> pending(
      &state->pending, raw_ptr<const BoazHostWindowOptions>(options));
  BrowserWindowCreateParams params(profile, true);
  params.omit_from_session_restore = true;
  params.should_trigger_session_restore = false;
  BrowserWindowInterface* browser = ::CreateBrowserWindow(std::move(params));
  CHECK(browser);
  for (const auto& [id, window] : state->windows) {
    if (window.browser.get() == browser) { *output = id; return BOAZ_HOST_OK; }
  }
  CHECK(false) << "Native browser factory did not register its window";
}
BoazHostResult CreateWindow(const BoazHostWindowOptions* options, BoazHostWindow* output) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return CreateWindowWithProfile(state->profile.get(), options, output);
}
BoazHostResult PrepareProfile(const char* identifier, uint8_t is_private,
    BoazHostProfileCompletion completion, void* context) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  if (!identifier || !completion || is_private > 1) return BOAZ_HOST_INVALID_ARGUMENT;
  if (state->exit_requested || !state->profiles) return BOAZ_HOST_CLOSING;
  CHECK_LT(state->pending_profiles, std::numeric_limits<uint64_t>::max());
  ++state->pending_profiles;
  state->profiles->Acquire(identifier, is_private != 0, base::BindOnce(
      [](BoazHostProfileCompletion completion, void* context,
         BoazHostResult result, BoazHostProfile profile) {
        if (state->exit_requested && result == BOAZ_HOST_OK) {
          state->profiles->Release(profile);
          result = BOAZ_HOST_CLOSING;
          profile = 0;
        }
        Notify([&] { completion(context, result, profile); });
        CHECK_GT(state->pending_profiles, 0u);
        --state->pending_profiles;
        FinishIfDrained();
      }, completion, context));
  return BOAZ_HOST_OK;
}
BoazHostResult CreateProfileWindow(BoazHostProfile profile,
    const BoazHostWindowOptions* options, BoazHostWindow* output) {
  if (output) *output = 0;
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  Profile* resolved = state->profiles ? state->profiles->Resolve(profile) : nullptr;
  if (!resolved) return BOAZ_HOST_INVALID_HANDLE;
  return CreateWindowWithProfile(resolved, options, output);
}
BoazHostResult ReleaseProfile(BoazHostProfile profile) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  if (state->pending_profiles) return BOAZ_HOST_UNAVAILABLE;
  Profile* resolved = state->profiles ? state->profiles->Resolve(profile) : nullptr;
  if (!resolved) return BOAZ_HOST_INVALID_HANDLE;
  for (const auto& [id, window] : state->windows)
    if (window.browser && window.browser->GetProfile() == resolved) return BOAZ_HOST_UNAVAILABLE;
  return state->profiles->Release(profile);
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
BoazHostResult CaptureDocument(BoazHostPage page, BoazHostDocument* document) {
  if (document) *document = 0;
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  return state->tabs->CaptureDocument(page, document);
}
BoazHostResult CaptureDocumentOrigin(BoazHostPage page, BoazHostDocument* document,
    char* origin, size_t capacity) {
  if (document) *document = 0;
  if (origin && capacity) origin[0] = '\0';
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->CaptureDocumentOrigin(page, document, origin, capacity);
}
BoazHostResult ReleaseDocument(BoazHostPage page, BoazHostDocument document) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  return state->tabs->ReleaseDocument(page, document);
}
BoazHostScriptStatus ScriptStatus(TrustedExecution::Status status) {
  switch (status) {
    case TrustedExecution::Status::kSuccess: return BOAZ_SCRIPT_SUCCESS;
    case TrustedExecution::Status::kInvalidTarget: return BOAZ_SCRIPT_INVALID_TARGET;
    case TrustedExecution::Status::kNavigation: return BOAZ_SCRIPT_NAVIGATION;
    case TrustedExecution::Status::kClosed: return BOAZ_SCRIPT_CLOSED;
    case TrustedExecution::Status::kRendererFailed: return BOAZ_SCRIPT_RENDERER_FAILED;
    case TrustedExecution::Status::kTimeout: return BOAZ_SCRIPT_TIMEOUT;
    case TrustedExecution::Status::kInvalidArgument: return BOAZ_SCRIPT_INVALID_ARGUMENT;
    case TrustedExecution::Status::kBusy: return BOAZ_SCRIPT_BUSY;
  }
}
BoazHostResult ExecuteTrusted(BoazHostPage page, BoazHostDocument document,
    const char* source, size_t source_length, const char* arguments,
    size_t arguments_length, BoazHostScriptCompletion completion, void* context) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  constexpr size_t kLimit = 64 * 1024;
  if (!completion || !source || !arguments || !source_length ||
      source_length > kLimit || arguments_length > kLimit)
    return BOAZ_HOST_INVALID_ARGUMENT;
  std::string_view function(source, source_length);
  if (!base::IsStringUTF8(function)) return BOAZ_HOST_INVALID_ARGUMENT;
  auto dict = base::JSONReader::ReadDict(std::string_view(arguments, arguments_length),
                                       base::JSON_PARSE_RFC, 32);
  if (!dict) return BOAZ_HOST_INVALID_ARGUMENT;
  CHECK_LT(state->pending_scripts, std::numeric_limits<uint64_t>::max());
  ++state->pending_scripts;
  auto result = state->tabs->ExecuteTrusted(page, document, base::UTF8ToUTF16(function),
      std::move(*dict), base::BindOnce(
          [](BoazHostPage page, BoazHostDocument document, BoazHostScriptCompletion callback,
             void* context, TrustedExecution::Outcome outcome) {
            CHECK(state);
            auto status = ScriptStatus(outcome.status);
            auto json = outcome.status == TrustedExecution::Status::kSuccess
                ? base::WriteJson(outcome.value) : std::nullopt;
            if (status == BOAZ_SCRIPT_SUCCESS && !json) status = BOAZ_SCRIPT_INVALID_ARGUMENT;
            Notify([&] { callback(context, page, document, status, json ? json->c_str() : nullptr); });
            CHECK_GT(state->pending_scripts, 0u);
            --state->pending_scripts;
            FinishIfDrained();
          }, page, document, completion, context));
  if (result != BOAZ_HOST_OK) --state->pending_scripts;
  return result;
}
BoazHostResult WindowLayout(BoazHostWindow window, BoazHostWindowLayout* layout) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  return state->tabs->GetWindowLayout(window, layout);
}
BoazHostResult SetSplit(BoazHostWindow window, BoazHostPage first,
    BoazHostPage second, uint8_t vertical, double ratio) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  if (vertical > 1) return BOAZ_HOST_INVALID_ARGUMENT;
  return state->tabs->SetSplit(window, first, second, vertical != 0, ratio);
}
BoazHostResult ClearSplit(BoazHostWindow window) {
  if (auto r = Check(); r != BOAZ_HOST_OK) return r;
  return state->tabs->ClearSplit(window);
}
BoazHostResult SetAudioMuted(BoazHostPage page, uint8_t muted) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  if (muted > 1) return BOAZ_HOST_INVALID_ARGUMENT;
  return state->tabs->SetAudioMuted(page, muted != 0);
}
BoazHostResult IsBusyForResidency(BoazHostPage page, uint8_t* busy) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->IsBusyForResidency(page, busy);
}
BoazHostResult GetZoomFactor(BoazHostPage page, double* factor) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->GetZoomFactor(page, factor);
}
BoazHostResult SetZoomFactor(BoazHostPage page, double factor) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->SetZoomFactor(page, factor);
}
BoazHostResult FindText(BoazHostPage page, const char* text, uint8_t forward) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  if (!text || forward > 1) return BOAZ_HOST_INVALID_ARGUMENT;
  return state->tabs->FindText(page, text, forward != 0);
}
BoazHostResult StopFind(BoazHostPage page) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->StopFind(page);
}
BoazHostResult StopLoading(BoazHostPage page) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->StopLoading(page);
}
BoazHostResult EnumerateHistory(BoazHostPage page, BoazHostHistoryVisitor visitor, void* context) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  if (!visitor) return BOAZ_HOST_INVALID_ARGUMENT;
  struct Visit { BoazHostHistoryVisitor visitor; raw_ptr<void> context; } visit{visitor, context};
  return state->tabs->EnumerateHistory(page,
      [](void* opaque, int32_t entry, int32_t offset, const char* url, const char* title) {
        auto* visit = static_cast<Visit*>(opaque);
        Notify([&] { visit->visitor(visit->context, entry, offset, url, title); });
      }, &visit);
}
BoazHostResult GoToHistoryEntry(BoazHostPage page, int32_t entry) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->GoToHistoryEntry(page, entry);
}
BoazHostResult ShowDevTools(BoazHostPage page, BoazHostDevToolsAction action) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->ShowDevTools(page, action);
}
BoazHostResult CaptureVisible(BoazHostPage page, uint64_t request, int32_t width,
    int32_t height, BoazHostCaptureCompletion completion, void* context) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  if (!completion) return BOAZ_HOST_INVALID_ARGUMENT;
  CHECK_LT(state->pending_captures, std::numeric_limits<uint64_t>::max());
  ++state->pending_captures;
  auto result = state->tabs->CaptureVisible(page, request, width, height,
      base::BindOnce([](BoazHostPage page, uint64_t request,
                       BoazHostCaptureCompletion completion, void* context,
                       VisiblePageCapture::Outcome outcome) {
        CHECK(state);
        Notify([&] { completion(context, page, request, outcome.status,
            outcome.png.empty() ? nullptr : outcome.png.data(), outcome.png.size()); });
        CHECK_GT(state->pending_captures, 0u);
        --state->pending_captures;
        FinishIfDrained();
      }, page, request, completion, context));
  if (result != BOAZ_HOST_OK) --state->pending_captures;
  return result;
}
BoazHostResult CancelCapture(BoazHostPage page, uint64_t request) {
  if (auto result = Check(); result != BOAZ_HOST_OK) return result;
  return state->tabs->CancelCapture(page, request);
}
const BoazHostAPI kAPI = {sizeof(BoazHostAPI), BOAZ_HOST_ABI_VERSION,
  SetCallbacks, CreateWindow, CreatePage, Navigate, Back, Forward, Reload,
  Activate, NativeView, ClosePage, CloseWindow, Shutdown,
  EnumerateExtensions, InvokeExtension, CaptureDocument, ReleaseDocument, ExecuteTrusted,
  WindowLayout, SetSplit, ClearSplit, PrepareProfile, CreateProfileWindow, ReleaseProfile, SetAudioMuted, GetZoomFactor, SetZoomFactor, FindText, StopFind, StopLoading, EnumerateHistory, GoToHistoryEntry, IsBusyForResidency, ShowDevTools, CaptureDocumentOrigin, CaptureVisible, CancelCapture};

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
    if (const auto packaged = PackagedApplicationUserDataPath()) {
      base::FilePath resolved;
      CHECK(base::PathService::Get(chrome::DIR_USER_DATA, &resolved));
      CHECK_EQ(path, *packaged);
      CHECK_EQ(resolved, *packaged);
    } else {
      CHECK(base::FilePath(kProfiles).IsParent(path));
    }
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
    CHECK_EQ(state->pending_scripts, 0u);
    CHECK_EQ(state->pending_profiles, 0u);
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
    state->profiles = std::make_unique<NativeProfiles>(state->profile_path.DirName(), state->profile.get());
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([] {
          const bool application_ui = base::CommandLine::ForCurrentProcess()->HasSwitch("boaz-app-ui");
          NSString* bundled_ui = [[[NSBundle mainBundle] privateFrameworksPath]
              stringByAppendingPathComponent:@"libBoazApplicationUI.dylib"];
          const base::FilePath library(application_ui ? [bundled_ui fileSystemRepresentation] : kLibrary);
          CHECK_EQ(base::MakeAbsoluteFilePath(library), library);
          void* handle = dlopen(library.value().c_str(), RTLD_NOW | RTLD_LOCAL);
          CHECK(handle) << "Native UI library could not load";
          auto start = reinterpret_cast<BoazNativeUIStart>(dlsym(handle, "BoazNativeUIStart"));
          CHECK(start);
          CHECK_EQ(start(&kAPI), BOAZ_HOST_OK);
        }));
  }
};
}  // namespace

bool RouteExternalURLs(std::vector<std::string> urls) {
  if (!NativeHostEnabled() ||
      !base::CommandLine::ForCurrentProcess()->HasSwitch("boaz-app-ui")) return false;
  if (!urls.empty()) PendingExternalURLs().push_back(std::move(urls));
  if (state && state->callbacks.external_urls) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&DeliverExternalURLs));
  }
  return true;
}
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
  CHECK(browser->GetProfile() == state->profile ||
        (state->profiles && state->profiles->Owns(browser->GetProfile())));
  BoazHostWindowOptions options{};
  if (state->pending) {
    options = *state->pending;
    state->pending = nullptr;
  }
  else {
    CHECK(state->callbacks.prepare_window);
    CHECK_EQ(Notify([&] { return state->callbacks.prepare_window(
        state->callbacks.context, state->profiles->HandleFor(browser->GetProfile()), &options); }), BOAZ_HOST_OK);
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
