#import "SCIInternalActions.h"
#import "SCIEmployeeDefaults.h"
#import "SCIDogfoodObjectRuntime.h"
#import "../../Utils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static NSString *const kSCIForceEmployeeKey = @"sci_force_ig_internal_employee";

void SCIInstallEmployeeInternalHooksIfNeeded(void);
void SCIRefreshGraphQLDogfoodForceEnabled(void);
void SCIInstallGraphQLDogfoodForceHooksIfNeeded(void);

static NSError *SCIErr(NSString *msg) {
    return [NSError errorWithDomain:@"SCIInternalActions"
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey: msg ?: @"unknown"}];
}

static NSString *SCIClassName(id obj) {
    return obj ? (NSStringFromClass(object_getClass(obj)) ?: @"") : @"";
}

static NSString *SCIAddr(id obj) {
    return obj ? [NSString stringWithFormat:@"%p", obj] : @"";
}

static Class SCIFindClass(NSString *needle) {
    if (!needle.length) return Nil;
    Class direct = NSClassFromString(needle);
    if (direct) return direct;

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    Class found = Nil;
    const char *needleC = needle.UTF8String;
    for (unsigned int i = 0; classes && i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (name && strstr(name, needleC)) {
            found = classes[i];
            break;
        }
    }
    if (classes) free(classes);
    return found;
}

static id SCIObjectIvarNamed(id obj, NSString *name) {
    if (!obj || !name.length) return nil;
    for (Class cls = object_getClass(obj); cls; cls = class_getSuperclass(cls)) {
        Ivar iv = class_getInstanceVariable(cls, name.UTF8String);
        if (!iv) continue;
        const char *type = ivar_getTypeEncoding(iv);
        if (!type || type[0] != '@') return nil;
        @try { return object_getIvar(obj, iv); } @catch (__unused id ex) { return nil; }
    }
    return nil;
}

static id SCIObjectViaSelector(id obj, SEL sel) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, sel); } @catch (__unused id ex) { return nil; }
}

static BOOL SCIBoolViaSelector(id obj, SEL sel, BOOL fallback) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) return fallback;
    @try { return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel); } @catch (__unused id ex) { return fallback; }
}

static BOOL SCICallVoid0(id obj, SEL sel, NSError **error) {
    if (!obj) {
        if (error) *error = SCIErr(@"No IGAutofillInternalSettings object resolved from the live IGUserSession.");
        return NO;
    }
    if (![obj respondsToSelector:sel]) {
        if (error) *error = SCIErr([NSString stringWithFormat:@"%@ not present on %@", NSStringFromSelector(sel), SCIClassName(obj)]);
        return NO;
    }
    @try {
        ((void (*)(id, SEL))objc_msgSend)(obj, sel);
        [SCIDogfoodObjectRuntime noteAction:NSStringFromSelector(sel) status:@"sent" detail:obj];
        return YES;
    } @catch (id ex) {
        if (error) *error = SCIErr([NSString stringWithFormat:@"%@ threw: %@", NSStringFromSelector(sel), ex]);
        [SCIDogfoodObjectRuntime noteAction:NSStringFromSelector(sel) status:@"exception" detail:ex];
        return NO;
    }
}

static BOOL SCICallVoidBool(id obj, SEL sel, BOOL value, NSError **error) {
    if (!obj) {
        if (error) *error = SCIErr(@"No IGAutofillInternalSettings object resolved from the live IGUserSession.");
        return NO;
    }
    if (![obj respondsToSelector:sel]) {
        if (error) *error = SCIErr([NSString stringWithFormat:@"%@ not present on %@", NSStringFromSelector(sel), SCIClassName(obj)]);
        return NO;
    }
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
        [SCIDogfoodObjectRuntime noteAction:NSStringFromSelector(sel) status:(value ? @"sent YES" : @"sent NO") detail:obj];
        return YES;
    } @catch (id ex) {
        if (error) *error = SCIErr([NSString stringWithFormat:@"%@ threw: %@", NSStringFromSelector(sel), ex]);
        [SCIDogfoodObjectRuntime noteAction:NSStringFromSelector(sel) status:@"exception" detail:ex];
        return NO;
    }
}

@implementation SCIInternalActions

