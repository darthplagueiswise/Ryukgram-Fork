/*
 * SCITier2EmployeeGate.m
 *
 * Structural iOS translation of InstaEclipse Tier-2 semantics.
 *
 * This module discovers and hooks ONLY the canonical `_ig_is_employee` thunk.
 * It never reads, aliases, redirects or forces `_ig_is_employee_or_test_user`,
 * test-account gates, dogfood gates, or unrelated MobileConfig descriptors.
 *
 * Discovery contains no hard-coded image offset or numeric MobileConfig id:
 *   ADRP x1, employee-descriptor GOT page
 *   LDR  x1, [x1, employee-descriptor GOT slot]
 *   B    shared `(session, descriptor) -> BOOL` evaluator
 *
 * Sideload safety requirements:
 *   - the generic Substrate symbol must be provided by ElleKit;
 *   - ElleKit's thread-safety mode is enabled before MSHookFunction;
 *   - only the tiny canonical `(session) -> BOOL` thunk is patched;
 *   - the shared evaluator remains untouched;
 *   - installation runs once, on the main thread, after app activation.
 */

#import "SCITier2EmployeeGate.h"
#import "../../Utils.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

enum {
    kTier2MaxGotRanges = 4,
    kTier2MaxDescriptorSlots = 8,
    kTier2MinimumThunkFanIn = 2,
};

typedef struct {
    uintptr_t start;
    size_t size;
} Tier2Range;

typedef struct {
    uintptr_t text;
    size_t textSize;
    Tier2Range gotRanges[kTier2MaxGotRanges];
    size_t gotRangeCount;
} Tier2ImageLayout;

typedef BOOL (*Tier2DescriptorEvaluator)(id session, const void *descriptor);
typedef void (*Tier2FunctionHooker)(void *target, void *replacement,
                                    void **original);
typedef void (*Tier2ThreadSafetySetter)(int enabled);

typedef struct {
    Tier2FunctionHooker hookFunction;
    Tier2ThreadSafetySetter enableThreadSafety;
    const char *imagePath;
} Tier2ElleKitAPI;

static atomic_bool gTier2Enabled = ATOMIC_VAR_INIT(false);
static atomic_bool gTier2Installed = ATOMIC_VAR_INIT(false);
static atomic_bool gTier2Installing = ATOMIC_VAR_INIT(false);
static atomic_bool gTier2Attempted = ATOMIC_VAR_INIT(false);

static const void *gEmployeeDescriptor = NULL;
static Tier2DescriptorEvaluator gEmployeeEvaluator = NULL;

static uintptr_t Tier2StripDataPointer(uintptr_t value) {
#if __has_feature(ptrauth_calls) && __has_include(<ptrauth.h>)
    return (uintptr_t)ptrauth_strip((void *)value, ptrauth_key_asda);
#else
    return value;
#endif
}

static void *Tier2StripFunctionPointer(void *value) {
#if __has_feature(ptrauth_calls) && __has_include(<ptrauth.h>)
    return ptrauth_strip(value, ptrauth_key_function_pointer);
#else
    return value;
#endif
}

static BOOL Tier2NameIs(const char actual[16], const char *expected) {
    return strncmp(actual, expected, 16) == 0;
}

static BOOL Tier2Inside(uintptr_t address, uintptr_t start, size_t size) {
    return size != 0 && address >= start && address - start < size;
}

static void Tier2AddRange(Tier2Range *ranges, size_t *count,
                          size_t maximum, uintptr_t start, size_t size) {
    if (!start || !size || *count >= maximum) return;
    ranges[(*count)++] = (Tier2Range){ start, size };
}

static BOOL Tier2BuildMainImageLayout(Tier2ImageLayout *layout) {
    memset(layout, 0, sizeof(*layout));

    const struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    for (uint32_t index = 0; index < _dyld_image_count(); ++index) {
        const struct mach_header *candidate = _dyld_get_image_header(index);
        if (candidate && candidate->magic == MH_MAGIC_64 &&
            candidate->filetype == MH_EXECUTE) {
            header = (const struct mach_header_64 *)candidate;
            slide = _dyld_get_image_vmaddr_slide(index);
            break;
        }
    }
    if (!header) return NO;

    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t commandIndex = 0;
         commandIndex < header->ncmds &&
         cursor + sizeof(struct load_command) <= end;
         ++commandIndex) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) ||
            cursor + command->cmdsize > end) {
            return NO;
        }

        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment =
                (const struct segment_command_64 *)command;
            const struct section_64 *section =
                (const struct section_64 *)((const uint8_t *)segment +
                                            sizeof(*segment));
            for (uint32_t sectionIndex = 0;
                 sectionIndex < segment->nsects;
                 ++sectionIndex) {
                const uintptr_t address =
                    (uintptr_t)section[sectionIndex].addr + (uintptr_t)slide;
                const size_t sectionSize = (size_t)section[sectionIndex].size;
                if (Tier2NameIs(section[sectionIndex].sectname, "__text") &&
                    Tier2NameIs(section[sectionIndex].segname, "__TEXT")) {
                    layout->text = address;
                    layout->textSize = sectionSize;
                } else if (Tier2NameIs(section[sectionIndex].sectname, "__got") ||
                           Tier2NameIs(section[sectionIndex].sectname, "__auth_got")) {
                    Tier2AddRange(layout->gotRanges, &layout->gotRangeCount,
                                  kTier2MaxGotRanges, address, sectionSize);
                }
            }
        }
        cursor += command->cmdsize;
    }

    return layout->text && layout->textSize >= 12 && layout->gotRangeCount;
}

