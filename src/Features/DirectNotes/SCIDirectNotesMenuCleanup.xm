#import <Foundation/Foundation.h>

// beta2 stability fix:
// This file used to install a second cleanup hook for SCITweakSettings +sections.
// The same responsibility is already owned by:
//   src/Settings/SCIDirectNotesDogfoodingMenuCleanup.xm
// Keeping two startup hooks on the same settings method is unnecessary and makes
// menu behavior harder to reason about. Leave this compilation unit inert.

__attribute__((constructor(65535)))
static void RYDNDirectNotesMenuCleanupInit(void) {
    @autoreleasepool {
        NSLog(@"[RyukGram][DirectNotesMenuCleanup] inert duplicate cleanup; Settings owner remains active");
    }
}
