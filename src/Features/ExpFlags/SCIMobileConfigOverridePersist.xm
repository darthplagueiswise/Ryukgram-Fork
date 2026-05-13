#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>

//
// SCIMobileConfigOverridePersist.xm  (dev2)
//
// PROBLEMA:
//   O menu nativo de dogfooding abre corretamente mas as selees NO persistem
//   porque o menu executa caminhos que requerem um userSession autenticado com
//   permisses de dogfooder. Sem isso, os writes na tabela de overrides no
//   passam pela validao de permisso.
//
// SOLUO:
//   Usar as funes C++ exportadas do FBSharedFramework para escrever
//   diretamente na tabela de overrides  bypassando a validao de permisso.
//   Estas funes so chamveis via dlsym, no requerem hook, no tocam __TEXT.
//
// FUNES VERIFICADAS (lief scan FBSharedFramework arm64):
//
//   updateOverrideForParam(uint64 specifier, bool value, bool persist)
//    __ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb @ 0xd75c2c
//
//   removeOverrideForParam(uint64 specifier, bool persist)
//    __ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb @ 0xd75d14
//
//   FBMobileConfigManager::getOrCreateOverridesTable(bool create)
//    __ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb @ 0x29063c
//
//   paramKeyFromSpecifier(uint64 specifier) -> NSString*
//    __ZN12mobileconfig21paramKeyFromSpecifierEy @ 0xb555ac
//
//   getBoolDefault(uint64 specifier) -> bool
//    __ZN12mobileconfig14getBoolDefaultEy @ 0xba1f10
//
//   _IGMobileConfigSetConfigOverrides (ObjC-callable C wrapper)
//    @ 0x11cd8bc in FBSharedFramework
//
// ObjC PONTE (confirmada no binrio):
//   IGMobileConfigContextManager:
//     -setOverrideForParam:andValue:
//     -removeOverrideForParam:
//     -getOverridesTablePath
//     +getCurrentManager               (Flex IMG_6733)
//
// FLEX IMG_6744  specifiers vivos capturados:
//   oriSpecifier:              535083930726957056 = 0x076d000000000000
//   stableTranslatedSpecifier: 535084209939152898 = 0x076d004102580002
//   appUpgrade:                279212195842       = 0x0000004102580002
//
// SPECIFIERS CONHECIDOS (anlise esttica + FBSharedFramework binary):
//   0x00810749002926c6  media/feed rendering
//   0x00810749002e26cb  media/feed rendering
//   0x0081037300010d36  UI/style
//   0x0081141f00006271  UI/style
//   0x00810c190000439a  media/feed rendering
//   0x008107150001251e  media/feed rendering
//   0x00410adf00053dac  cache/sessionless
//   0x008106a9014f20b7  delivery flags
//   0x00810749002526c4  feed item mutation
//   0x00810e1e00004e06  video state
//   0x00410adf00083dad  UK/EU pricing
//   0x0041094200003249  stash/experiments (DirectNotes dogfooding candidates)
//   0x004109420005324a  stash/experiments
//   0x004109420006324b  stash/experiments
//   0x008106a600231faf  stash/experiments (sessioned)
//
//

//  C++ function typedefs

// FBMobileConfigOverridesTable* getOrCreateOverridesTable(bool create)
// Returns a raw pointer to the C++ OverridesTable on the manager.
// 'this' pointer of FBMobileConfigManager is obtained via +getCurrentManager.
typedef void *(*RGGetOrCreateOverridesTableFn)(void *managerThis, BOOL create);

// void updateOverrideForParam(uint64_t specifier, bool value, bool persist)
// 'this' = FBMobileConfigOverridesTable*
typedef void (*RGUpdateOverrideForParamFn)(void *tableThis, uint64_t specifier, BOOL value, BOOL persist);

// void removeOverrideForParam(uint64_t specifier, bool persist)
typedef void (*RGRemoveOverrideForParamFn)(void *tableThis, uint64_t specifier, BOOL persist);

// NSString* paramKeyFromSpecifier(uint64_t specifier)
typedef NSString *(*RGParamKeyFromSpecifierFn)(uint64_t specifier);

// bool getBoolDefault(uint64_t specifier)
typedef BOOL (*RGGetBoolDefaultFn)(uint64_t specifier);

//  Resolved function pointers
static RGGetOrCreateOverridesTableFn gGetOrCreateOverridesTable = NULL;
static RGUpdateOverrideForParamFn    gUpdateOverrideForParam    = NULL;
static RGRemoveOverrideForParamFn    gRemoveOverrideForParam    = NULL;
static RGParamKeyFromSpecifierFn     gParamKeyFromSpecifier     = NULL;
static RGGetBoolDefaultFn            gGetBoolDefault            = NULL;

