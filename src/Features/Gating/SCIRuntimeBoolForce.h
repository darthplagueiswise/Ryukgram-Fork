#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Standalone, launch-time forcing of no-argument BOOL getters.
//
// This is intentionally decoupled from SCIGatingCatalog / the Feature Gatings
// browser. Features like Liquid Glass and Story Tray must take effect during the
// launch path (their getters are consumed while IG builds its UI), so they need
// their override installed at %ctor — long before the gating screen is ever
// opened. The gating browser keeps its own per-getter override mechanism for
// interactive runtime poking; this helper is the build-it-in-stone path.
//
// Safety contract:
//   * Only 0-argument BOOL/_Bool getters are forced (validated before install).
//   * The installed implementation returns a captured constant and performs NO
//     Objective-C work, so it can never recurse back through MobileConfig.
//   * Idempotent: forcing the same class+selector twice is a no-op.
//   * Never calls the original IMP, so there is no shared-orig hazard.
@interface SCIRuntimeBoolForce : NSObject

// Forces -[cls sel] (or +[cls sel] when classMethod is YES) to always return
// `value`. Returns YES if the override was installed (or already present),
// NO if the class/selector is missing or is not a 0-arg BOOL getter.
+ (BOOL)forceClassNamed:(NSString *)className
               selector:(NSString *)selectorName
            classMethod:(BOOL)classMethod
                  value:(BOOL)value;

// Convenience: force several instance BOOL getters on one class to the same value.
+ (void)forceInstanceSelectors:(NSArray<NSString *> *)selectors
                   onClassNamed:(NSString *)className
                          value:(BOOL)value;

// Convenience: force several class BOOL getters on one class to the same value.
+ (void)forceClassSelectors:(NSArray<NSString *> *)selectors
                onClassNamed:(NSString *)className
                       value:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
