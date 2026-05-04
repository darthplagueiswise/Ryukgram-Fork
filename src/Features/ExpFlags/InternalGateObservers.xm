#import <Foundation/Foundation.h>

// SCI DexKit v2.0 consolidated EasyGating/MCI/META/MSGC C bool interception in
// SCIMobileConfigBrokerRouter.xm. Keeping the previous fishhook observer active
// would duplicate hooks and route overrides through SCIExpFlags instead of mcbr.

%ctor {
    NSLog(@"[RyukGram][GateForce] legacy InternalGateObservers disabled; using SCIMobileConfigBrokerRouter v2");
}
