#import "SCIDexKitBoolRouter.h"
#import <Foundation/Foundation.h>

// DexKit v2.0 moved the runtime BOOL override logic to SCIDexKitBoolRouter.
// This file is kept only so older Makefile/source references remain harmless.
%ctor {
    NSLog(@"[RyukGram][DexKit] SCIRuntimeBoolMethodOverrides shim loaded; router is SCIDexKitBoolRouter");
}
