#import "Bridge.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/cef_id_mappers.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_box_layout.h"
#include "include/views/cef_window.h"
#include "include/views/cef_window_delegate.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include <algorithm>
#include <atomic>
#include <climits>

extern "C" void *BZCreateRootView(void *host);
extern "C" void *BZCreateToolbar(void *host);
extern "C" void *BZCreateSidebar(void *host);

static int gArgc;
static char **gArgv;
static std::atomic<bool> gPumpEnabled{false};
static CFRunLoopTimerRef gPumpTimer;
static BOOL gInitialized;
static bool gDoingWork;
static bool gWorkReentered;
static void SchedulePump(int64_t delay_ms);

static void ClearPumpTimer() {
    if (!gPumpTimer) return;
    CFRunLoopTimerInvalidate(gPumpTimer);
    CFRelease(gPumpTimer);
    gPumpTimer = nullptr;
}

static void DoPumpWork() {
    if (!gPumpEnabled.load()) return;
    if (gDoingWork) {
        gWorkReentered = true;
        return;
    }
    gWorkReentered = false;
    gDoingWork = true;
    CefDoMessageLoopWork();
    gDoingWork = false;
    if (gWorkReentered) {
        dispatch_async(dispatch_get_main_queue(), ^{ SchedulePump(0); });
    } else if (!gPumpTimer) {
        // CEF's external-pump sample requires a bounded idle fallback to keep
        // native-loop IPC progressing when no scheduling callback follows work.
        dispatch_async(dispatch_get_main_queue(), ^{ SchedulePump(INT_MAX); });
    }
}

static void SchedulePump(int64_t delay_ms) {
    if (!gPumpEnabled.load()) return;
    if (delay_ms == INT_MAX && gPumpTimer) return;
    ClearPumpTimer();
    if (delay_ms <= 0) {
        DoPumpWork();
        return;
    }
    double delay = static_cast<double>(std::min<int64_t>(delay_ms, 1000 / 30)) / 1000.0;
    gPumpTimer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0, ^(CFRunLoopTimerRef timer) {
            ClearPumpTimer();
            DoPumpWork();
        });
    CFRunLoopAddTimer(CFRunLoopGetMain(), gPumpTimer, kCFRunLoopCommonModes);
}

static void Report(NSString *status) {
    NSLog(@"CEF spike: %@", status);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BoazCEFSpikeStatus"
                                                        object:nil userInfo:@{@"status": status}];
}

static void StopNativeLoop() {
    [NSApp stop:nil];
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
        location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
        subtype:0 data1:0 data2:0];
    [NSApp postEvent:wake atStart:NO];
}

@interface SpikeDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) BZBrowserHost *host;
- (void)createWindow;
- (void)requestQuit;
@end

@interface BZCApplication : NSApplication <CefAppProtocol>
@property(nonatomic, assign) BOOL handlingSendEvent;
@end

@implementation BZCApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event {
    CefScopedSendingEvent scope;
    [super sendEvent:event];
}
- (void)terminate:(id)sender {
    [(SpikeDelegate *)self.delegate requestQuit];
}
@end

class SpikeApp final : public CefApp, public CefBrowserProcessHandler {
public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
    void OnContextInitialized() override {
        CEF_REQUIRE_UI_THREAD();
        dispatch_async(dispatch_get_main_queue(), ^{
            [(SpikeDelegate *)NSApp.delegate createWindow];
        });
    }
    void OnScheduleMessagePumpWork(int64_t delay_ms) override {
        dispatch_async(dispatch_get_main_queue(), ^{
            SchedulePump(delay_ms);
        });
    }
private:
    IMPLEMENT_REFCOUNTING(SpikeApp);
};

@interface BZBrowserHost ()
- (void)didCreate:(CefRefPtr<CefBrowser>)browser;
- (void)didClose;
- (void)startViewsWithURL:(NSString *)url;
- (void)didCreateViewsWindow:(CefRefPtr<CefWindow>)window;
- (void)didDestroyViewsWindow;
- (BOOL)closeViewsWindow;
- (void)setPageTitle:(NSString *)title;
@end

