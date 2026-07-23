/*
 * SCITier2EmployeeGate.m
 *
 * Runtime translation of the Android Tier-2 algorithm for a Feather/ElleKit
 * injected dylib.  The source deliberately contains no feature name, numeric
 * MobileConfig identifier, class name, image offset, or target descriptor.
 *
 * The only discovery anchor is the stable raw MobileConfig selector
 * getBool:withOptions:.  The selected descriptor is discovered from the loaded
 * executable by shape (short branch-free leaf), then reuse (dispatch fan-in).
 *
 * Application uses ElleKit's MSHookMessageEx only.  It performs no code-page
 * patching, symbol-slot rebinding, or manual authenticated-pointer writes.
 * ElleKit owns the arm64e/PAC-safe class replacement.
 */

#import "SCITier2EmployeeGate.h"
#import "../../Utils.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    kTier2MaxCandidates = 256,
    kTier2MaxDataRanges = 6,
    kTier2MaxGotRanges = 4,
    kTier2MaxRawSelrefs = 64,
    kTier2MaxGetterHooks = 32,
    kTier2MaxLeafArm64Instructions = 64,
    kTier2RetInstruction = 0xD65F03C0,
};

typedef struct {
    uintptr_t start;
    size_t size;
} Tier2Range;

typedef struct {
    uintptr_t text;
    size_t textSize;
    uintptr_t selrefs;
    size_t selrefsSize;
    Tier2Range gotRanges[kTier2MaxGotRanges];
    size_t gotRangeCount;
    Tier2Range dataRanges[kTier2MaxDataRanges];
    size_t dataRangeCount;
} Tier2ImageLayout;

typedef struct {
    uintptr_t function;
    uintptr_t configSlot;
    size_t instructionCount;
    size_t dispatchFanIn;
} Tier2Candidate;

typedef BOOL (*Tier2RawGetterIMP)(id receiver,
                                  SEL selector,
                                  uint64_t configWord,
                                  id options);
typedef void (*Tier2MessageHooker)(Class cls,
                                   SEL selector,
                                   IMP replacement,
                                   IMP *original);

typedef struct {
    Class cls;
    Tier2RawGetterIMP original;
} Tier2GetterHook;

static volatile BOOL gTier2Enabled = NO;
static volatile BOOL gTier2Installing = NO;
static volatile BOOL gTier2Installed = NO;
static uint64_t gTier2TargetConfigWord = 0;
static Tier2GetterHook gTier2GetterHooks[kTier2MaxGetterHooks];
static size_t gTier2GetterHookCount = 0;

static void Tier2InstallIfPossible(void);

static void Tier2ScheduleInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gTier2Enabled) Tier2InstallIfPossible();
    });
}

void SCITier2EmployeeGateSetEnabled(BOOL enabled) {
    gTier2Enabled = enabled;
    if (enabled) Tier2ScheduleInstall();
}

BOOL SCITier2EmployeeGateEnabled(void) {
    return gTier2Enabled;
}

BOOL SCITier2EmployeeGateInstalled(void) {
    return gTier2Installed;
}

static BOOL Tier2NameIs(const char actual[16], const char *expected) {
    return strncmp(actual, expected, 16) == 0;
}

/* arm64e authentication occupies high bits; iOS user VAs use the low payload. */
static uintptr_t Tier2StripPointer(uintptr_t pointer) {
    return pointer & UINT64_C(0x0000ffffffffffff);
}

static BOOL Tier2Inside(uintptr_t address, uintptr_t start, size_t size) {
    return address >= start && address < start + size;
}

static BOOL Tier2IsADRP(uint32_t instruction) {
    return (instruction & 0x9f000000) == 0x90000000;
}

static BOOL Tier2IsLDRXUnsigned(uint32_t instruction) {
    return (instruction & 0xffc00000) == 0xf9400000;
}

static BOOL Tier2IsBL(uint32_t instruction) {
    return (instruction & 0xfc000000) == 0x94000000;
}

static uint32_t Tier2RegisterD(uint32_t instruction) {
    return instruction & 0x1f;
}

static uint32_t Tier2RegisterN(uint32_t instruction) {
    return (instruction >> 5) & 0x1f;
}

static uintptr_t Tier2DecodeADRP(uint32_t instruction, uintptr_t pc) {
    int64_t immediate = (((int64_t)((instruction >> 5) & 0x7ffff)) << 2) |
                        ((instruction >> 29) & 0x3);
    if (immediate & (INT64_C(1) << 20)) {
        immediate |= ~((INT64_C(1) << 21) - 1);
    }
    return (pc & ~UINT64_C(0xfff)) + (uintptr_t)(immediate * 4096);
}

