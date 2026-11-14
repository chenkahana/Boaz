#include "native_devtools.h"
#import <AppKit/AppKit.h>
#include "bootstrap.h"
#include <map>
#include "base/no_destructor.h"
#include "base/check.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

@interface BoazDockContainer : NSView
@property(nonatomic, copy) void (^layoutChanged)(void);
@end
@implementation BoazDockContainer
@synthesize layoutChanged = _layoutChanged;
- (BOOL)isFlipped { return YES; }
- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  if (_layoutChanged) _layoutChanged();
}
- (void)setBoundsSize:(NSSize)size {
  [super setBoundsSize:size];
  if (_layoutChanged) _layoutChanged();
}
@end

namespace boaz {
namespace {
void CheckUI() {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK([NSThread isMainThread]);
}
struct DockPreferences {
  int current = 0;
  int last = 0;
  base::RepeatingCallback<void(int, int)> changed;
};
auto& Preferences() {
  static base::NoDestructor<std::map<BrowserWindowInterface*, DockPreferences>> preferences;
  return *preferences;
}
DockPreferences* PreferencesFor(content::WebContents* contents) {
  if (!contents) return nullptr;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  auto it = Preferences().find(browser);
  return it == Preferences().end() ? nullptr : &it->second;
}
int PreferenceKind(const std::string& name) {
  if (name == "currentDockState" || name == "current-dock-state") return 1;
  if (name == "lastDockState" || name == "last-dock-state") return 2;
  return 0;
}
const char* EncodedSide(int side) {
  switch (side) {
    case 1: return "\"bottom\"";
    case 2: return "\"left\"";
    case 3: return "\"undocked\"";
    default: return "\"right\"";
  }
}
void Change(DockPreferences& prefs, int current, int last) {
  if (prefs.current == current && prefs.last == last) return;
  prefs.current = current;
  prefs.last = last;
  if (prefs.changed) prefs.changed.Run(current, last);
}
class NativeDock final : public content::WebContentsObserver,
                         public content::WebContentsUserData<NativeDock> {
 public:
  ~NativeDock() override { TearDown(); }
  NSView* Container() {
    CheckUI();
    if (!web_contents()) return nil;
    NSView* view = web_contents()->GetNativeView().GetNativeNSView();
    // A frontend currently hosted by another dock must stay there until the
    // upstream transfer barrier detaches it.
    if ([view.superview isKindOfClass:[BoazDockContainer class]] &&
        view.superview != container_) return container_;
    page_ = view;
    if (page_ && page_.superview != container_) [container_ addSubview:page_];
    Layout();
    return container_;
  }
  void Update() {
    CheckUI();
    if (!web_contents()) return;
    DevToolsContentsResizingStrategy strategy;
    auto* frontend = DevToolsWindow::GetInTabWebContents(web_contents(), &strategy);
    NSView* view = frontend ? frontend->GetNativeView().GetNativeNSView() : nil;
    if (frontend_ != view) {
      Detach();
      frontend_ = view;
      if (frontend_) {
        [container_ addSubview:frontend_ positioned:NSWindowBelow relativeTo:page_];
      }
    }
    strategy_.CopyFrom(strategy);
    Layout();
  }
  void Detach() {
    CheckUI();
    const bool focused = frontend_ && container_.window &&
        [container_.window.firstResponder isKindOfClass:[NSView class]] &&
        [(NSView*)container_.window.firstResponder isDescendantOf:frontend_];
    if (frontend_.superview == container_) [frontend_ removeFromSuperview];
    frontend_ = nil;
    if (page_.superview == container_) {
      page_.hidden = NO;
      page_.frame = container_.bounds;
      if (focused) [container_.window makeFirstResponder:page_];
    }
  }
 private:
  friend class content::WebContentsUserData<NativeDock>;
  explicit NativeDock(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<NativeDock>(*contents) {
    CheckUI();
    container_ = [[BoazDockContainer alloc] initWithFrame:NSZeroRect];
    auto weak = weak_factory_.GetWeakPtr();
    container_.layoutChanged = ^{ if (weak) weak->Layout(); };
  }
  void Layout() {
    CheckUI();
    if (!container_ || !page_ || page_.superview != container_) return;
    if (!frontend_ || frontend_.superview != container_) {
      page_.hidden = NO;
      page_.frame = container_.bounds;
      return;
    }
    gfx::Rect frontend_bounds, page_bounds;
    ApplyDevToolsContentsResizingStrategy(strategy_,
        gfx::Rect(0, 0, static_cast<int>(container_.bounds.size.width),
                  static_cast<int>(container_.bounds.size.height)),
        &frontend_bounds, &page_bounds);
    frontend_.frame = NSMakeRect(frontend_bounds.x(), frontend_bounds.y(),
        frontend_bounds.width(), frontend_bounds.height());
    page_.frame = NSMakeRect(page_bounds.x(), page_bounds.y(),
        page_bounds.width(), page_bounds.height());
    page_.hidden = strategy_.hide_inspected_contents();
  }
  void WebContentsDestroyed() override { TearDown(); }
  void TearDown() {
    CheckUI();
    weak_factory_.InvalidateWeakPtrs();
    container_.layoutChanged = nil;
    Detach();
    if (page_.superview == container_) [page_ removeFromSuperview];
    page_ = nil;
  }
  BoazDockContainer* __strong container_;
  NSView* __strong page_;
  NSView* __strong frontend_;
  DevToolsContentsResizingStrategy strategy_;
  base::WeakPtrFactory<NativeDock> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeDock);
}
void RegisterNativeDevToolsPreferences(BrowserWindowInterface* browser,
    base::RepeatingCallback<void(int, int)> changed) {
  CheckUI();
  CHECK(browser);
  CHECK(!Preferences().contains(browser));
  Preferences().emplace(browser, DockPreferences{0, 0, std::move(changed)});
}
void UnregisterNativeDevToolsPreferences(BrowserWindowInterface* browser) {
  CheckUI();
  Preferences().erase(browser);
}
bool SetNativeDevToolsPreferences(BrowserWindowInterface* browser, int current, int last) {
  CheckUI();
  auto it = Preferences().find(browser);
  if (it == Preferences().end() || current < 0 || current > 3 || last < 0 || last > 2)
    return false;
  Change(it->second, current, last);
  return true;
}
std::optional<std::string> GetNativeDevToolsPreference(content::WebContents* contents,
    const std::string& name) {
  CheckUI();
  auto* prefs = PreferencesFor(contents);
  int kind = PreferenceKind(name);
  if (!prefs || !kind) return std::nullopt;
  return EncodedSide(kind == 1 ? prefs->current : prefs->last);
}
bool SetNativeDevToolsPreference(content::WebContents* contents,
    const std::string& name, const std::string& value) {
  CheckUI();
  auto* prefs = PreferencesFor(contents);
  int kind = PreferenceKind(name);
  if (!prefs || !kind) return false;
  for (int side = 0; side <= (kind == 1 ? 3 : 2); ++side) {
    if (value == EncodedSide(side)) {
      Change(*prefs, kind == 1 ? side : prefs->current, kind == 2 ? side : prefs->last);
      break;
    }
  }
  return true;  // A malformed native preference must never reach profile storage.
}
bool RemoveNativeDevToolsPreference(content::WebContents* contents, const std::string& name) {
  return SetNativeDevToolsPreference(contents, name, EncodedSide(0));
}
std::optional<int> NativeDevToolsDockSide(content::WebContents* contents) {
  CheckUI();
  auto* prefs = PreferencesFor(contents);
  return prefs ? std::optional<int>(prefs->current) : std::nullopt;
}
void* NativePageContainer(content::WebContents* contents) {
  CheckUI();
  if (!contents) return nullptr;
  NativeDock::CreateForWebContents(contents);
  return (__bridge void*)NativeDock::FromWebContents(contents)->Container();
}
bool CanDockNativeDevTools(content::WebContents* contents) {
  CheckUI();
  if (!contents) return false;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  return browser && IsNativeHostBrowser(browser) &&
      browser->GetType() == BrowserWindowInterface::TYPE_NORMAL;
}
void UpdateNativeDevTools(content::WebContents* contents) {
  CheckUI();
  if (!CanDockNativeDevTools(contents)) return;
  NativeDock::CreateForWebContents(contents);
  auto* dock = NativeDock::FromWebContents(contents);
  dock->Container();
  dock->Update();
}
void DetachNativeDevTools(content::WebContents* contents) {
  CheckUI();
  if (contents) {
    if (auto* dock = NativeDock::FromWebContents(contents)) dock->Detach();
  }
}
}
