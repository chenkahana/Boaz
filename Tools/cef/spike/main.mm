#import "Bridge.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include <algorithm>
#include <atomic>
#include <climits>

extern "C" void *BZCreateRootView(void *host);

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
@end

class SpikeClient final : public CefClient,
                          public CefLifeSpanHandler,
                          public CefLoadHandler,
                          public CefDisplayHandler {
public:
    explicit SpikeClient(BZBrowserHost *host) : host_(host) {}
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        [host_ didCreate:browser];
        Report(browser->GetHost()->GetRuntimeStyle() == CEF_RUNTIME_STYLE_ALLOY
            ? @"Browser created · Alloy · sandbox requested"
            : @"Browser created · unexpected runtime style");
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        [host_ didClose];
        Report(@"OnBeforeClose received");
        StopNativeLoop();
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
        host_.window.title = [NSString stringWithFormat:@"Boaz CEF Spike — %s", title.ToString().c_str()];
    }
private:
    __weak BZBrowserHost *host_;
    IMPLEMENT_REFCOUNTING(SpikeClient);
};

@implementation BZBrowserHost {
    CefRefPtr<CefBrowser> browser_;
    CefRefPtr<SpikeClient> client_;
    BOOL closeRequested_;
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
- (void)didCreate:(CefRefPtr<CefBrowser>)browser {
    browser_ = browser;
    NSView *view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    view.frame = self.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (closeRequested_) browser_->GetHost()->CloseBrowser(false);
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
}
@end

@implementation SpikeDelegate
- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    CefSettings settings;
    settings.external_message_pump = true;
    settings.log_severity = LOGSEVERITY_WARNING;
    CefString(&settings.keychain_service_name) = "com.chenkahana.boaz.cef-spike Safe Storage";
    CefString(&settings.keychain_account_name) = "BoazCEFSpike";
    NSString *cache = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.chenkahana.boaz.cef-spike/isolated-keychain-v1"];
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
    NSString *startURL = NSProcessInfo.processInfo.environment[@"BOAZ_CEF_SPIKE_URL"] ?: @"https://example.com";
    [self.host startWithURL:startURL];
}
- (BOOL)windowShouldClose:(NSWindow *)sender { return [self.host tryClose]; }
- (void)windowWillClose:(NSNotification *)notification {
    [self.host removeBrowserView];
    self.window.contentView = nil;
}
- (void)requestQuit {
    if (self.window) [self.window performClose:nil];
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
