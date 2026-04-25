#import "UtvWebKitTV.h"

#if TARGET_OS_TV
#import <dlfcn.h>
#import "WebKit/WKWebView.h"
#import "WebKit/WKWebViewConfiguration.h"
#import "WebKit/WKPreferences.h"
#import "WebKit/WKUserScript.h"
#import "WebKit/WKWebsiteDataStore.h"

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
    static BOOL bootstrapped = NO;
    if (bootstrapped) return YES;

    BOOL ok = NSClassFromString(@"WKWebView") != Nil;
    if (!ok) {
        static const char * const candidates[] = {
            "/System/Library/Frameworks/WebKit.framework/WebKit",
            "/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
            "/System/Library/StagedFrameworks/Safari/WebKit.framework/WebKit",
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            if (dlopen(candidates[i], RTLD_NOW | RTLD_GLOBAL) != NULL &&
                NSClassFromString(@"WKWebView") != Nil) {
                ok = YES;
                break;
            }
        }
    }
    bootstrapped = ok;
    return ok;
#else
    return NSClassFromString(@"WKWebView") != Nil;
#endif
}

WKUserScript * _Nullable UtvWebKitMakeUserScript(NSString *source,
                                                  NSInteger injectionTime,
                                                  BOOL mainFrameOnly) {
    Class cls = NSClassFromString(@"WKUserScript");
    if (cls == Nil) return nil;
    // Use objc runtime to allocate so Swift/Obj-C don't emit _OBJC_CLASS_$_WKUserScript
    // class refs that dyld kills the process over on tvOS.
    id instance = [cls alloc];
    return [instance initWithSource:source
                       injectionTime:(WKUserScriptInjectionTime)injectionTime
                    forMainFrameOnly:mainFrameOnly];
}

WKWebViewConfiguration * _Nullable UtvWebKitMakeConfiguration(void) {
    Class cls = NSClassFromString(@"WKWebViewConfiguration");
    if (cls == Nil) return nil;
    return [[cls alloc] init];
}

WKWebView * _Nullable UtvWebKitMakeWebView(CGRect frame, WKWebViewConfiguration *configuration) {
    Class cls = NSClassFromString(@"WKWebView");
    if (cls == Nil) return nil;
    id instance = [cls alloc];
    return [instance initWithFrame:frame configuration:configuration];
}

WKWebsiteDataStore * _Nullable UtvWebKitDefaultDataStore(void) {
    Class cls = NSClassFromString(@"WKWebsiteDataStore");
    if (cls == Nil) return nil;
    return [cls defaultDataStore];
}

NSSet<NSString *> * _Nullable UtvWebKitAllWebsiteDataTypes(void) {
    Class cls = NSClassFromString(@"WKWebsiteDataStore");
    if (cls == Nil) return nil;
    return [cls allWebsiteDataTypes];
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
