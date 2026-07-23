/*
 * SCITier2EmployeeGate.m
 *
 * iOS application of InstaEclipse's Tier-2 gate semantics:
 *   1. resolve the canonical is_employee descriptor;
 *   2. find the tiny (session)->BOOL thunk structurally from its GOT load;
 *   3. hook the shared evaluator with ElleKit, preserving its exact ABI;
 *   4. make is_employee_or_test_user consumers observe the canonical employee
 *      result instead of independently forcing the combined gate;
 *   5. cover Objective-C raw MobileConfig reads that inline the descriptor.
 *
 * No hard-coded image offset or MobileConfig numeric ID is used. No manual
 * code-page, GOT, PAC or authenticated-pointer write is performed here;
 * function/message replacement is delegated to the injected ElleKit runtime.
 */

#import "SCITier2EmployeeGate.h"
#import "../../Utils.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

enum {
    kTier2MaxGotRanges = 4,
    kTier2MaxDescriptorSlots = 8,
    kTier2MaxGetterHooks = 64,
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
typedef BOOL (*Tier2GetterOneArgument)(id receiver, SEL selector, uintptr_t config);
typedef BOOL (*Tier2GetterTwoArguments)(id receiver, SEL selector,
                                        uintptr_t config, uintptr_t options);
typedef void (*Tier2FunctionHooker)(void *target, void *replacement,
                                    void **original);
typedef void (*Tier2MessageHooker)(Class cls, SEL selector, IMP replacement,
                                   IMP *original);

typedef struct {
    Class cls;
    SEL selector;
    unsigned int explicitArgumentCount;
    IMP original;
} Tier2GetterHook;

static atomic_bool gTier2Enabled = ATOMIC_VAR_INIT(false);
static atomic_bool gTier2Installed = ATOMIC_VAR_INIT(false);
static atomic_bool gTier2Installing = ATOMIC_VAR_INIT(false);

static void *gEmployeeDescriptor = NULL;
static void *gEmployeeOrTestUserDescriptor = NULL;
static uintptr_t gEmployeeConfig = 0;
static uintptr_t gEmployeeOrTestUserConfig = 0;
static Tier2DescriptorEvaluator gOriginalDescriptorEvaluator = NULL;
static Tier2GetterHook gGetterHooks[kTier2MaxGetterHooks];
static size_t gGetterHookCount = 0;
static BOOL (*gOriginalLegacyEmployeeMaster)(id, SEL) = NULL;

extern void SCIRefreshGraphQLDogfoodForceEnabled(void);

static dispatch_queue_t Tier2InstallQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ryukgram.tier2-employee", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static uintptr_t Tier2StripPointer(uintptr_t value) {
#if __has_feature(ptrauth_calls) && __has_include(<ptrauth.h>)
    return (uintptr_t)ptrauth_strip((void *)value, ptrauth_key_asda);
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
    if (start == 0 || size == 0 || *count >= maximum) return;
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
                (const struct section_64 *)((const uint8_t *)segment + sizeof(*segment));
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
    return layout->text != 0 && layout->textSize >= 12 &&
           layout->gotRangeCount != 0;
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

static size_t Tier2CollectDescriptorSlots(const Tier2ImageLayout *layout,
                                          const void *descriptor,
                                          uintptr_t slots[kTier2MaxDescriptorSlots]) {
    size_t count = 0;
    const uintptr_t wanted = Tier2StripPointer((uintptr_t)descriptor);
    for (size_t rangeIndex = 0;
         rangeIndex < layout->gotRangeCount && count < kTier2MaxDescriptorSlots;
         ++rangeIndex) {
        const Tier2Range range = layout->gotRanges[rangeIndex];
        uintptr_t cursor = (range.start + sizeof(uintptr_t) - 1) &
                           ~(uintptr_t)(sizeof(uintptr_t) - 1);
        const uintptr_t end = range.start + range.size;
        for (; cursor + sizeof(uintptr_t) <= end; cursor += sizeof(uintptr_t)) {
            const uintptr_t value = *(const uintptr_t *)cursor;
            if (Tier2StripPointer(value) == wanted) slots[count++] = cursor;
            if (count == kTier2MaxDescriptorSlots) break;
        }
    }
    return count;
}

static BOOL Tier2SlotIsKnown(uintptr_t slot, const uintptr_t *slots, size_t count) {
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

static BOOL Tier2FindCanonicalEvaluator(const Tier2ImageLayout *layout,
                                        const void *employeeDescriptor,
                                        uintptr_t *outThunk,
                                        uintptr_t *outEvaluator,
                                        size_t *outFanIn) {
    uintptr_t slots[kTier2MaxDescriptorSlots] = {0};
    const size_t slotCount = Tier2CollectDescriptorSlots(
        layout, employeeDescriptor, slots);
    if (slotCount == 0) return NO;

    const uint32_t *words = (const uint32_t *)layout->text;
    const size_t wordCount = layout->textSize / sizeof(uint32_t);
    uintptr_t selectedThunk = 0;
    uintptr_t selectedEvaluator = 0;
    size_t selectedFanIn = 0;
    size_t candidateCount = 0;

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
        ++candidateCount;
        if (fanIn > selectedFanIn) {
            selectedThunk = pc;
            selectedEvaluator = evaluator;
            selectedFanIn = fanIn;
        }
    }

    if (candidateCount != 1 || selectedThunk == 0 || selectedEvaluator == 0) {
        return NO;
    }
    *outThunk = selectedThunk;
    *outEvaluator = selectedEvaluator;
    *outFanIn = selectedFanIn;
    return YES;
}

static BOOL Tier2DescriptorMatches(const void *actual, const void *expected) {
    return actual && expected &&
           Tier2StripPointer((uintptr_t)actual) ==
           Tier2StripPointer((uintptr_t)expected);
}

static BOOL Tier2CanonicalEmployeeValue(void) {
    return atomic_load_explicit(&gTier2Enabled, memory_order_acquire) ? YES : NO;
}

static BOOL Tier2DescriptorEvaluatorReplacement(id session,
                                                const void *descriptor) {
    if (atomic_load_explicit(&gTier2Enabled, memory_order_acquire)) {
        if (Tier2DescriptorMatches(descriptor, gEmployeeDescriptor) ||
            Tier2DescriptorMatches(descriptor, gEmployeeOrTestUserDescriptor)) {
            return Tier2CanonicalEmployeeValue();
        }
    }
    return gOriginalDescriptorEvaluator
        ? gOriginalDescriptorEvaluator(session, descriptor)
        : NO;
}

static BOOL Tier2ConfigMatches(uintptr_t value) {
    return value != 0 &&
           (value == (uintptr_t)gEmployeeDescriptor ||
            value == (uintptr_t)gEmployeeOrTestUserDescriptor ||
            value == gEmployeeConfig ||
            value == gEmployeeOrTestUserConfig);
}

static IMP Tier2OriginalGetter(id receiver, SEL selector,
                               unsigned int explicitArgumentCount) {
    for (Class cls = object_getClass(receiver); cls; cls = class_getSuperclass(cls)) {
        for (size_t index = 0; index < gGetterHookCount; ++index) {
            const Tier2GetterHook hook = gGetterHooks[index];
            if (hook.cls == cls && hook.selector == selector &&
                hook.explicitArgumentCount == explicitArgumentCount) {
                return hook.original;
            }
        }
    }
    return NULL;
}

static BOOL Tier2GetterOneReplacement(id receiver, SEL selector,
                                      uintptr_t config) {
    if (atomic_load_explicit(&gTier2Enabled, memory_order_acquire) &&
        Tier2ConfigMatches(config)) {
        return Tier2CanonicalEmployeeValue();
    }
    Tier2GetterOneArgument original = (Tier2GetterOneArgument)
        Tier2OriginalGetter(receiver, selector, 1);
    return original ? original(receiver, selector, config) : NO;
}

static BOOL Tier2GetterTwoReplacement(id receiver, SEL selector,
                                      uintptr_t config, uintptr_t options) {
    if (atomic_load_explicit(&gTier2Enabled, memory_order_acquire) &&
        Tier2ConfigMatches(config)) {
        return Tier2CanonicalEmployeeValue();
    }
    Tier2GetterTwoArguments original = (Tier2GetterTwoArguments)
        Tier2OriginalGetter(receiver, selector, 2);
    return original ? original(receiver, selector, config, options) : NO;
}

static BOOL Tier2IsBoolReturn(Method method) {
    if (!method) return NO;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == 'B' || type[0] == 'c' || type[0] == 'C';
}

static BOOL Tier2IsRegisterSizedArgument(Method method, unsigned int index) {
    char type[64] = {0};
    method_getArgumentType(method, index, type, sizeof(type));
    const char *cursor = type;
    while (*cursor == 'r' || *cursor == 'n' || *cursor == 'N' ||
           *cursor == 'o' || *cursor == 'O' || *cursor == 'R' ||
           *cursor == 'V') {
        ++cursor;
    }
    return *cursor == '@' || *cursor == '^' || *cursor == '*' ||
           *cursor == 'Q' || *cursor == 'q' || *cursor == 'L' ||
           *cursor == 'l';
}

static BOOL Tier2MethodHasSafeABI(Method method,
                                  unsigned int explicitArgumentCount) {
    if (!Tier2IsBoolReturn(method) ||
        method_getNumberOfArguments(method) != explicitArgumentCount + 2) {
        return NO;
    }
    for (unsigned int index = 0; index < explicitArgumentCount; ++index) {
        if (!Tier2IsRegisterSizedArgument(method, index + 2)) return NO;
    }
    return YES;
}

static BOOL Tier2HookAlreadyRecorded(Class cls, SEL selector) {
    for (size_t index = 0; index < gGetterHookCount; ++index) {
        if (gGetterHooks[index].cls == cls &&
            gGetterHooks[index].selector == selector) return YES;
    }
    return NO;
}

static size_t Tier2InstallGetterHooks(Tier2MessageHooker hooker) {
    const SEL selectors[] = {
        sel_registerName("getBool:"),
        sel_registerName("getBool:withOptions:"),
    };
    const unsigned int explicitCounts[] = {1, 2};
    const IMP replacements[] = {
        (IMP)Tier2GetterOneReplacement,
        (IMP)Tier2GetterTwoReplacement,
    };

    const int capacity = objc_getClassList(NULL, 0);
    if (capacity <= 0) return 0;
    Class *classes = (Class *)calloc((size_t)capacity, sizeof(Class));
    if (!classes) return 0;
    const int reported = objc_getClassList(classes, capacity);
    const int classCount = reported < capacity ? reported : capacity;

    const size_t initialCount = gGetterHookCount;
    for (int classIndex = 0;
         classIndex < classCount && gGetterHookCount < kTier2MaxGetterHooks;
         ++classIndex) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(classes[classIndex], &methodCount);
        if (!methods) continue;
        for (unsigned int methodIndex = 0;
             methodIndex < methodCount && gGetterHookCount < kTier2MaxGetterHooks;
             ++methodIndex) {
            Method method = methods[methodIndex];
            const SEL methodSelector = method_getName(method);
            for (size_t selectorIndex = 0; selectorIndex < 2; ++selectorIndex) {
                if (methodSelector != selectors[selectorIndex] ||
                    Tier2HookAlreadyRecorded(classes[classIndex], methodSelector) ||
                    !Tier2MethodHasSafeABI(method, explicitCounts[selectorIndex])) {
                    continue;
                }

                IMP original = NULL;
                hooker(classes[classIndex], methodSelector,
                       replacements[selectorIndex], &original);
                if (!original) continue;
                gGetterHooks[gGetterHookCount++] = (Tier2GetterHook){
                    classes[classIndex], methodSelector,
                    explicitCounts[selectorIndex], original
                };
            }
        }
        free(methods);
    }
    free(classes);
    return gGetterHookCount - initialCount;
}

