#import <Foundation/Foundation.h>

// beta2 stability fix:
// The previous implementation ran from a constructor, scanned the Objective-C
// runtime class list, installed callback hooks immediately, then repeated the
// scan after 1s and 3s. That is unsafe during Instagram cold start/login and
// matches the observed delayed crash when the user has not enabled anything.
//
// DirectNotes dogfooding persistence must be rebuilt as an explicit user action
// from the native dogfooding menu. For beta2 launch stability, this file is a
// no-op while preserving the compilation unit.

#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) void SCIInstallDirectNotesDogfoodingHooksWhenRequested(void) {
    NSLog(@"[RyukGram][DirectNotesDogfood] startup hooks disabled; manual install not implemented in beta2 stability build");
}
#ifdef __cplusplus
}
#endif

__attribute__((constructor))
static void RYDNDirectNotesDogfoodingInit(void) {
    @autoreleasepool {
        NSLog(@"[RyukGram][DirectNotesDogfood] startup inert; no class scan, no hooks, no timers");
    }
}