static uintptr_t Tier2LDRTarget(uintptr_t page, uint32_t instruction) {
    return page + (((instruction >> 10) & 0xfff) * sizeof(uint64_t));
}

static BOOL Tier2HasConditionalBranch(const uint32_t *words,
                                      size_t start,
                                      size_t end) {
    for (size_t index = start; index < end; ++index) {
        const uint32_t instruction = words[index];
        /* B.cond, CBZ/CBNZ, TBZ/TBNZ. */
        if ((instruction & 0xff000010) == 0x54000000 ||
            (instruction & 0x7e000000) == 0x34000000 ||
            (instruction & 0x7e000000) == 0x36000000) {
            return YES;
        }
    }
    return NO;
}

static size_t Tier2PreviousFunctionStart(const uint32_t *words, size_t index) {
    const size_t lowerBound = index > 256 ? index - 256 : 0;
    for (size_t cursor = index; cursor > lowerBound; --cursor) {
        if (words[cursor - 1] == kTier2RetInstruction) return cursor;
    }
    return lowerBound;
}

static size_t Tier2NextFunctionEnd(const uint32_t *words,
                                   size_t wordCount,
                                   size_t index) {
    const size_t limit = index + 512 < wordCount ? index + 512 : wordCount;
    for (size_t cursor = index; cursor < limit; ++cursor) {
        if (words[cursor] == kTier2RetInstruction) return cursor + 1;
    }
    return 0;
}

static void Tier2AddRange(Tier2Range *ranges,
                          size_t *count,
                          size_t maximum,
                          uintptr_t start,
                          size_t size) {
    if (size == 0 || *count >= maximum) return;
    ranges[(*count)++] = (Tier2Range){ start, size };
}

static BOOL Tier2InsideAnyGotRange(const Tier2ImageLayout *layout,
                                   uintptr_t address) {
    for (size_t index = 0; index < layout->gotRangeCount; ++index) {
        const Tier2Range range = layout->gotRanges[index];
        if (Tier2Inside(address, range.start, range.size)) return YES;
    }
    return NO;
}

static size_t Tier2CountDispatchReferences(const Tier2ImageLayout *layout,
                                           uintptr_t function) {
    size_t result = 0;
    const uintptr_t strippedFunction = Tier2StripPointer(function);

    for (size_t rangeIndex = 0; rangeIndex < layout->dataRangeCount; ++rangeIndex) {
        const Tier2Range range = layout->dataRanges[rangeIndex];
        uintptr_t cursor = (range.start + 7) & ~UINT64_C(7);
        const uintptr_t end = range.start + range.size;

        for (; cursor + sizeof(uintptr_t) <= end; cursor += sizeof(uintptr_t)) {
            const uintptr_t value = *(const uintptr_t *)cursor;
            if (Tier2StripPointer(value) == strippedFunction) ++result;
        }
    }
    return result;
}

static BOOL Tier2BuildImageLayout(const struct mach_header_64 *header,
                                  intptr_t slide,
                                  Tier2ImageLayout *layout) {
    memset(layout, 0, sizeof(*layout));

    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t commandIndex = 0;
         commandIndex < header->ncmds && cursor + sizeof(struct load_command) <= end;
         ++commandIndex) {
        const struct load_command *loadCommand = (const struct load_command *)cursor;
        if (loadCommand->cmdsize < sizeof(struct load_command) ||
            cursor + loadCommand->cmdsize > end) {
            return NO;
        }

        if (loadCommand->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment =
                (const struct segment_command_64 *)loadCommand;
            const BOOL isData = Tier2NameIs(segment->segname, "__DATA") ||
                                Tier2NameIs(segment->segname, "__DATA_CONST") ||
                                Tier2NameIs(segment->segname, "__AUTH") ||
                                Tier2NameIs(segment->segname, "__AUTH_CONST");
            if (isData) {
                Tier2AddRange(layout->dataRanges,
                               &layout->dataRangeCount,
                               kTier2MaxDataRanges,
                               (uintptr_t)segment->vmaddr + slide,
                               (size_t)segment->vmsize);
            }

            const struct section_64 *section =
                (const struct section_64 *)((const uint8_t *)segment + sizeof(*segment));
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; ++sectionIndex) {
                const uintptr_t address = (uintptr_t)section[sectionIndex].addr + slide;
                const size_t size = (size_t)section[sectionIndex].size;

                if (Tier2NameIs(section[sectionIndex].sectname, "__text")) {
                    layout->text = address;
                    layout->textSize = size;
                } else if (Tier2NameIs(section[sectionIndex].sectname, "__objc_selrefs")) {
                    layout->selrefs = address;
                    layout->selrefsSize = size;
                } else if (Tier2NameIs(section[sectionIndex].sectname, "__got") ||
                           Tier2NameIs(section[sectionIndex].sectname, "__auth_got")) {
                    Tier2AddRange(layout->gotRanges,
                                   &layout->gotRangeCount,
                                   kTier2MaxGotRanges,
                                   address,
                                   size);
                }
            }
        }

        cursor += loadCommand->cmdsize;
    }

    return layout->text != 0 && layout->gotRangeCount != 0 && layout->selrefs != 0;
}

