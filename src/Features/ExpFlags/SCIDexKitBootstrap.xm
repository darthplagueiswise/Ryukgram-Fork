#import "SCIDexKitStore.h"
#import "SCIDexKitBoolRouter.h"
#import "../../Core/SCIBoolOverrideResolver.h"
#import <Foundation/Foundation.h>

%ctor {
    @autoreleasepool {
        [SCIDexKitStore registerDefaults];
        [SCIDexKitStore migrateIfNeeded];
        [SCIDexKitStore invalidateObservedCacheIfBuildChanged];
        [SCIBoolOverrideResolver reloadSnapshotFromDefaults];
        NSLog(@"[RyukGram][DexKitBootstrap] startup inert; saved overrides are not reapplied automatically");
    }
}