static BOOL Tier2LegacyEmployeeMasterReplacement(id receiver, SEL selector) {
    if (atomic_load_explicit(&gTier2Enabled, memory_order_acquire)) return NO;
    return gOriginalLegacyEmployeeMaster
        ? gOriginalLegacyEmployeeMaster(receiver, selector)
        : NO;
}

static void Tier2InstallLegacyMasterNeutralizer(Tier2MessageHooker hooker) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [SCIInternalGatePrefs class];
        SEL selector = @selector(employeeInternalMasterEnabled);
        Method method = class_getClassMethod(cls, selector);
        if (!method || !Tier2MethodHasSafeABI(method, 0)) return;
        Class meta = object_getClass(cls);
        IMP original = NULL;
        hooker(meta, selector, (IMP)Tier2LegacyEmployeeMasterReplacement,
               &original);
        gOriginalLegacyEmployeeMaster = (BOOL (*)(id, SEL))original;
    });
}

static void Tier2DisableLegacyForcers(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            @"sci_employee_internal",
            @"sci_force_mc_session_employee_gate",
            @"sci_force_ig_internal_employee",
            @"sci_force_ig_is_employee",
            @"sci_force_easy_gating_all",
            @"sci_force_easy_gating_internal",
            @"sci_force_easy_gating_auth",
            @"sci_force_easy_gating_mcq",
            @"sci_force_easy_gating_platform",
            @"sci_force_mc_internal_use_all",
            @"sci_force_all_mc_gates",
            @"sci_force_mc_internal_use_boolean",
            @"sci_force_sessioned_mc_all",
            @"sci_force_msgc_sessioned_boolean",
            @"sci_force_mci_experiment_boolean",
            @"sci_force_mci_extension_boolean",
        ];
    });
    for (NSString *key in keys) [SCIUtils setPref:@NO forKey:key];
    SCIRefreshGraphQLDogfoodForceEnabled();
}