+ (nullable id)liveUserSession {
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) session = [SCIDogfoodObjectRuntime liveInstanceOfClassNameContaining:@"IGUserSession"];
    if (!session) session = [SCIDogfoodObjectRuntime liveInstanceOfClassNameContaining:@"FOAUserSession"];

    NSString *className = SCIClassName(session);
    if ([className containsString:@"Provider"]) {
        id provided = SCIObjectViaSelector(session, NSSelectorFromString(@"userSession_DO_NOT_RETAIN"));
        if (!provided) provided = SCIObjectViaSelector(session, NSSelectorFromString(@"userSession"));
        if (!provided) provided = SCIObjectIvarNamed(session, @"_userSession");
        if (provided) session = provided;
    }

    if (session) [SCIDogfoodObjectRuntime noteLiveUserSession:session source:@"SCIInternalActions.liveUserSession"];
    return session;
}

+ (nullable UIViewController *)topPresentedViewController {
    return [SCIDogfoodObjectRuntime topViewController];
}

+ (nullable id)autofillInternalSettings:(out NSError **)error {
    id session = [self liveUserSession];
    if (!session) {
        if (error) *error = SCIErr(@"No live IGUserSession yet. Open any account screen once, then return here.");
        return nil;
    }

    id obj = SCIObjectViaSelector(session, NSSelectorFromString(@"autofillInternalSettings"));
    if (!obj) obj = SCIObjectIvarNamed(session, @"_autofillInternalSettings");
    if (!obj) obj = SCIObjectIvarNamed(session, @"autofillInternalSettings");
    if (obj) {
        [SCIDogfoodObjectRuntime noteObject:obj role:@"AutofillInternalSettings" source:@"IGUserSession.autofillInternalSettings"];
        return obj;
    }

    Class cls = SCIFindClass(@"IGAutofillInternalSettings");
    SEL initSel = NSSelectorFromString(@"initWithUserSession:");
    if (cls && [cls instancesRespondToSelector:initSel]) {
        @try {
            obj = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], initSel, session);
            if (obj) {
                [SCIDogfoodObjectRuntime noteObject:obj role:@"AutofillInternalSettings" source:@"IGAutofillInternalSettings.initWithUserSession:"];
                return obj;
            }
        } @catch (id ex) {
            if (error) *error = SCIErr([NSString stringWithFormat:@"initWithUserSession: threw: %@", ex]);
            return nil;
        }
    }

    if (error) *error = SCIErr(@"Could not resolve IGAutofillInternalSettings from the live IGUserSession.");
    return nil;
}

+ (BOOL)openNotesDogfoodSettings:(out NSError **)error {
    Class cls = SCIFindClass(@"IGDirectNotesDogfoodingSettingsStaticFuncs");
    if (!cls) {
        if (error) *error = SCIErr(@"IGDirectNotesDogfoodingSettingsStaticFuncs not found.");
        return NO;
    }
    SEL sel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (![cls respondsToSelector:sel]) {
        if (error) *error = SCIErr(@"notesDogfoodingSettingsOpenOnViewController:userSession: not present.");
        return NO;
    }
    id session = [self liveUserSession];
    UIViewController *vc = [self topPresentedViewController];
    if (!session) {
        if (error) *error = SCIErr(@"No live IGUserSession yet.");
        return NO;
    }
    if (!vc) {
        if (error) *error = SCIErr(@"Could not resolve top view controller.");
        return NO;
    }
    @try {
        ((void (*)(Class, SEL, id, id))objc_msgSend)(cls, sel, vc, session);
        [SCIDogfoodObjectRuntime noteAction:@"Open Notes Dogfooding" status:@"sent" detail:SCIClassName(session)];
        return YES;
    } @catch (id ex) {
        if (error) *error = SCIErr([NSString stringWithFormat:@"opener threw: %@", ex]);
        [SCIDogfoodObjectRuntime noteAction:@"Open Notes Dogfooding" status:@"exception" detail:ex];
        return NO;
    }
}

+ (NSInteger)bloksForceExperienceState {
    id obj = [self autofillInternalSettings:NULL];
    if (!obj) return 2;
    if (SCIBoolViaSelector(obj, NSSelectorFromString(@"isForceBloksExperienceOn"), NO)) return 1;
    if (SCIBoolViaSelector(obj, NSSelectorFromString(@"isForceBloksExperienceOff"), NO)) return 0;
    return 2;
}