static BOOL Tier2RawGetterSelref(uintptr_t address) {
    const uintptr_t value = Tier2StripPointer(*(const uintptr_t *)address);
    if (value == 0) return NO;
    const char *name = sel_getName((SEL)value);
    return name != NULL && strcmp(name, "getBool:withOptions:") == 0;
}

static BOOL Tier2IsKnownRawGetterSelref(const uintptr_t *rawSelrefs,
                                        size_t count,
                                        uintptr_t address) {
    for (size_t index = 0; index < count; ++index) {
        if (rawSelrefs[index] == address) return YES;
    }
    return NO;
}

static BOOL Tier2ConfigSlotBeforeCall(const uint32_t *words,
                                      uintptr_t text,
                                      size_t selectorIndex,
                                      size_t callIndex,
                                      const Tier2ImageLayout *layout,
                                      uintptr_t *outSlot) {
    const size_t lowerBound = selectorIndex > 24 ? selectorIndex - 24 : 0;
    for (size_t index = lowerBound; index + 1 < callIndex; ++index) {
        const uint32_t adrp = words[index];
        const uint32_t ldr = words[index + 1];
        if (!Tier2IsADRP(adrp) || !Tier2IsLDRXUnsigned(ldr) ||
            Tier2RegisterN(ldr) != Tier2RegisterD(adrp)) {
            continue;
        }

        const uintptr_t page = Tier2DecodeADRP(adrp, text + index * 4);
        const uintptr_t slot = Tier2LDRTarget(page, ldr);
        if (!Tier2InsideAnyGotRange(layout, slot)) continue;

        const uint32_t valueRegister = Tier2RegisterD(ldr);
        for (size_t useIndex = index + 2; useIndex < callIndex; ++useIndex) {
            const uint32_t use = words[useIndex];
            if (Tier2IsLDRXUnsigned(use) &&
                Tier2RegisterD(use) == 2 &&
                Tier2RegisterN(use) == valueRegister &&
                ((use >> 10) & 0xfff) == 0) {
                *outSlot = slot;
                return YES;
            }
        }
    }
    return NO;
}

static void Tier2AppendCandidate(Tier2Candidate *candidates,
                                 size_t *candidateCount,
                                 uintptr_t function,
                                 uintptr_t configSlot,
                                 size_t instructionCount) {
    for (size_t index = 0; index < *candidateCount; ++index) {
        if (candidates[index].function == function) return;
    }
    if (*candidateCount < kTier2MaxCandidates) {
        candidates[(*candidateCount)++] =
            (Tier2Candidate){ function, configSlot, instructionCount, 0 };
    }
}

