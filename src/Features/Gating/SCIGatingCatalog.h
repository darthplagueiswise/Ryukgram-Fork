#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIGatingRuntimeScope) {
    SCIGatingRuntimeScopeInstagramMain = 0,
    SCIGatingRuntimeScopeFBSharedFramework = 1,
};

// Runtime catalog of Instagram's feature-gating accessors.
//
// Meta ships hundreds of "gating" classes (IGPermissionsGating, IGUpperFunnelGating,
// *ExperimentHelper, *Config, …). Each exposes no-argument BOOL getters such as
// -isMessagingControlsEnabled whose bodies read a shared MobileConfig context and
// return the live feature value. This is the closest IG analogue to WhatsApp's
// WAABProperties: a browsable, named list of every feature flag accessor.
//
// This class enumerates those accessors purely from the ObjC runtime (always matches
// the installed binary — no shipped resource that can go stale) and can evaluate a
// single getter on demand, guarded so a misbehaving getter is blacklisted rather than
// crashing every launch.
@interface SCIGatingCatalog : NSObject

// Array of @{ @"class": demangled-ish name, @"raw": raw objc name,
//              @"getters": @[@{@"selector": sel, @"classMethod": @(BOOL)}, …] }.
// Sorted by display name. Cached after first build.
+ (NSArray<NSDictionary *> *)catalog;
+ (NSArray<NSDictionary *> *)catalogForScope:(SCIGatingRuntimeScope)scope;
+ (NSString *)displayNameForScope:(SCIGatingRuntimeScope)scope;

// Total counts for headers.
+ (NSUInteger)classCount;
+ (NSUInteger)getterCount;

// On-demand, crash-guarded evaluation of one getter. Returns @(BOOL) or nil if the
// getter is blacklisted / unavailable / could not be evaluated safely.
+ (nullable NSNumber *)evaluateClass:(NSString *)rawClassName selector:(NSString *)selectorName;
+ (nullable NSNumber *)evaluateClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod;

// Whether a correctly typed live receiver is currently available for safe evaluation.
+ (BOOL)hasLiveReceiverForClass:(NSString *)rawClassName;

// Stable identifier used to bind/override a flag (raw class + selector).
+ (NSString *)canonicalNameForClass:(NSString *)rawClassName selector:(NSString *)selectorName;

// Direct getter hooks used by Feature Gatings. These replace the BOOL accessor
// itself and fall back to the original IMP when no override is stored.
+ (void)installPersistedDirectOverrideHooks;
+ (nullable NSNumber *)directOverrideStateForName:(NSString *)name;
+ (void)setDirectBoolOverride:(BOOL)value class:(NSString *)rawClassName selector:(NSString *)selectorName;
+ (void)clearDirectOverrideForName:(NSString *)name;
+ (void)clearDirectOverrides;

// Generic runtime BOOL hooks used by FLEX/Ryuk runtime tooling. Supports no-argument
// instance and class methods returning BOOL/_Bool. These APIs are intentionally
// class+selector based so a debugger UI can discover a selector in FLEX and bind it
// directly without needing it to be present in the gating catalog.
+ (BOOL)canRuntimeHookBoolMethodForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod;
+ (nullable NSNumber *)runtimeBoolOverrideStateForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod;
+ (void)setRuntimeBoolOverride:(BOOL)value class:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod;
+ (void)clearRuntimeBoolOverrideForClass:(NSString *)rawClassName selector:(NSString *)selectorName classMethod:(BOOL)isClassMethod;

// Whether a getter is currently blacklisted (crashed previously, or user disabled).
+ (BOOL)isBlacklistedClass:(NSString *)rawClassName selector:(NSString *)selectorName;
+ (void)clearBlacklist;

// Must be called early (e.g. tweak %ctor). If a previous evaluation armed the guard and
// the app then crashed, the offending getter is moved to the blacklist here.
+ (void)reconcileCrashGuardOnLaunch;

@end

NS_ASSUME_NONNULL_END