static BOOL Tier2IsADRP(uint32_t instruction) {
    return (instruction & UINT32_C(0x9f000000)) == UINT32_C(0x90000000);
}

static BOOL Tier2IsLDRXUnsigned(uint32_t instruction) {
    return (instruction & UINT32_C(0xffc00000)) == UINT32_C(0xf9400000);
}

static BOOL Tier2IsB(uint32_t instruction) {
    return (instruction & UINT32_C(0xfc000000)) == UINT32_C(0x14000000);
}

static BOOL Tier2IsBL(uint32_t instruction) {
    return (instruction & UINT32_C(0xfc000000)) == UINT32_C(0x94000000);
}

static int64_t Tier2SignExtend(uint64_t value, unsigned int bits) {
    const uint64_t sign = UINT64_C(1) << (bits - 1);
    return (int64_t)((value ^ sign) - sign);
}

static uintptr_t Tier2DecodeADRP(uint32_t instruction, uintptr_t pc) {
    const uint64_t immediate =
        (((uint64_t)((instruction >> 5) & 0x7ffff)) << 2) |
        ((instruction >> 29) & 0x3);
    const int64_t pageDelta = Tier2SignExtend(immediate, 21) << 12;
    return (uintptr_t)((intptr_t)(pc & ~UINT64_C(0xfff)) + pageDelta);
}

static uintptr_t Tier2DecodeBranch(uint32_t instruction, uintptr_t pc) {
    const int64_t delta = Tier2SignExtend(instruction & 0x03ffffff, 26) << 2;
    return (uintptr_t)((intptr_t)pc + delta);
}

static uintptr_t Tier2LDRTarget(uintptr_t page, uint32_t instruction) {
    return page + (((instruction >> 10) & 0xfff) * sizeof(uintptr_t));
}

static size_t Tier2CollectDescriptorSlots(
    const Tier2ImageLayout *layout,
    const void *descriptor,
    uintptr_t slots[kTier2MaxDescriptorSlots]) {
    size_t count = 0;
    const uintptr_t wanted = Tier2StripDataPointer((uintptr_t)descriptor);

    for (size_t rangeIndex = 0;
         rangeIndex < layout->gotRangeCount && count < kTier2MaxDescriptorSlots;
         ++rangeIndex) {
        const Tier2Range range = layout->gotRanges[rangeIndex];
        uintptr_t cursor = (range.start + sizeof(uintptr_t) - 1) &
                           ~(uintptr_t)(sizeof(uintptr_t) - 1);
        const uintptr_t end = range.start + range.size;
        for (; cursor + sizeof(uintptr_t) <= end; cursor += sizeof(uintptr_t)) {
            const uintptr_t value = *(const uintptr_t *)cursor;
            if (Tier2StripDataPointer(value) == wanted) slots[count++] = cursor;
            if (count == kTier2MaxDescriptorSlots) break;
        }
    }
    return count;
}

static BOOL Tier2SlotIsKnown(uintptr_t slot,
                             const uintptr_t *slots,
                             size_t count) {
    for (size_t index = 0; index < count; ++index) {
        if (slots[index] == slot) return YES;
    }
    return NO;
}

static size_t Tier2DirectFanIn(const Tier2ImageLayout *layout,
                               uintptr_t target) {
    const uint32_t *words = (const uint32_t *)layout->text;
    const size_t count = layout->textSize / sizeof(uint32_t);
    size_t fanIn = 0;

    for (size_t index = 0; index < count; ++index) {
        const uint32_t instruction = words[index];
        if (!Tier2IsBL(instruction) && !Tier2IsB(instruction)) continue;
        const uintptr_t pc = layout->text + index * sizeof(uint32_t);
        if (Tier2DecodeBranch(instruction, pc) == target) ++fanIn;
    }
    return fanIn;
}

