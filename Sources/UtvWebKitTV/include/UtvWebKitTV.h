#import <Foundation/Foundation.h>

@class WKWebViewConfiguration;

NS_ASSUME_NONNULL_BEGIN

/// Loads the WebKit framework. Must be called once at app launch before any WKWebView usage.
/// On macOS this is a no-op (WebKit is loaded normally). On tvOS this dlopen()s the
/// private framework. Returns YES if WebKit is available afterwards.
BOOL UtvWebKitBootstrap(void);

/// Health check: WKWebView class plus the selectors we depend on all resolve.
/// Use after UtvWebKitBootstrap() to surface a clean error before any view is created.
BOOL UtvWebKitIsAvailable(void);

/// Enables private MSE / managed-MSE / media-grants prefs needed for YouTube playback on tvOS.
/// On macOS this is a no-op (default prefs already work).
void UtvWebKitEnableYouTubeMediaPrefs(WKWebViewConfiguration *configuration);

NS_ASSUME_NONNULL_END