static void Tier2InstallIfPossible(void) {
    if (!atomic_load_explicit(&gTier2Enabled, memory_order_acquire) ||
        atomic_load_explicit(&gTier2Installed, memory_order_acquire)) {
        return;
    }
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gTier2Installing, &expected, true)) return;

    Tier2MessageHooker messageHook =
        (Tier2MessageHooker)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    Tier2FunctionHooker functionHook =
        (Tier2FunctionHooker)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (!messageHook || !functionHook) {
        NSLog(@"[SCITier2] ElleKit hook APIs unavailable; installation skipped");
        atomic_store(&gTier2Installing, false);
        return;
    }

    Tier2InstallLegacyMasterNeutralizer(messageHook);
    Tier2DisableLegacyForcers();

    gEmployeeDescriptor = dlsym(RTLD_DEFAULT, "ig_is_employee");
    gEmployeeOrTestUserDescriptor =
        dlsym(RTLD_DEFAULT, "ig_is_employee_or_test_user");
    if (!gEmployeeDescriptor) {
        NSLog(@"[SCITier2] canonical employee descriptor unavailable");
        atomic_store(&gTier2Installing, false);
        return;
    }
    gEmployeeConfig = *(const uintptr_t *)gEmployeeDescriptor;
    if (gEmployeeOrTestUserDescriptor) {
        gEmployeeOrTestUserConfig =
            *(const uintptr_t *)gEmployeeOrTestUserDescriptor;
    }

    Tier2ImageLayout layout;
    uintptr_t thunk = 0;
    uintptr_t evaluator = 0;
    size_t fanIn = 0;
    if (!Tier2BuildMainImageLayout(&layout) ||
        !Tier2FindCanonicalEvaluator(&layout, gEmployeeDescriptor,
                                     &thunk, &evaluator, &fanIn)) {
        NSLog(@"[SCITier2] canonical (session)->BOOL thunk was not proven");
        atomic_store(&gTier2Installing, false);
        return;
    }

    void *original = NULL;
    functionHook((void *)evaluator,
                 (void *)Tier2DescriptorEvaluatorReplacement,
                 &original);
    if (!original) {
        NSLog(@"[SCITier2] ElleKit did not return a callable evaluator original");
        atomic_store(&gTier2Installing, false);
        return;
    }
    gOriginalDescriptorEvaluator = (Tier2DescriptorEvaluator)original;

    const size_t getterHooks = Tier2InstallGetterHooks(messageHook);
    atomic_store_explicit(&gTier2Installed, true, memory_order_release);
    atomic_store(&gTier2Installing, false);
    NSLog(@"[SCITier2] installed canonical employee gate; thunk=%p evaluator=%p fan-in=%zu getters=%zu combined-alias=%d",
          (void *)thunk, (void *)evaluator, fanIn, getterHooks,
          gEmployeeOrTestUserDescriptor != NULL);
}