class SpikeClient final : public CefClient,
                          public CefLifeSpanHandler,
                          public CefLoadHandler,
                          public CefDisplayHandler, public CefCommandHandler {
public:
    explicit SpikeClient(BZBrowserHost *host) : host_(host) {}
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefCommandHandler> GetCommandHandler() override { return this; }
    bool OnChromeCommand(CefRefPtr<CefBrowser> browser, int command_id,
                         cef_window_open_disposition_t disposition) override {
        if (command_id != cef_id_for_command_id_name("IDC_EXIT")) return false;
        return [host_ closeViewsWindow];
    }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        [host_ didCreate:browser];
        Report(browser->GetHost()->GetRuntimeStyle() == CEF_RUNTIME_STYLE_ALLOY
            ? @"Browser created · Alloy · sandbox requested"
            : @"Browser created · Chrome · sandbox requested");
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        [host_ didClose];
        Report(@"OnBeforeClose received");
    }
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                       int popup_id, const CefString &target_url,
                       const CefString &target_frame_name, WindowOpenDisposition disposition,
                       bool user_gesture, const CefPopupFeatures &features,
                       CefWindowInfo &window_info, CefRefPtr<CefClient> &client,
                       CefBrowserSettings &settings, CefRefPtr<CefDictionaryValue> &extra_info,
                       bool *no_javascript_access) override {
        Report(@"Popup blocked in this single-page feasibility app");
        return true;
    }
    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int status) override {
        CEF_REQUIRE_UI_THREAD();
        if (frame->IsMain()) Report([NSString stringWithFormat:@"Loaded · HTTP %d", status]);
    }
    void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                     ErrorCode code, const CefString &text, const CefString &url) override {
        CEF_REQUIRE_UI_THREAD();
        if (frame->IsMain()) Report([NSString stringWithFormat:@"Load error %d · %s", code, text.ToString().c_str()]);
    }
    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
        CEF_REQUIRE_UI_THREAD();
        [host_ setPageTitle:[NSString stringWithFormat:@"Boaz CEF Spike — %s", title.ToString().c_str()]];
    }
private:
    __weak BZBrowserHost *host_;
    IMPLEMENT_REFCOUNTING(SpikeClient);
};

class SpikeBrowserViewDelegate final : public CefBrowserViewDelegate {
public:
    ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView> view) override {
        return [NSProcessInfo.processInfo.environment[@"BOAZ_CEF_SPIKE_CHROME_TOOLBAR"] isEqualToString:@"1"]
            ? CEF_CTT_NORMAL : CEF_CTT_NONE;
    }
    void OnWindowChanged(CefRefPtr<CefView> view, bool added) override {
        if (!added || toolbarAdded_ ||
            ![NSProcessInfo.processInfo.environment[@"BOAZ_CEF_SPIKE_CHROME_TOOLBAR"] isEqualToString:@"1"]) return;
        auto browserView = view->AsBrowserView();
        auto window = view->GetWindow();
        auto toolbar = browserView ? browserView->GetChromeToolbar() : nullptr;
        NSLog(@"CEF toolbar diagnostic: OnWindowChanged available=%d window=%d",
              !!toolbar, !!window);
        if (!toolbar || !window) return;
        toolbarAdded_ = true;
        window->AddChildViewAt(toolbar, 0);
        window->GetLayout()->AsBoxLayout()->SetFlexForView(toolbar, 0);
        window->Layout();
        auto bounds = toolbar->GetBounds();
        NSLog(@"CEF toolbar diagnostic: bounds=%d,%d %dx%d", bounds.x, bounds.y,
              bounds.width, bounds.height);
    }
    cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
private:
    bool toolbarAdded_ = false;
    IMPLEMENT_REFCOUNTING(SpikeBrowserViewDelegate);
};

class SpikeWindowDelegate final : public CefWindowDelegate {
public:
    SpikeWindowDelegate(BZBrowserHost *host, CefRefPtr<CefBrowserView> browser)
        : host_(host), browser_(browser) {}
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        CefBoxLayoutSettings layout;
        layout.horizontal = false;
        layout.inside_border_insets = CefInsets(60, 220, 0, 0);
        layout.default_flex = 1;
        window->SetToBoxLayout(layout);
        window->AddChildView(browser_);
        [host_ didCreateViewsWindow:window];
        window->Show();
    }
    void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
        browser_ = nullptr;
        [host_ didDestroyViewsWindow];
    }
    bool CanClose(CefRefPtr<CefWindow> window) override {
        auto browser = browser_ ? browser_->GetBrowser() : nullptr;
        return browser && browser->GetHost()->TryCloseBrowser();
    }
    CefSize GetPreferredSize(CefRefPtr<CefView> view) override { return CefSize(1100, 760); }
    cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