static BOOL Tier2FindEmployeeThunk(const Tier2ImageLayout *layout,
                                   const void *employeeDescriptor,
                                   uintptr_t *outThunk,
                                   uintptr_t *outEvaluator,
                                   size_t *outFanIn) {
    uintptr_t slots[kTier2MaxDescriptorSlots] = {0};
    const size_t slotCount = Tier2CollectDescriptorSlots(
        layout, employeeDescriptor, slots);
    if (!slotCount) return NO;

    const uint32_t *words = (const uint32_t *)layout->text;
    const size_t wordCount = layout->textSize / sizeof(uint32_t);
    uintptr_t selectedThunk = 0;
    uintptr_t selectedEvaluator = 0;
    size_t selectedFanIn = 0;
    size_t candidates = 0;

    for (size_t index = 0; index + 2 < wordCount; ++index) {
        const uint32_t adrp = words[index];
        const uint32_t ldr = words[index + 1];
        const uint32_t branch = words[index + 2];
        if (!Tier2IsADRP(adrp) || !Tier2IsLDRXUnsigned(ldr) ||
            !Tier2IsB(branch)) {
            continue;
        }

        const unsigned int adrpRegister = adrp & 0x1f;
        const unsigned int ldrDestination = ldr & 0x1f;
        const unsigned int ldrBase = (ldr >> 5) & 0x1f;
        if (adrpRegister != 1 || ldrDestination != 1 || ldrBase != 1) continue;

        const uintptr_t pc = layout->text + index * sizeof(uint32_t);
        const uintptr_t slot = Tier2LDRTarget(Tier2DecodeADRP(adrp, pc), ldr);
        if (!Tier2SlotIsKnown(slot, slots, slotCount)) continue;

        const uintptr_t evaluator = Tier2DecodeBranch(branch, pc + 8);
        if (!Tier2Inside(evaluator, layout->text, layout->textSize)) continue;

        const size_t fanIn = Tier2DirectFanIn(layout, pc);
        if (fanIn < kTier2MinimumThunkFanIn) continue;

        ++candidates;
        if (fanIn > selectedFanIn) {
            selectedThunk = pc;
            selectedEvaluator = evaluator;
            selectedFanIn = fanIn;
        }
    }

    if (candidates != 1 || !selectedThunk || !selectedEvaluator) return NO;
    *outThunk = selectedThunk;
    *outEvaluator = selectedEvaluator;
    *outFanIn = selectedFanIn;
    return YES;
}

static BOOL Tier2EmployeeThunkReplacement(id session) {
    if (atomic_load_explicit(&gTier2Enabled, memory_order_acquire)) {
        return YES;
    }

    Tier2DescriptorEvaluator evaluator = gEmployeeEvaluator;
    const void *descriptor = gEmployeeDescriptor;
    return evaluator && descriptor ? evaluator(session, descriptor) : NO;
}

static void *Tier2ResolveEmployeeDescriptor(void) {
    void *descriptor = dlsym(RTLD_DEFAULT, "ig_is_employee");
    if (!descriptor) descriptor = dlsym(RTLD_DEFAULT, "_ig_is_employee");
    return descriptor;
}

static BOOL Tier2SymbolInfo(void *symbol, Dl_info *info) {
    if (!symbol || !info) return NO;
    memset(info, 0, sizeof(*info));
    return dladdr(Tier2StripFunctionPointer(symbol), info) != 0 &&
           info->dli_fbase != NULL;
}

static BOOL Tier2ResolveElleKitAPI(Tier2ElleKitAPI *api) {
    if (!api) return NO;
    memset(api, 0, sizeof(*api));

    void *substrateHook = dlsym(RTLD_DEFAULT, "MSHookFunction");
    void *elleKitHook = dlsym(RTLD_DEFAULT, "EKHookFunction");
    void *threadSafety = dlsym(RTLD_DEFAULT, "EKEnableThreadSafety");
    if (!substrateHook || !elleKitHook || !threadSafety) {
        return NO;
    }

    Dl_info substrateInfo;
    Dl_info elleKitInfo;
    Dl_info threadSafetyInfo;
    if (!Tier2SymbolInfo(substrateHook, &substrateInfo) ||
        !Tier2SymbolInfo(elleKitHook, &elleKitInfo) ||
        !Tier2SymbolInfo(threadSafety, &threadSafetyInfo)) {
        return NO;
    }

    if (substrateInfo.dli_fbase != elleKitInfo.dli_fbase ||
        substrateInfo.dli_fbase != threadSafetyInfo.dli_fbase) {
        return NO;
    }

    api->hookFunction = (Tier2FunctionHooker)substrateHook;
    api->enableThreadSafety = (Tier2ThreadSafetySetter)threadSafety;
    api->imagePath = substrateInfo.dli_fname;
    return YES;
}

