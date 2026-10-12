#import "ScreenTimePreferences.h"

// These SPI declarations match WebKit's WKPreferencesPrivate.h and _WKFeature.h.
@interface NSObject (ReproWebKitFeature)
@property (nonatomic, readonly, copy) NSString *key;
@end

@interface WKPreferences (ReproScreenTime)
+ (NSArray<NSObject *> *)_features;
- (BOOL)_isEnabledForFeature:(NSObject *)feature;
- (void)_setEnabled:(BOOL)enabled forFeature:(NSObject *)feature;
@end

static BOOL Fail(NSError **error, NSString *message)
{
    if (error) {
        *error = [NSError errorWithDomain:@"ScreenTimeRepro" code:1
                                userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

static NSObject *ScreenTimeFeature(WKPreferences *preferences, NSError **error)
{
    if (![WKPreferences respondsToSelector:@selector(_features)]
        || ![preferences respondsToSelector:@selector(_isEnabledForFeature:)]
        || ![preferences respondsToSelector:@selector(_setEnabled:forFeature:)]) {
        Fail(error, @"This WebKit build does not expose the required WKPreferences SPI.");
        return nil;
    }
    for (NSObject *feature in [WKPreferences _features]) {
        if ([feature respondsToSelector:@selector(key)]
            && [feature.key isEqualToString:@"ScreenTimeEnabled"]) {
            return feature;
        }
    }
    Fail(error, @"ScreenTimeEnabled is absent from this WebKit build.");
    return nil;
}

BOOL ReproReadScreenTimeEnabled(WKPreferences *preferences, BOOL *enabled, NSError **error)
{
    NSObject *feature = ScreenTimeFeature(preferences, error);
    if (!feature)
        return NO;
    *enabled = [preferences _isEnabledForFeature:feature];
    return YES;
}

BOOL ReproSetScreenTimeEnabled(WKPreferences *preferences, BOOL enabled, NSError **error)
{
    NSObject *feature = ScreenTimeFeature(preferences, error);
    if (!feature)
        return NO;
    [preferences _setEnabled:enabled forFeature:feature];
    if ([preferences _isEnabledForFeature:feature] != enabled)
        return Fail(error, @"ScreenTimeEnabled did not match the requested value.");
    return YES;
}