static BOOL gFunctionsResolved = NO;
static BOOL gFunctionsAvailable = NO;

static void RGResolveMCFunctions(void) {
    if (gFunctionsResolved) return;
    gFunctionsResolved = YES;

    // Each symbol is verified  in FBSharedFramework export table (lief scan)
    struct {
        const char *sym;
        void **out;
    } symbols[] = {
        {
            "__ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb",
            (void **)&gGetOrCreateOverridesTable
        },
        {
            "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb",
            (void **)&gUpdateOverrideForParam
        },
        {
            "__ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb",
            (void **)&gRemoveOverrideForParam
        },
        {
            "__ZN12mobileconfig21paramKeyFromSpecifierEy",
            (void **)&gParamKeyFromSpecifier
        },
        {
            "__ZN12mobileconfig14getBoolDefaultEy",
            (void **)&gGetBoolDefault
        },
    };

    int resolved = 0;
    for (int i = 0; i < (int)(sizeof(symbols)/sizeof(symbols[0])); i++) {
        void *addr = dlsym(RTLD_DEFAULT, symbols[i].sym);
        if (!addr) {
            // Try without leading underscore (some systems strip it)
            addr = dlsym(RTLD_DEFAULT, symbols[i].sym + 1);
        }
        if (addr) {
            *symbols[i].out = addr;
            resolved++;
        }
        NSLog(@"[RyukGram][MCOverride] %s: %s @ %p",
              resolved > i ? "" : "",
              symbols[i].sym + 40, // truncate for readability
              addr);
    }

    gFunctionsAvailable = (gGetOrCreateOverridesTable != NULL && gUpdateOverrideForParam != NULL);
    NSLog(@"[RyukGram][MCOverride] resolved %d/%lu functions, available=%d",
          resolved, sizeof(symbols)/sizeof(symbols[0]), gFunctionsAvailable);
}

//  Get the FBMobileConfigManager C++ this-pointer
// Uses ObjC bridge: +[IGMobileConfigContextManager getCurrentManager]
// which returns the manager as a raw pointer (from Flex IMG_6733 confirmed).
// The manager's _configManager ivar is shared_ptr<FBMobileConfigManager>.
static void *RGGetConfigManagerCppPtr(void) {
    // IGMobileConfigContextManager is confirmed  in binary
    Class ctxMgr = NSClassFromString(@"IGMobileConfigContextManager");
    if (!ctxMgr) return NULL;

    SEL getCurrentMgrSel = NSSelectorFromString(@"getCurrentManager");
    if (!class_getClassMethod(ctxMgr, getCurrentMgrSel)) return NULL;

    // Returns the ObjC wrapper
    id objcWrapper = ((id (*)(id, SEL))objc_msgSend)((id)ctxMgr, getCurrentMgrSel);
    if (!objcWrapper) return NULL;

    // Extract _configManager ivar  it's a shared_ptr<FBMobileConfigManager>
    // The shared_ptr stores the raw pointer at offset 0 of the struct
    Ivar configMgrIvar = class_getInstanceVariable([objcWrapper class], "_configManager");
    if (!configMgrIvar) {
        // Try parent class
        Class cls = [objcWrapper class];
        while (cls && !configMgrIvar) {
            configMgrIvar = class_getInstanceVariable(cls, "_configManager");
            cls = class_getSuperclass(cls);
        }
    }
    if (!configMgrIvar) return NULL;

    // The ivar is shared_ptr<FBMobileConfigManager>  first word is the raw ptr
    ptrdiff_t ivarOffset = ivar_getOffset(configMgrIvar);
    void **ivarPtr = (void **)((uint8_t *)(__bridge void *)objcWrapper + ivarOffset);
    void *rawPtr = *ivarPtr; // dereference shared_ptr to get the FBMobileConfigManager*

    return rawPtr;
}

