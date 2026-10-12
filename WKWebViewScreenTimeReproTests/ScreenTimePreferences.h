#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads WebKit's internal ScreenTimeEnabled feature flag.
BOOL ReproReadScreenTimeEnabled(WKPreferences *preferences, BOOL *enabled, NSError **error);

/// Sets and reads back WebKit's internal ScreenTimeEnabled feature flag.
BOOL ReproSetScreenTimeEnabled(WKPreferences *preferences, BOOL enabled, NSError **error);

NS_ASSUME_NONNULL_END
