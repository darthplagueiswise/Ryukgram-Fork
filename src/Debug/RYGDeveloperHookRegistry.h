#import <Foundation/Foundation.h>

@class RYGRuntimeBoolMethod;

NS_ASSUME_NONNULL_BEGIN

/// Developer-only BOOL override registry.
///
/// This registry is intentionally independent from Runtime Browser discovery/UI.
/// It validates the live Objective-C Method and type encoding before installing
/// an IMP and persists overrides against the owning Mach-O LC_UUID.
@interface RYGDeveloperHookRegistry : NSObject

+ (instancetype)sharedRegistry;

/// Returns the persisted override for the exact live ABI identity, or nil when
/// the method is using its native implementation.
- (nullable NSNumber *)overrideValueForMethod:(RYGRuntimeBoolMethod *)method;

/// Applies/persists an exact Developer override. Passing nil returns the method
/// to native behaviour while leaving the installed forwarding shim in place.
/// Returns NO when the class/selector/type encoding is no longer an exact match.
- (BOOL)setOverrideValue:(nullable NSNumber *)value
               forMethod:(RYGRuntimeBoolMethod *)method
                   error:(NSError * _Nullable * _Nullable)error;

/// Reinstalls forwarding shims for persisted identities whose image is loaded.
/// Safe to call repeatedly; no Objective-C runtime enumeration is performed.
- (void)restorePersistedOverridesForLoadedImages;

/// Schedules a cheap post-activation restore. No class walk is done here.
- (void)startIfNeeded;

@end

NS_ASSUME_NONNULL_END