private:
    __weak BZBrowserHost *host_;
    CefRefPtr<CefBrowserView> browser_;
    IMPLEMENT_REFCOUNTING(SpikeWindowDelegate);
};

@implementation BZBrowserHost {
    CefRefPtr<CefBrowser> browser_;
    CefRefPtr<SpikeClient> client_;
    BOOL closeRequested_;
    CefRefPtr<CefWindow> viewsWindow_;
    BOOL viewsMode_;
    __weak NSWindow *presentationWindow_;
}
- (void)startWithURL:(NSString *)url {
    if (client_) return;
    client_ = new SpikeClient(self);
    CefWindowInfo info;
    info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self),
                    CefRect(0, 0, self.bounds.size.width, self.bounds.size.height));
    info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    CefBrowserSettings settings;
    if (!CefBrowserHost::CreateBrowser(info, client_, url.UTF8String, settings, nullptr, nullptr)) {
        client_ = nullptr;
        Report(@"Browser creation failed");
    }
}
- (void)startViewsWithURL:(NSString *)url {
    viewsMode_ = YES;
    client_ = new SpikeClient(self);
    CefBrowserSettings settings;
    auto browser = CefBrowserView::CreateBrowserView(client_, url.UTF8String, settings,
                                                     nullptr, nullptr, new SpikeBrowserViewDelegate);
    CefWindow::CreateTopLevelWindow(new SpikeWindowDelegate(self, browser));
}
- (void)didCreateViewsWindow:(CefRefPtr<CefWindow>)window {
    viewsWindow_ = window;
    NSView *root = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(window->GetWindowHandle());
    presentationWindow_ = root.window;
    NSView *cefContent = presentationWindow_.contentView;
    NSView *container = [[NSView alloc] initWithFrame:cefContent.frame];
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    presentationWindow_.contentView = container;
    cefContent.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:cefContent];
    cefContent.frame = container.bounds;
    NSView *toolbar = (__bridge_transfer NSView *)BZCreateToolbar((__bridge void *)self);
    NSView *sidebar = (__bridge_transfer NSView *)BZCreateSidebar((__bridge void *)self);
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:toolbar positioned:NSWindowAbove relativeTo:nil];
    [container addSubview:sidebar positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [toolbar.topAnchor constraintEqualToAnchor:container.topAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:60],
        [sidebar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:220],
    ]];
}
- (void)didDestroyViewsWindow {
    viewsWindow_ = nullptr;
    if (!browser_) StopNativeLoop();
}
- (BOOL)closeViewsWindow {
    if (!viewsWindow_) return NO;
    viewsWindow_->Close();
    return YES;
}
- (void)didCreate:(CefRefPtr<CefBrowser>)browser {
    browser_ = browser;
    if (!viewsMode_) {
        NSView *view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
        view.frame = self.bounds;
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    if (closeRequested_) browser_->GetHost()->CloseBrowser(false);
}
- (void)setPageTitle:(NSString *)title {
    (viewsMode_ ? presentationWindow_ : self.window).title = title;
}
- (void)navigate:(NSString *)url {
    if (browser_) browser_->GetMainFrame()->LoadURL(url.UTF8String);
}
- (void)goBack { if (browser_) browser_->GoBack(); }
- (void)reload { if (browser_) browser_->Reload(); }
- (BOOL)tryClose {
    if (client_ && !browser_) {
        closeRequested_ = YES;
        return NO;
    }
    return !browser_ || browser_->GetHost()->TryCloseBrowser();
}
- (void)removeBrowserView {
    if (browser_) {
        NSView *view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser_->GetHost()->GetWindowHandle());
        [view removeFromSuperview];
    } else if (!client_) {
        StopNativeLoop();
    }
}
- (void)didClose {
    browser_ = nullptr;
    client_ = nullptr;
    if (!viewsMode_ || !viewsWindow_) StopNativeLoop();
}
@end

