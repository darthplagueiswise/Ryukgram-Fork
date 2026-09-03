#import <Foundation/Foundation.h>

// Shared file logger for RyukGram's own activity — one file across the main app
// and any injected appex. Self-contained (Foundation only) so it also compiles
// into zxPluginsInject.dylib. Process-safe via flock + O_APPEND.
//
// Two gates:
//   • RYG_FILELOG (compile-time) — pass -DRYG_FILELOG=0 for production; the
//     whole thing, the NSLog tee and the Settings row compile out to no-ops.
//   • RYGFileLogSetEnabled (runtime) — OFF by default, marker-file backed so an
//     appex honors the same switch.
//
// Captures NSLog(@"[RyukGram]...") via a prefix-filtered tee, plus explicit
// RYGFLog(category, fmt, ...) lines.

#ifndef RYG_FILELOG
#define RYG_FILELOG 1
#endif

NS_ASSUME_NONNULL_BEGIN

#if RYG_FILELOG

#ifdef __cplusplus
extern "C" {
#endif

void RYGFileLogWrite(NSString * _Nullable category, NSString *message);
NSString * _Nullable RYGFileLogPath(void);
NSURL * _Nullable RYGFileLogURL(void);
void RYGFileLogClear(void);
NSString * _Nullable RYGFileLogExportToDocuments(void);

// Runtime master switch (marker-file backed, cross-process). Default OFF.
void RYGFileLogSetEnabled(BOOL enabled);
BOOL RYGFileLogIsEnabled(void);

#ifdef __cplusplus
}
#endif

#define RYGFLog(cat, fmt, ...) RYGFileLogWrite((cat), [NSString stringWithFormat:(fmt), ##__VA_ARGS__])

#else // RYG_FILELOG == 0 — compiled out entirely.

NS_INLINE void RYGFileLogWrite(NSString * _Nullable category, NSString *message) { (void)category; (void)message; }
NS_INLINE NSString * _Nullable RYGFileLogPath(void) { return nil; }
NS_INLINE NSURL * _Nullable RYGFileLogURL(void) { return nil; }
NS_INLINE void RYGFileLogClear(void) {}
NS_INLINE NSString * _Nullable RYGFileLogExportToDocuments(void) { return nil; }
NS_INLINE void RYGFileLogSetEnabled(BOOL enabled) { (void)enabled; }
NS_INLINE BOOL RYGFileLogIsEnabled(void) { return NO; }

#define RYGFLog(cat, fmt, ...) do {} while (0)

#endif

NS_ASSUME_NONNULL_END