static Tier2Candidate *Tier2DiscoverGate(const Tier2ImageLayout *layout) {
    const uint32_t *words = (const uint32_t *)layout->text;
    const size_t wordCount = layout->textSize / sizeof(uint32_t);

    uintptr_t rawSelrefs[kTier2MaxRawSelrefs];
    size_t rawSelrefCount = 0;
    for (uintptr_t address = layout->selrefs;
         address + sizeof(uintptr_t) <= layout->selrefs + layout->selrefsSize;
         address += sizeof(uintptr_t)) {
        if (Tier2RawGetterSelref(address) && rawSelrefCount < kTier2MaxRawSelrefs) {
            rawSelrefs[rawSelrefCount++] = address;
        }
    }
    if (rawSelrefCount == 0) return NULL;

    Tier2Candidate candidates[kTier2MaxCandidates];
    size_t candidateCount = 0;
    for (size_t index = 0; index + 8 < wordCount; ++index) {
        const uint32_t adrp = words[index];
        const uint32_t selectorLdr = words[index + 1];
        if (!Tier2IsADRP(adrp) || !Tier2IsLDRXUnsigned(selectorLdr) ||
            Tier2RegisterN(selectorLdr) != Tier2RegisterD(adrp) ||
            Tier2RegisterD(selectorLdr) != 1) {
            continue;
        }

        const uintptr_t selectorPage = Tier2DecodeADRP(adrp, layout->text + index * 4);
        const uintptr_t selectorRef = Tier2LDRTarget(selectorPage, selectorLdr);
        if (!Tier2IsKnownRawGetterSelref(rawSelrefs, rawSelrefCount, selectorRef)) {
            continue;
        }

        size_t callIndex = 0;
        for (size_t probe = index + 2; probe <= index + 8; ++probe) {
            if (Tier2IsBL(words[probe])) {
                callIndex = probe;
                break;
            }
        }
        if (callIndex == 0) continue;

        uintptr_t configSlot = 0;
        if (!Tier2ConfigSlotBeforeCall(words, layout->text, index, callIndex,
                                       layout, &configSlot)) {
            continue;
        }

        const size_t start = Tier2PreviousFunctionStart(words, index);
        const size_t end = Tier2NextFunctionEnd(words, wordCount, index);
        if (end == 0 || end <= start) continue;
        const size_t instructionCount = end - start;
        if (instructionCount > kTier2MaxLeafArm64Instructions ||
            Tier2HasConditionalBranch(words, start, end)) {
            continue;
        }

        Tier2AppendCandidate(candidates, &candidateCount,
                             layout->text + start * 4,
                             configSlot, instructionCount);
    }

    Tier2Candidate *winner = NULL;
    for (size_t index = 0; index < candidateCount; ++index) {
        candidates[index].dispatchFanIn =
            Tier2CountDispatchReferences(layout, candidates[index].function);
        if (candidates[index].dispatchFanIn == 0) continue;
        if (winner == NULL ||
            candidates[index].dispatchFanIn > winner->dispatchFanIn ||
            (candidates[index].dispatchFanIn == winner->dispatchFanIn &&
             candidates[index].instructionCount < winner->instructionCount)) {
            winner = &candidates[index];
        }
    }

    if (winner == NULL) return NULL;
    static Tier2Candidate selected;
    selected = *winner;
    return &selected;
}

static BOOL Tier2ReadTargetConfigWord(uintptr_t configSlot, uint64_t *outWord) {
    const uintptr_t descriptor =
        Tier2StripPointer(*(const uintptr_t *)configSlot);
    if (descriptor == 0 || (descriptor & (sizeof(uint64_t) - 1)) != 0) return NO;

    const uint64_t value = *(const uint64_t *)descriptor;
    if (value == 0) return NO;
    *outWord = value;
    return YES;
}

static Tier2RawGetterIMP Tier2OriginalGetterForReceiver(id receiver) {
    for (Class cls = object_getClass(receiver);
         cls != Nil;
         cls = class_getSuperclass(cls)) {
        for (size_t index = 0; index < gTier2GetterHookCount; ++index) {
            if (gTier2GetterHooks[index].cls == cls) {
                return gTier2GetterHooks[index].original;
            }
        }
    }
    return NULL;
}

static BOOL Tier2RawGetterReplacement(id receiver,
                                      SEL selector,
                                      uint64_t configWord,
                                      id options) {
    const Tier2RawGetterIMP original = Tier2OriginalGetterForReceiver(receiver);
    if (original == NULL) return NO; /* fail closed on an unproven runtime ABI */
    if (gTier2Enabled &&
        gTier2TargetConfigWord != 0 &&
        configWord == gTier2TargetConfigWord) {
        return YES;
    }
    return original(receiver, selector, configWord, options);
}

static BOOL Tier2MethodHasExpectedRawGetterABI(Method method) {
    if (method_getNumberOfArguments(method) != 4) return NO;
    char returnType[16] = { 0 };
    method_getReturnType(method, returnType, sizeof(returnType));
    /* Objective-C BOOL may be B, c, or C depending on its producer. */
    return returnType[0] == 'B' || returnType[0] == 'c' || returnType[0] == 'C';
}