+ (BOOL)setBloksForceExperienceState:(NSInteger)state error:(out NSError **)error {
    id obj = [self autofillInternalSettings:error];
    SEL sel = NULL;
    if (state == 1) sel = NSSelectorFromString(@"setForceBloksExperienceOn");
    else if (state == 0) sel = NSSelectorFromString(@"setForceBloksExperienceOff");
    else sel = NSSelectorFromString(@"clearForceBloksExperience");
    return SCICallVoid0(obj, sel, error);
}

+ (BOOL)bloksPrefetchEnabled {
    return SCIBoolViaSelector([self autofillInternalSettings:NULL], NSSelectorFromString(@"isBloksPrefetchEnabled"), NO);
}

+ (BOOL)setBloksPrefetchEnabled:(BOOL)on error:(out NSError **)error {
    return SCICallVoidBool([self autofillInternalSettings:error], NSSelectorFromString(@"setBloksPrefetchEnabledWithEnabled:"), on, error);
}

+ (BOOL)debugFooterEnabled {
    return SCIBoolViaSelector([self autofillInternalSettings:NULL], NSSelectorFromString(@"getDebugFooterEnabled"), NO);
}

+ (BOOL)setDebugFooterEnabled:(BOOL)on error:(out NSError **)error {
    return SCICallVoidBool([self autofillInternalSettings:error], NSSelectorFromString(@"setDebugFooterEnabledWithEnabled:"), on, error);
}

+ (BOOL)forceInternalEmployeeEnabled {
    return [SCIUtils getBoolPref:kSCIForceEmployeeKey];
}

+ (void)setForceInternalEmployeeEnabled:(BOOL)on {
    [SCIUtils setPref:@(on) forKey:kSCIForceEmployeeKey];
    SCIRefreshGraphQLDogfoodForceEnabled();
    if (on) {
        SCIInstallEmployeeInternalHooksIfNeeded();
        SCIInstallGraphQLDogfoodForceHooksIfNeeded();
    }
}

+ (NSDictionary *)state {
    id session = [self liveUserSession];
    id autofill = [self autofillInternalSettings:NULL];
    id defaults = SCIObjectViaSelector(autofill, NSSelectorFromString(@"sessionUserDefaults"));
    if (!defaults) defaults = SCIObjectIvarNamed(autofill, @"sessionUserDefaults");
    if (!defaults) defaults = SCIObjectIvarNamed(autofill, @"_sessionUserDefaults");
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"activeUserSession"] = session ? [NSString stringWithFormat:@"%@ %@", SCIClassName(session), SCIAddr(session)] : @"nil";
    d[@"autofillInternalSettings"] = autofill ? [NSString stringWithFormat:@"%@ %@", SCIClassName(autofill), SCIAddr(autofill)] : @"nil";
    d[@"sessionUserDefaults"] = defaults ? [NSString stringWithFormat:@"%@ %@", SCIClassName(defaults), SCIAddr(defaults)] : @"nil";
    d[@"bloksForceExperienceState"] = @([self bloksForceExperienceState]);
    d[@"bloksPrefetchEnabled"] = @([self bloksPrefetchEnabled]);
    d[@"debugFooterEnabled"] = @([self debugFooterEnabled]);
    d[@"forceInternalEmployeeEnabled"] = @([self forceInternalEmployeeEnabled]);
    d[@"employeeDefaultsEnabled"] = @([SCIEmployeeDefaults enabled]);
    return d;
}

+ (BOOL)forceBloksExperienceOn { return [self setBloksForceExperienceState:1 error:NULL]; }
+ (BOOL)forceBloksExperienceOff { return [self setBloksForceExperienceState:0 error:NULL]; }
+ (BOOL)setBloksPrefetchEnabled:(BOOL)enabled { return [self setBloksPrefetchEnabled:enabled error:NULL]; }
+ (BOOL)setDebugFooterEnabled:(BOOL)enabled { return [self setDebugFooterEnabled:enabled error:NULL]; }
+ (BOOL)clearForceBloksExperience { return [self setBloksForceExperienceState:2 error:NULL]; }

+ (BOOL)setJsOdNumber:(NSString *)value {
    id obj = [self autofillInternalSettings:NULL];
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(@"setJsOdNumber:")]) return NO;
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(obj, NSSelectorFromString(@"setJsOdNumber:"), value ?: @"");
        [SCIDogfoodObjectRuntime noteAction:@"setJsOdNumber:" status:@"sent" detail:value ?: @""];
        return YES;
    } @catch (id ex) {
        [SCIDogfoodObjectRuntime noteAction:@"setJsOdNumber:" status:@"exception" detail:ex];
        return NO;
    }
}

@end
