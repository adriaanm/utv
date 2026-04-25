#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>

@class WKWebView;
@class WKWebViewConfiguration;
@class WKUserScript;
@class WKWebsiteDataStore;
@class WKUserContentController;

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

/// Construct a WKUserScript via the objc runtime (NSClassFromString) so the binary
/// does not embed an _OBJC_CLASS_$_WKUserScript flat-namespace reference. Returns
/// nil on platforms where WKUserScript is unavailable. injectionTime is a raw
/// WKUserScriptInjectionTime value (0 = atDocumentStart, 1 = atDocumentEnd).
WKUserScript * _Nullable UtvWebKitMakeUserScript(NSString *source,
                                                  NSInteger injectionTime,
                                                  BOOL mainFrameOnly);

/// Construct a WKWebViewConfiguration via NSClassFromString. See above for why.
WKWebViewConfiguration * _Nullable UtvWebKitMakeConfiguration(void);

/// Construct a WKWebView via NSClassFromString.
WKWebView * _Nullable UtvWebKitMakeWebView(CGRect frame, WKWebViewConfiguration *configuration);

/// Look up `WKWebsiteDataStore.defaultDataStore` via NSClassFromString.
WKWebsiteDataStore * _Nullable UtvWebKitDefaultDataStore(void);

/// Look up `WKWebsiteDataStore.allWebsiteDataTypes` via NSClassFromString.
NSSet<NSString *> * _Nullable UtvWebKitAllWebsiteDataTypes(void);

/// Compile a JSON content blocker rule list and add it to the given user content controller.
/// Routes through `WKContentRuleListStore` resolved via NSClassFromString so we don't pull
/// `_OBJC_CLASS_$_WKContentRuleListStore` into the binary's flat-namespace bind list (which
/// dyld kills the process over on tvOS — see UtvWebKitBootstrap caveat).
/// `completion` is invoked on the main thread with nil on success, or an NSError describing
/// either an SDK-availability miss or a compile failure.
void UtvWebKitCompileContentRuleList(WKUserContentController *controller,
                                     NSString *identifier,
                                     NSString *encodedJSON,
                                     void (^completion)(NSError * _Nullable error));

NS_ASSUME_NONNULL_END
