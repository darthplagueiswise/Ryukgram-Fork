#import "SCIExpMobileConfigDebug.h"

static __weak id gSCILastMCContext = nil;
static NSString *gSCILastMCContextSource = nil;
static NSUInteger gSCIContextHitCount = 0;

static dispatch_queue_t SCIExpMCDebugQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("sci.expflags.mc.debug", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

@implementation SCIExpMobileConfigDebug

+ (void)noteContext:(id)context source:(NSString *)source {
    if (!context) return;
    dispatch_async(SCIExpMCDebugQueue(), ^{
        gSCILastMCContext = context;
        gSCILastMCContextSource = [source copy] ?: @"unknown";
        gSCIContextHitCount++;
    });
}

+ (NSString *)debugState {
    __block id ctx = nil;
    __block NSString *src = nil;
    __block NSUInteger hits = 0;
    dispatch_sync(SCIExpMCDebugQueue(), ^{
        ctx = gSCILastMCContext;
        src = gSCILastMCContextSource;
        hits = gSCIContextHitCount;
    });
    return [NSString stringWithFormat:@"context=%@ source=%@ hits=%lu",
            ctx ? NSStringFromClass([ctx class]) : @"nil",
            src ?: @"nil",
            (unsigned long)hits];
}

+ (NSString *)runDebugDumps {
    NSString *state = [self debugState];
    NSString *message = [NSString stringWithFormat:@"MobileConfig debug context tracker is active. %@", state];
    NSLog(@"[RyukGram][MCDebug] %@", message);
    return message;
}

@end