static void Tier2ScheduleInstall(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.75 * NSEC_PER_SEC)),
                   Tier2InstallQueue(), ^{
        @autoreleasepool { Tier2InstallIfPossible(); }
    });
}

void SCITier2EmployeeGateSetEnabled(BOOL enabled) {
    atomic_store_explicit(&gTier2Enabled, enabled, memory_order_release);
    if (!enabled) return;

    Tier2MessageHooker messageHook =
        (Tier2MessageHooker)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (messageHook) Tier2InstallLegacyMasterNeutralizer(messageHook);
    Tier2DisableLegacyForcers();
    Tier2ScheduleInstall();
}

BOOL SCITier2EmployeeGateEnabled(void) {
    return atomic_load_explicit(&gTier2Enabled, memory_order_acquire) ? YES : NO;
}

BOOL SCITier2EmployeeGateInstalled(void) {
    return atomic_load_explicit(&gTier2Installed, memory_order_acquire) ? YES : NO;
}

__attribute__((constructor))
static void SCITier2EmployeeGateBootstrap(void) {
    @autoreleasepool {
        const BOOL enabled = [SCIUtils getBoolPref:@"sci_tier2_employee_internal"];
        atomic_store_explicit(&gTier2Enabled, enabled, memory_order_release);
        if (!enabled) return;

        Tier2MessageHooker messageHook =
            (Tier2MessageHooker)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        if (messageHook) Tier2InstallLegacyMasterNeutralizer(messageHook);
        Tier2DisableLegacyForcers();
        Tier2ScheduleInstall();
    }
}