//  ObjC bridge path (fallback, simpler)
// Uses -setOverrideForParam:andValue: on the context manager
// which is confirmed  in binary and is the ObjC-safe path.
static BOOL RGSetOverrideViaObjC(uint64_t specifier, BOOL value) {
    Class ctxMgr = NSClassFromString(@"IGMobileConfigContextManager");
    if (!ctxMgr) return NO;

    SEL getSel = NSSelectorFromString(@"getCurrentManager");
    if (!class_getClassMethod(ctxMgr, getSel)) return NO;

    id manager = ((id (*)(id, SEL))objc_msgSend)((id)ctxMgr, getSel);
    if (!manager) return NO;

    SEL setOverrideSel = NSSelectorFromString(@"setOverrideForParam:andValue:");
    if (![manager respondsToSelector:setOverrideSel]) return NO;

    @try {
        // setOverrideForParam:andValue:  param is NSUInteger (specifier), value is BOOL (NSNumber or direct)
        // Type encoding: v@:Q@ (void, self, SEL, uint64, id) or v@:QB (void, self, SEL, uint64, BOOL)
        // We pass @(value) as NSNumber to be safe
        ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(
            manager,
            setOverrideSel,
            (NSUInteger)specifier,
            @(value));
        return YES;
    } @catch (id ex) {
        NSLog(@"[RyukGram][MCOverride] setOverrideForParam exception: %@", ex);
        return NO;
    }
}

static BOOL RGRemoveOverrideViaObjC(uint64_t specifier) {
    Class ctxMgr = NSClassFromString(@"IGMobileConfigContextManager");
    if (!ctxMgr) return NO;
    SEL getSel = NSSelectorFromString(@"getCurrentManager");
    id manager = [[ctxMgr class] respondsToSelector:getSel] ?
        ((id (*)(id, SEL))objc_msgSend)((id)ctxMgr, getSel) : nil;
    if (!manager) return NO;
    SEL remSel = NSSelectorFromString(@"removeOverrideForParam:");
    if (![manager respondsToSelector:remSel]) return NO;
    @try {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(manager, remSel, (NSUInteger)specifier);
        return YES;
    } @catch (id ex) { return NO; }
}