static size_t Tier2InstallRawGetterHooks(Tier2MessageHooker hooker) {
    const SEL rawGetter = sel_registerName("getBool:withOptions:");
    const int classCapacity = objc_getClassList(NULL, 0);
    if (classCapacity <= 0) return 0;

    Class *classes = (Class *)calloc((size_t)classCapacity, sizeof(Class));
    if (classes == NULL) return 0;
    const int reportedClassCount = objc_getClassList(classes, classCapacity);
    const int classCount = reportedClassCount < classCapacity
        ? reportedClassCount
        : classCapacity;

    for (int classIndex = 0;
         classIndex < classCount && gTier2GetterHookCount < kTier2MaxGetterHooks;
         ++classIndex) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(classes[classIndex], &methodCount);
        if (methods == NULL) continue;

        for (unsigned int methodIndex = 0;
             methodIndex < methodCount && gTier2GetterHookCount < kTier2MaxGetterHooks;
             ++methodIndex) {
            Method method = methods[methodIndex];
            if (method_getName(method) != rawGetter ||
                !Tier2MethodHasExpectedRawGetterABI(method)) {
                continue;
            }

            const size_t slot = gTier2GetterHookCount++;
            gTier2GetterHooks[slot].cls = classes[classIndex];
            gTier2GetterHooks[slot].original =
                (Tier2RawGetterIMP)method_getImplementation(method);

            IMP signedOriginal = NULL;
            hooker(classes[classIndex], rawGetter,
                   (IMP)Tier2RawGetterReplacement, &signedOriginal);
            /* ElleKit returns a callable PAC-correct original on arm64e. */
            if (signedOriginal != NULL) {
                gTier2GetterHooks[slot].original = (Tier2RawGetterIMP)signedOriginal;
            }
        }
        free(methods);
    }
    free(classes);
    return gTier2GetterHookCount;
}

static const struct mach_header_64 *Tier2MainImage(intptr_t *outSlide) {
    for (uint32_t index = 0; index < _dyld_image_count(); ++index) {
        const struct mach_header *header = _dyld_get_image_header(index);
        if (header != NULL && header->magic == MH_MAGIC_64 &&
            header->filetype == MH_EXECUTE) {
            *outSlide = _dyld_get_image_vmaddr_slide(index);
            return (const struct mach_header_64 *)header;
        }
    }
    return NULL;
}

static void Tier2InstallIfPossible(void) {
    if (gTier2Installed || gTier2Installing) return;
    gTier2Installing = YES;

    intptr_t mainSlide = 0;
    const struct mach_header_64 *mainHeader = Tier2MainImage(&mainSlide);
    if (mainHeader == NULL) {
        NSLog(@"[SCITier2] main executable unavailable; no hook installed");
        gTier2Installing = NO;
        return;
    }

    Tier2ImageLayout layout;
    if (!Tier2BuildImageLayout(mainHeader, mainSlide, &layout)) {
        NSLog(@"[SCITier2] required Mach-O sections absent; no hook installed");
        gTier2Installing = NO;
        return;
    }

    Tier2Candidate *gate = Tier2DiscoverGate(&layout);
    uint64_t targetConfigWord = 0;
    if (gate == NULL ||
        !Tier2ReadTargetConfigWord(gate->configSlot, &targetConfigWord)) {
        NSLog(@"[SCITier2] no verified structural gate; no hook installed");
        gTier2Installing = NO;
        return;
    }

    /* Avoid a hard link or an unsafe fallback if ElleKit is absent. */
    const Tier2MessageHooker messageHook =
        (Tier2MessageHooker)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (messageHook == NULL) {
        NSLog(@"[SCITier2] MSHookMessageEx unavailable; no hook installed");
        gTier2Installing = NO;
        return;
    }

    gTier2TargetConfigWord = targetConfigWord;
    const size_t hookCount = Tier2InstallRawGetterHooks(messageHook);
    if (hookCount == 0) {
        gTier2TargetConfigWord = 0;
        NSLog(@"[SCITier2] raw getter ABI was not found; no hook installed");
        gTier2Installing = NO;
        return;
    }

    gTier2Installed = YES;
    gTier2Installing = NO;
    NSLog(@"[SCITier2] installed %zu signed message hook(s); leaf=%p, instructions=%zu, fan-in=%zu",
          hookCount, (void *)gate->function,
          gate->instructionCount, gate->dispatchFanIn);
}

__attribute__((constructor))
static void SCITier2EmployeeGateBootstrap(void) {
    @autoreleasepool {
        gTier2Enabled = [SCIUtils getBoolPref:@"sci_tier2_employee_internal"];
        if (gTier2Enabled) Tier2ScheduleInstall();
    }
}
