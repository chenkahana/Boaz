#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BZBrowserHost : NSView
- (void)startWithURL:(NSString *)url;
- (void)navigate:(NSString *)url;
- (void)goBack;
- (void)reload;
- (BOOL)tryClose;
- (void)removeBrowserView;
@end

NS_ASSUME_NONNULL_END
