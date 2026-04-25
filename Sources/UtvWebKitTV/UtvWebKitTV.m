#import "UtvWebKitTV.h"

#if TARGET_OS_TV
#import <dlfcn.h>
#import "WebKit/WKWebView.h"
#import "WebKit/WKWebViewConfiguration.h"
#import "WebKit/WKPreferences.h"

@interface WKPreferences (UtvPrivate)
- (void)_setMediaSourceEnabled:(BOOL)enabled;
- (void)_setManagedMediaSourceEnabled:(BOOL)enabled;
- (void)_setMediaCapabilityGrantsEnabled:(BOOL)enabled;
@end
#else
#import <WebKit/WebKit.h>
#endif

BOOL UtvWebKitBootstrap(void) {
#if TARGET_OS_TV
    if (NSClassFromString(@"WKWebView") != Nil) return YES;

    static const char * const candidates[] = {
        "/System/Library/Frameworks/WebKit.framework/WebKit",
        "/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
        "/System/Library/StagedFrameworks/Safari/WebKit.framework/WebKit",
    };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        if (dlopen(candidates[i], RTLD_NOW | RTLD_GLOBAL) != NULL &&
            NSClassFromString(@"WKWebView") != Nil) {
            return YES;
        }
    }
    return NO;
#else
    return NSClassFromString(@"WKWebView") != Nil;
#endif
}

BOOL UtvWebKitIsAvailable(void) {
    Class cls = NSClassFromString(@"WKWebView");
    if (cls == Nil) return NO;
    if (![cls instancesRespondToSelector:@selector(loadRequest:)]) return NO;
    if (![cls instancesRespondToSelector:@selector(evaluateJavaScript:completionHandler:)]) return NO;
    return YES;
}

void UtvWebKitEnableYouTubeMediaPrefs(WKWebViewConfiguration *configuration) {
#if TARGET_OS_TV
    WKPreferences *prefs = configuration.preferences;
    if ([prefs respondsToSelector:@selector(_setMediaSourceEnabled:)]) {
        [prefs _setMediaSourceEnabled:YES];
    }
    if ([prefs respondsToSelector:@selector(_setManagedMediaSourceEnabled:)]) {
        [prefs _setManagedMediaSourceEnabled:YES];
    }
    if ([prefs respondsToSelector:@selector(_setMediaCapabilityGrantsEnabled:)]) {
        [prefs _setMediaCapabilityGrantsEnabled:YES];
    }
#else
    (void)configuration;
#endif
}
