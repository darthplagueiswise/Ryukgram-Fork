#import "RYGCallSelfVideoTap.h"

static volatile int gGroupMode = 0;
static char gSelfKey;   // stable tile key for your camera

@implementation RYGCallSelfVideoTap

+ (void)setGroupMode:(BOOL)on { __atomic_store_n(&gGroupMode, on ? 1 : 0, __ATOMIC_SEQ_CST); }
+ (BOOL)groupModeActive { return __atomic_load_n(&gGroupMode, __ATOMIC_RELAXED) != 0; }
+ (void *)selfTileKey { return &gSelfKey; }

@end
