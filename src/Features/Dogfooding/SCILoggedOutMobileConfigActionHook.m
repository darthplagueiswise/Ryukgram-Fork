#import "SCIDogfoodObjectRuntime.h"
#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define LOMCLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] LoggedOutMCAction " fmt, ##__VA_ARGS__)

// radare2 6.1.8 and Capstone 5.0.7 independently identify the thick Swift
// closure installed for the exact native "Force MobileConfig re-fetch" action:
//   action construction: Instagram VA 0x104aaf748 (function passed in x3)
//   closure context:     supplied as the Swift thick-context register x20
//   closure entry:       Instagram VA 0x105824584
//
// The function body overwrites x0 immediately and saves/restores x19-x28 through
// the common prologue/epilogue, confirming a zero-explicit-argument thick Swift
// closure. This hook is hash/version scoped by a 16-byte instruction signature.
// It does not scan titles, hook UIAlertAction globally, or guess a Bloks action.

static const uintptr_t kLOMCInstagramPreferredBase = 0x100000000ULL;
static const uintptr_t kLOMCForceFetchClosureVA = 0x105824584ULL;
static const uint8_t kLOMCForceFetchSignature[16] = {
    0xe0, 0x03, 0x1e, 0xaa,
    0x10, 0x18, 0x38, 0x97,
    0xfe, 0x03, 0x00, 0xaa,
    0xfd, 0x7b, 0x05, 0xa9
};

typedef void (*LOMCForceFetchClosureFn)(void);
static LOMCForceFetchClosureFn origLOMCForceFetchClosure = NULL;
static BOOL sLOMCInstalled = NO;

static BOOL LOMCResultRequested(NSString *result) {
    NSString *lower = result.lowercaseString ?: @"";
    return [lower containsString:@"fetch=requested"] ||
           [lower containsString:@"requested through oem"];
}

__attribute__((noinline))
static void newLOMCForceFetchClosure(void) {
#if defined(__arm64__)
    // Swift thick closures carry their captured context in x20. A normal C call
    // is allowed to use callee-saved registers internally, so preserve the exact
    // incoming value explicitly before doing Objective-C work and restore it
    // before tailing into the original closure fallback.
    register void *incomingSwiftContext __asm__("x20");
    void *savedSwiftContext = incomingSwiftContext;
#endif

    NSString *result = [SCIDogfoodObjectRuntime tryFetchSessionlessMobileConfig];
    BOOL requested = LOMCResultRequested(result);

    [SCIDogfoodObjectRuntime noteAction:@"Logged-out Force MobileConfig re-fetch"
                                  status:requested ? @"OEM request started" : @"OEM bridge blocked"
                                  detail:result ?: @""];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SCIUtils showToastForDuration:3.0
                                 title:requested
                                    ? @"MobileConfig fetch requested"
                                    : @"MobileConfig fetch blocked"
                              subtitle:result];
    });

    // The old closure re-enters the remote placeholder path. Preserve it only as
    // a fallback when the concrete native inputs were unavailable.
    if (!requested && origLOMCForceFetchClosure) {
#if defined(__arm64__)
        register void *restoredSwiftContext __asm__("x20") = savedSwiftContext;
        __asm__ volatile("" : : "r"(restoredSwiftContext) : "memory");
#endif
        origLOMCForceFetchClosure();
    }
}

static BOOL LOMCPathIsInstagram(const char *path) {
    if (!path) return NO;
    const char *last = strrchr(path, '/');
    last = last ? last + 1 : path;
    return strcmp(last, "Instagram") == 0;
}

static void LOMCInstall(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        if (sLOMCInstalled) return;
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char *path = _dyld_get_image_name(i);
            if (!LOMCPathIsInstagram(path)) continue;

            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            uintptr_t target = (uintptr_t)slide + kLOMCForceFetchClosureVA;
            if (target < (uintptr_t)slide + kLOMCInstagramPreferredBase) return;
            if (memcmp((const void *)target, kLOMCForceFetchSignature,
                       sizeof(kLOMCForceFetchSignature)) != 0) {
                LOMCLOG("signature mismatch at %p; direct hook skipped", (void *)target);
                return;
            }

            MSHookFunction((void *)target, (void *)&newLOMCForceFetchClosure,
                           (void **)&origLOMCForceFetchClosure);
            sLOMCInstalled = origLOMCForceFetchClosure != NULL;
            LOMCLOG("exact native force-fetch closure hook installed=%d target=%p",
                    sLOMCInstalled, (void *)target);
            return;
        }
    }
}

static void LOMCImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    LOMCInstall();
}

__attribute__((constructor))
static void SCILoggedOutMobileConfigActionHookCtor(void) {
    @autoreleasepool {
        LOMCInstall();
        _dyld_register_func_for_add_image(LOMCImageLoaded);
    }
}