//  Public API
#ifdef __cplusplus
extern "C" {
#endif

// Set a boolean override on a specifier. persist=YES writes to disk.
// Uses C++ path (direct, no ObjC overhead) with ObjC fallback.
// Returns YES if either path succeeded.
BOOL SCIMCSetBoolOverride(uint64_t specifier, BOOL value, BOOL persist) {
    RGResolveMCFunctions();

    // Primary: C++ path via getOrCreateOverridesTable + updateOverrideForParam
    if (gFunctionsAvailable) {
        void *managerPtr = RGGetConfigManagerCppPtr();
        if (managerPtr) {
            void *overridesTable = gGetOrCreateOverridesTable(managerPtr, YES);
            if (overridesTable) {
                @try {
                    gUpdateOverrideForParam(overridesTable, specifier, value, persist);
                    NSLog(@"[RyukGram][MCOverride] C++ set 0x%016llx=%d persist=%d ",
                          (unsigned long long)specifier, value, persist);
                    return YES;
                } @catch (id ex) {
                    NSLog(@"[RyukGram][MCOverride] C++ exception: %@, trying ObjC fallback", ex);
                }
            }
        }
    }

    // Fallback: ObjC bridge
    BOOL ok = RGSetOverrideViaObjC(specifier, value);
    NSLog(@"[RyukGram][MCOverride] ObjC fallback 0x%016llx=%d: %@",
          (unsigned long long)specifier, value, ok ? @"" : @"");
    return ok;
}

// Remove a boolean override. Returns YES if succeeded.
BOOL SCIMCRemoveOverride(uint64_t specifier, BOOL persist) {
    RGResolveMCFunctions();

    if (gFunctionsAvailable) {
        void *managerPtr = RGGetConfigManagerCppPtr();
        if (managerPtr) {
            void *overridesTable = gGetOrCreateOverridesTable(managerPtr, NO);
            if (overridesTable) {
                @try {
                    gRemoveOverrideForParam(overridesTable, specifier, persist);
                    return YES;
                } @catch (id ex) {}
            }
        }
    }
    return RGRemoveOverrideViaObjC(specifier);
}

// Resolve specifier  human name. Returns nil if not resolvable.
// Requires configs to have been loaded (app must have reached feed first).
NSString *SCIMCParamName(uint64_t specifier) {
    RGResolveMCFunctions();
    if (!gParamKeyFromSpecifier) return nil;
    @try {
        return gParamKeyFromSpecifier(specifier);
    } @catch (id ex) { return nil; }
}

// Get the default bool value for a specifier (from the loaded config).
BOOL SCIMCBoolDefault(uint64_t specifier) {
    RGResolveMCFunctions();
    if (!gGetBoolDefault) return NO;
    @try {
        return gGetBoolDefault(specifier);
    } @catch (id ex) { return NO; }
}

// Set multiple overrides at once from a dictionary of specifier_hex_string -> @YES/@NO
BOOL SCIMCSetBoolOverrides(NSDictionary<NSString *, NSNumber *> *specifierToValue, BOOL persist) {
    if (!specifierToValue.count) return NO;
    int ok = 0;
    for (NSString *hexKey in specifierToValue) {
        uint64_t spec = strtoull(hexKey.UTF8String, NULL, 16);
        if (!spec) continue;
        BOOL val = [specifierToValue[hexKey] boolValue];
        if (SCIMCSetBoolOverride(spec, val, persist)) ok++;
    }
    return ok > 0;
}

// Get all confirmed specifiers from binary analysis (static list)
NSDictionary<NSString *, NSString *> *SCIMCKnownSpecifiers(void) {
    return @{
        @"0x00810749002926c6": @"media/feed rendering [IGMediaTakenAtDate]",
        @"0x00810749002e26cb": @"media/feed rendering [IGMediaTakenAtDate+2]",
        @"0x0081037300010d36": @"UI/style [colorFromHexString]",
        @"0x0081141f00006271": @"UI/style [IGStringStyleBoldGray]",
        @"0x00810c190000439a": @"media/feed rendering [IGMediaSizeForViewWidth]",
        @"0x008107150001251e": @"media/feed rendering [IGMediaIsEligibleTallerContainer]",
        @"0x00410adf00053dac": @"cache/sessionless [IGCache containsKey]",
        @"0x008106a9014f20b7": @"delivery flags [IGDeliveryFieldsDeliveryFlags]",
        @"0x00810749002526c4": @"feed item mutation [IGFeedItemChangeForLike]",
        @"0x00810e1e00004e06": @"video state [IGVideoIsApplicationBackgrounded]",
        @"0x00810e1e00014e07": @"video state [IGVideoIsApplicationBackgrounded+2]",
        @"0x00410adf00083dad": @"UK/EU pricing [isUKEUProductPricingCompliant]",
        @"0x0041094200003249": @"stash/experiments [IGStashSetExperimentsValues]",
        @"0x004109420005324a": @"stash/experiments [IGStashSetExperimentsValues+2]",
        @"0x004109420006324b": @"stash/experiments [IGStashSetExperimentsValues+3]",
        @"0x008106a600231faf": @"stash/experiments sessioned [IGStashSetExperimentsValues+4]",
        // Live specifiers from Flex IMG_6744
        @"0x076d000000000000": @"[live] oriSpecifier from Flex screenshot",
        @"0x076d004102580002": @"[live] stableTranslatedSpecifier from Flex screenshot",
        @"0x0000004102580002": @"[live] appUpgradeTranslatedSpecifier from Flex screenshot",
    };
}

// Diagnostic: returns info about the resolve status and override table
NSDictionary<NSString *, id> *SCIMCOverrideDiagnostics(void) {
    RGResolveMCFunctions();
    void *managerPtr = RGGetConfigManagerCppPtr();
    void *overridesTable = (managerPtr && gGetOrCreateOverridesTable)
        ? gGetOrCreateOverridesTable(managerPtr, NO) : NULL;

    return @{
        @"functions_resolved"          : @(gFunctionsResolved),
        @"functions_available"         : @(gFunctionsAvailable),
        @"getOrCreateOverridesTable"   : @(gGetOrCreateOverridesTable != NULL),
        @"updateOverrideForParam"      : @(gUpdateOverrideForParam != NULL),
        @"removeOverrideForParam"      : @(gRemoveOverrideForParam != NULL),
        @"paramKeyFromSpecifier"       : @(gParamKeyFromSpecifier != NULL),
        @"getBoolDefault"              : @(gGetBoolDefault != NULL),
        @"manager_cpp_ptr"             : managerPtr ? [NSString stringWithFormat:@"%p", managerPtr] : @"nil",
        @"overrides_table_ptr"         : overridesTable ? [NSString stringWithFormat:@"%p", overridesTable] : @"nil",
        @"objc_bridge_available"       : @(NSClassFromString(@"IGMobileConfigContextManager") != nil),
    };
}

#ifdef __cplusplus
}
#endif

//  Constructor
// Inert: only resolves function pointers for fast first-call.
// No hooks, no timers, no observers.
__attribute__((constructor))
static void RGMCOverridePersistInit(void) {
    @autoreleasepool {
        // Resolve on a background queue so we don't block the launch thread.
        // The functions are in the shared library which is already loaded.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            RGResolveMCFunctions();
        });
    }
}
