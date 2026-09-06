#pragma once

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RYGRuntimeValueOverridesKey;

typedef NS_ENUM(NSInteger, RYGRuntimeValueArgumentKind) {
    RYGRuntimeValueArgumentNone = 0,
    RYGRuntimeValueArgumentObject,
    RYGRuntimeValueArgumentInteger,
    RYGRuntimeValueArgumentUnsupported = NSIntegerMax,
};

NSString *RYGRuntimeValueUID(NSString *className, NSString *selectorName, BOOL classMethod);
NSString *RYGRuntimeValueNormalizedType(NSString *typeCode);
NSString * _Nullable RYGRuntimeValueTypeName(NSString *typeCode);
BOOL RYGRuntimeValueTypeIsSupported(NSString *typeCode);
BOOL RYGRuntimeValueTypeIsBoolean(NSString *typeCode);
BOOL RYGRuntimeValueTypeIsSignedInteger(NSString *typeCode);
BOOL RYGRuntimeValueTypeIsUnsignedInteger(NSString *typeCode);
BOOL RYGRuntimeValueTypeIsFloatingPoint(NSString *typeCode);
BOOL RYGRuntimeValueTypeIsObject(NSString *typeCode);
BOOL RYGRuntimeValueSelectorIsSafeGetter(NSString *selectorName);

/// Classifies the exact Objective-C ABI supported by the runtime browser.
/// Zero-argument methods may return any supported scalar/Foundation object.
/// One-argument methods are intentionally limited to BOOL with an object or
/// q/Q register argument. The latter is the Instagram extension over the WAT
/// dogfood2 zero-argument getter model.
BOOL RYGRuntimeValueClassifyMethod(Method method,
                                   NSString * _Nullable * _Nullable typeCode,
                                   RYGRuntimeValueArgumentKind * _Nullable argumentKind);

BOOL RYGRuntimeValueHasOverride(NSString *className, NSString *selectorName, BOOL classMethod);
id _Nullable RYGRuntimeValueOverride(NSString *className, NSString *selectorName, BOOL classMethod);
void RYGRuntimeValueSetOverride(NSString *className, NSString *selectorName, BOOL classMethod,
                                NSString *typeCode, id _Nullable value);
void RYGRuntimeValueClearOverride(NSString *className, NSString *selectorName, BOOL classMethod);
NSArray<NSDictionary<NSString *, id> *> *RYGRuntimeValueAllOverrideSpecs(void);

BOOL RYGRuntimeValueInstallHook(NSString *className, NSString *selectorName, BOOL classMethod,
                                NSString *typeCode);
BOOL RYGRuntimeValueHookIsInstalled(NSString *className, NSString *selectorName, BOOL classMethod);
NSUInteger RYGRuntimeValueReinstallPersistedHooks(void);

/// For BOOL(id)/BOOL(q|Q), the browser never manufactures an argument. A
/// pass-through hook observes the value when Instagram naturally calls it and
/// applies an override, if present. For zero-argument getters this reads the
/// getter directly using its exact return ABI.
NSString *RYGRuntimeValueRead(NSString *className, NSString *selectorName, BOOL classMethod,
                              id _Nullable instance, id _Nullable * _Nullable rawValue);
id _Nullable RYGRuntimeValueObservedValue(NSString *className, NSString *selectorName, BOOL classMethod);

/// Current defining-image UUID for provenance/build-aware persistence.
NSString * _Nullable RYGRuntimeValueImageUUIDForClassName(NSString *className);

NS_ASSUME_NONNULL_END
