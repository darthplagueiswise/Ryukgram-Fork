#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Set a boolean MobileConfig override on a specifier.
/// @param specifier The uint64 MC specifier (e.g. 0x0041094200003249)
/// @param value     YES = force on, NO = force off
/// @param persist   YES = write to disk (survives restart), NO = memory only
/// @return YES if at least one code path succeeded
BOOL SCIMCSetBoolOverride(uint64_t specifier, BOOL value, BOOL persist);

/// Remove a boolean override for a specifier.
BOOL SCIMCRemoveOverride(uint64_t specifier, BOOL persist);

/// Resolve a specifier to its human-readable parameter name.
/// Returns nil if configs haven't been loaded yet or specifier is unknown.
NSString * _Nullable SCIMCParamName(uint64_t specifier);

/// Get the default bool value for a specifier from the loaded config.
BOOL SCIMCBoolDefault(uint64_t specifier);

/// Set multiple overrides. Keys are "0x..." hex strings, values are @YES/@NO.
BOOL SCIMCSetBoolOverrides(NSDictionary<NSString *, NSNumber *> * _Nonnull specifierToValue, BOOL persist);

/// Returns all known specifiers from binary analysis.
NSDictionary<NSString *, NSString *> * _Nonnull SCIMCKnownSpecifiers(void);

/// Returns diagnostic info about function resolution and override table state.
NSDictionary<NSString *, id> * _Nonnull SCIMCOverrideDiagnostics(void);

#ifdef __cplusplus
}
#endif
