#import <Foundation/Foundation.h>

// SCI DexKit v2.0 moved C MobileConfig/EasyGating interception to
// SCIMobileConfigBrokerRouter.xm, which hooks the real function bodies with
// MSHookFunction and stores per-specifier/per-gate overrides in mcbr:<id>:<hex>.
// This legacy fishhook observer is intentionally disabled to avoid double hooks.

%ctor {
    NSLog(@"[RyukGram][MCSymbolObserver] legacy fishhook observer disabled; using SCIMobileConfigBrokerRouter v2");
}