@implementation SpikeDelegate
- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    CefSettings settings;
    settings.external_message_pump = true;
    settings.log_severity = LOGSEVERITY_WARNING;
    NSString *profile = NSProcessInfo.processInfo.environment[@"BOAZ_CEF_SPIKE_PROFILE"] ?: @"isolated-keychain-v1";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
    if (profile.length < 1 || profile.length > 48 ||
        [profile rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        Report(@"Invalid spike profile: expected 1–48 lowercase ASCII letters, digits or hyphens");
        dispatch_async(dispatch_get_main_queue(), ^{ StopNativeLoop(); });
        return;
    }
    BOOL defaultProfile = [profile isEqualToString:@"isolated-keychain-v1"];
    NSString *service = defaultProfile ? @"com.chenkahana.boaz.cef-spike Safe Storage"
        : [NSString stringWithFormat:@"com.chenkahana.boaz.cef-spike.%@ Safe Storage", profile];
    NSString *account = defaultProfile ? @"BoazCEFSpike"
        : [@"BoazCEFSpike-" stringByAppendingString:profile];
    CefString(&settings.keychain_service_name) = service.UTF8String;
    CefString(&settings.keychain_account_name) = account.UTF8String;
    NSString *cache = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.chenkahana.boaz.cef-spike"]
        stringByAppendingPathComponent:profile];
    CefString(&settings.root_cache_path) = cache.UTF8String;
    CefString(&settings.cache_path) = [cache stringByAppendingPathComponent:@"Default"].UTF8String;
    CefString(&settings.log_file) = [cache stringByAppendingPathComponent:@"cef.log"].UTF8String;
    gPumpEnabled.store(true);
    gInitialized = CefInitialize(CefMainArgs(gArgc, gArgv), settings, new SpikeApp, nullptr);
    if (!gInitialized) {
        gPumpEnabled.store(false);
        Report(@"CEF initialization failed");
        dispatch_async(dispatch_get_main_queue(), ^{ StopNativeLoop(); });
    }
}
- (void)createWindow {
    if (self.window || !gInitialized) return;
    self.host = [[BZBrowserHost alloc] initWithFrame:NSMakeRect(0, 0, 1000, 650)];
    NSString *startURL = NSProcessInfo.processInfo.environment[@"BOAZ_CEF_SPIKE_URL"] ?: @"https://example.com";
    if ([NSProcessInfo.processInfo.environment[@"BOAZ_CEF_SPIKE_HOST"] isEqualToString:@"views"]) {
        [self.host startViewsWithURL:startURL];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 760)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    self.window.title = @"Boaz CEF Spike";
    self.window.contentView = (__bridge_transfer NSView *)BZCreateRootView((__bridge void *)self.host);
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.host startWithURL:startURL];
}
- (BOOL)windowShouldClose:(NSWindow *)sender { return [self.host tryClose]; }
- (void)windowWillClose:(NSNotification *)notification {
    [self.host removeBrowserView];
    self.window.contentView = nil;
}
- (void)requestQuit {
    if (self.window) [self.window performClose:nil];
    else if ([self.host closeViewsWindow]) return;
    else StopNativeLoop();
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }
@end

int main(int argc, char *argv[]) {
    gArgc = argc;
    gArgv = argv;
    CefScopedLibraryLoader loader;
    if (!loader.LoadInMain()) return 1;
    @autoreleasepool {
        [BZCApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        SpikeDelegate *delegate = [SpikeDelegate new];
        NSApp.delegate = delegate;
        NSMenu *menu = [NSMenu new];
        NSMenuItem *appItem = [NSMenuItem new];
        [menu addItem:appItem];
        appItem.submenu = [NSMenu new];
        [appItem.submenu addItemWithTitle:@"Quit Boaz CEF Spike" action:@selector(terminate:) keyEquivalent:@"q"];
        NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
        edit.submenu = [[NSMenu alloc] initWithTitle:@"Edit"];
        [edit.submenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
        [edit.submenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
        [edit.submenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
        [edit.submenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
        [menu addItem:edit];
        NSApp.mainMenu = menu;
        [NSApp run];
        gPumpEnabled.store(false);
        ClearPumpTimer();
        if (gInitialized) {
            // Match CEF's external-pump shutdown drain before CefShutdown.
            for (int i = 0; i < 10; ++i) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, true);
                CefDoMessageLoopWork();
                [NSThread sleepForTimeInterval:0.05];
            }
            CefShutdown();
            Report(@"CefShutdown complete");
        }
        NSApp.delegate = nil;
    }
    return gInitialized ? 0 : 1;
}
