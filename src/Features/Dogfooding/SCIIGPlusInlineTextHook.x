// SCIIGPlusInlineTextHook.x
// -----------------------------------------------------------------------------
// Experimental IGPlus Swift direct-dispatch hook.
//
// Why this exists:
// IGConsumerSubsService @objc getters can be hooked through MSHookMessageEx, but
// the app often uses Swift direct dispatch and never calls the ObjC IMP. The
// direct decisor found in the executable is inside __TEXT. ElleKit/Substrate style
// MSHookFunction patches that instruction stream directly; that is why this is
// isolated behind its own explicit dev toggle and crash guard.
//
// This hook intentionally hooks the whole generic benefit decisor and returns YES
// for every call. It is not descriptor-granular. The user explicitly requested
// this mode to test the "everything active" path.
//
// Timing:
// - %ctor reads only a cheap pref and early-returns when off.
// - When on, install is deferred until app active to avoid pre-main/scene launch
//   watchdog cost. No defaults/ObjC are read from the replacement.
//
// Sideload note:
// In normal sideload, __TEXT inline patching may still be rejected by platform
// code-signing. ElleKit can perform the jump, but this file does not pretend
// that every signing environment allows it. The toggle is experimental.

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"
#import "SCIInstallOnce.h"

#define IGTEXTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusText " fmt, ##__VA_ARGS__)

static NSString *const kSCIIGPlusInlineTextDecisorKey = @"sci_igplus_inline_text_decisor_all";

// VM address validated in the current IGConsumerSubs direct-dispatch analysis.
// Runtime address = vmaddr + _dyld_get_image_vmaddr_slide(Instagram).
static uintptr_t const kSCIIGPlusBenefitDecisorVM = 0x101c42d58ULL;

static bool (*orig_igplus_benefit_decisor)(void *descriptor) = NULL;
static volatile bool gIGPlusTextHookInstalled = false;

static bool hook_igplus_benefit_decisor(void *descriptor) {
    (void)descriptor;
    return true;
}

static intptr_t SCIInstagramSlide(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name];
        NSString *last = path.lastPathComponent;
        if ([last isEqualToString:@"Instagram"] || [path rangeOfString:@"/Instagram.app/Instagram"].location != NSNotFound) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

static void SCIInstallIGPlusInlineTextHook(void) {
    if (gIGPlusTextHookInstalled) return;
    if (![SCIInternalGatePrefs individualGateEnabledForKey:kSCIIGPlusInlineTextDecisorKey]) {
        return;
    }

    intptr_t slide = SCIInstagramSlide();
    if (slide == 0) {
        IGTEXTLOG("Instagram slide unavailable");
        return;
    }

    void *target = (void *)(kSCIIGPlusBenefitDecisorVM + (uintptr_t)slide);
    if (!target) return;

    IGTEXTLOG("MSHookFunction target=%p vm=0x%llx", target, (unsigned long long)kSCIIGPlusBenefitDecisorVM);
    MSHookFunction(target, (void *)hook_igplus_benefit_decisor, (void **)&orig_igplus_benefit_decisor);
    gIGPlusTextHookInstalled = true;
    IGTEXTLOG("installed orig=%p", orig_igplus_benefit_decisor);
}

%ctor {
    @autoreleasepool {
        if (![SCIInternalGatePrefs individualGateEnabledForKey:kSCIIGPlusInlineTextDecisorKey]) {
            return;
        }
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        // Install after UIKit/app activation rather than pre-main; this is still
        // an inline __TEXT hook, but avoids doing it inside dyld/pre-UI startup.
        SCIInstallOnceOnActive(^{ SCIInstallIGPlusInlineTextHook(); });
    }
}
