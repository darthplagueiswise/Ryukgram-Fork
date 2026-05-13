#import <Foundation/Foundation.h>

/*
 Unified ObjC MobileConfig getter hooks now live in:
   src/Features/ExpFlags/Hooks/SCIObjCMobileConfigGetterObserver.xm

 This file is intentionally kept as a no-op to avoid double-hooking
 IGMobileConfigContextManager getBool selectors with separate global orig IMPs.
 */