static void Tier2ClearLegacyEmployeeMasters(void) {
    NSArray<NSString *> *keys = @[
        @"sci_employee_internal",
        @"sci_force_mc_session_employee_gate",
        @"sci_force_ig_internal_employee",
        @"sci_force_ig_is_employee"
    ];
    for (NSString *key in keys) [SCIUtils setPref:@NO forKey:key];
}

static void Tier2InstallNow(void) {
    NSCAssert(NSThread.isMainThread, @"Tier-2 install must run on main thread");

    if (!atomic_load_explicit(&gTier2Enabled, memory_order_acquire) ||
        atomic_load_explicit(&gTier2Installed, memory_order_acquire) ||
        atomic_load_explicit(&gTier2Attempted, memory_order_acquire)) {
        return;
    }

    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(
            &gTier2Installing, &expected, true,
            memory_order_acq_rel, memory_order_acquire)) {
        return;
    }
    atomic_store_explicit(&gTier2Attempted, true, memory_order_release);

    @autoreleasepool {
        Tier2ImageLayout layout;
        Tier2ElleKitAPI elleKit;
        uintptr_t thunk = 0;
        uintptr_t evaluator = 0;
        size_t fanIn = 0;

        const void *employeeDescriptor = Tier2ResolveEmployeeDescriptor();
        const BOOL discovered = employeeDescriptor &&
            Tier2ResolveElleKitAPI(&elleKit) &&
            Tier2BuildMainImageLayout(&layout) &&
            Tier2FindEmployeeThunk(&layout, employeeDescriptor,
                                   &thunk, &evaluator, &fanIn);

        if (discovered) {
            /*
             * Publish the exact original thunk semantics before patching. The
             * replacement never needs ElleKit's trampoline: when disabled it
             * calls the untouched evaluator with the exact employee descriptor.
             */
            gEmployeeDescriptor = employeeDescriptor;
            gEmployeeEvaluator = (Tier2DescriptorEvaluator)evaluator;

            /*
             * Official ElleKit exposes this switch specifically so all other
             * threads are suspended around ElleKit's page-write and original-
             * protection restoration sequence.
             */
            elleKit.enableThreadSafety(1);

            void *originalMarker = NULL;
            elleKit.hookFunction((void *)thunk,
                                 (void *)Tier2EmployeeThunkReplacement,
                                 &originalMarker);

            if (originalMarker) {
                atomic_store_explicit(&gTier2Installed, true,
                                      memory_order_release);
                NSLog(@"[SCITier2] ElleKit thread-safe employee thunk installed provider=%s thunk=%p evaluator=%p fanIn=%zu",
                      elleKit.imagePath ? elleKit.imagePath : "<unknown>",
                      (void *)thunk, (void *)evaluator, fanIn);
            } else {
                NSLog(@"[SCITier2] ElleKit rejected employee thunk hook; not retrying");
            }
        } else {
            NSLog(@"[SCITier2] employee thunk discovery/provider validation failed closed");
        }
    }

    atomic_store_explicit(&gTier2Installing, false, memory_order_release);
}

static void Tier2ScheduleInstallOnMainThread(void) {
    if (!atomic_load_explicit(&gTier2Enabled, memory_order_acquire)) return;

    if (NSThread.isMainThread) {
        Tier2InstallNow();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            Tier2InstallNow();
        });
    }
}

void SCITier2EmployeeGateSetEnabled(BOOL enabled) {
    if (enabled) Tier2ClearLegacyEmployeeMasters();
    atomic_store_explicit(&gTier2Enabled, enabled, memory_order_release);

    if (enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (UIApplication.sharedApplication.applicationState ==
                UIApplicationStateActive) {
                Tier2InstallNow();
            }
        });
    }
}

BOOL SCITier2EmployeeGateEnabled(void) {
    return atomic_load_explicit(&gTier2Enabled, memory_order_acquire);
}

BOOL SCITier2EmployeeGateInstalled(void) {
    return atomic_load_explicit(&gTier2Installed, memory_order_acquire);
}

__attribute__((constructor))
static void Tier2Bootstrap(void) {
    @autoreleasepool {
        const BOOL enabled =
            [SCIUtils getBoolPref:@"sci_tier2_employee_internal"];
        atomic_store_explicit(&gTier2Enabled, enabled, memory_order_release);

        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
            Tier2ScheduleInstallOnMainThread();
        }];
    }
}
