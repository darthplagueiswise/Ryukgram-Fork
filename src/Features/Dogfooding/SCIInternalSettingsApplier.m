#import "SCIInternalSettingsApplier.h"
#import "SCIDogfoodObjectRuntime.h"
#import "SCIInternalGatePrefs.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

#define APLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Applier " fmt,##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs objCGateEnabledForKey:k]; }

@implementation SCIInternalSettingsApplier

// THE KEY FIX: [session autofillInternalSettings] returns a cached instance whose
// sessionUserDefaults ivar is nil (confirmed via FLEX). Writing to it does nothing.
// [[IGAutofillInternalSettings alloc] initWithUserSession:session] creates a fresh
// instance that properly populates sessionUserDefaults, so setters actually persist.
+ (id)autofillInternalSettingsForSession:(id)session {
    if (!session) return nil;
    Class C = NSClassFromString(@"IGAutofillInternalSettings");
    if (!C) C = NSClassFromString(@"_TtC33AutofillInternalSettingsInstagram26IGAutofillInternalSettings");
    if (C) {
        SEL iwus = NSSelectorFromString(@"initWithUserSession:");
        id obj = [C alloc];
        if (obj && [obj respondsToSelector:iwus]) {
            id ais = nil;
            @try { ais = ((id(*)(id,SEL,id))objc_msgSend)(obj, iwus, session); }
            @catch (id e) { APLOG("initWithUserSession: threw: %{public}@", e); }
            if (ais) {
                id sud = nil;
                @try { sud = [ais valueForKey:@"sessionUserDefaults"]; } @catch (__unused id e) {}
                APLOG("ais=ok sessionUserDefaults=%{public}s", sud ? "populated" : "nil");
                if (!sud) {
                    // sessionUserDefaults still nil — try the session property as last resort
                    SEL sp = NSSelectorFromString(@"autofillInternalSettings");
                    if ([session respondsToSelector:sp]) {
                        @try { ais = ((id(*)(id,SEL))objc_msgSend)(session, sp); }
                        @catch (__unused id e) {}
                    }
                }
                return ais;
            }
        }
    }
    // Final fallback: session property
    SEL s = NSSelectorFromString(@"autofillInternalSettings");
    if ([session respondsToSelector:s]) {
        @try { return ((id(*)(id,SEL))objc_msgSend)(session, s); } @catch (__unused id e) {}
    }
    return nil;
}

+ (void)callVoid:(id)obj sel:(NSString *)selName {
    if (!obj) return; SEL s = NSSelectorFromString(selName);
    if ([obj respondsToSelector:s]) { @try { ((void(*)(id,SEL))objc_msgSend)(obj, s); } @catch (__unused id e) {} }
}
+ (void)callBool:(id)obj sel:(NSString *)selName value:(BOOL)v {
    if (!obj) return; SEL s = NSSelectorFromString(selName);
    if ([obj respondsToSelector:s]) { @try { ((void(*)(id,SEL,BOOL))objc_msgSend)(obj, s, v); } @catch (__unused id e) {} }
}

+ (NSString *)applyLiquidGlass {
    Class H = NSClassFromString(@"IGLiquidGlassNavigationExperimentHelper");
    if (!H) H = NSClassFromString(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper");
    if (!H) return @"";
    SEL sh = NSSelectorFromString(@"shared");
    id shared = [H respondsToSelector:sh] ? ((id(*)(id,SEL))objc_msgSend)(H, sh) : nil;
    if (!shared) return @"";
    [self callBool:shared sel:@"overrideIsEnabled:" value:YES];
    [self callBool:shared sel:@"overrideIsGlassRenderingOptimizationEnabled:" value:YES];
    [self callBool:shared sel:@"overrideLegibilityBlurEnabled:" value:YES];
    return @"LiquidGlass=ON; ";
}

+ (NSString *)applyNow {
    NSMutableString *out = [NSMutableString string];
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) { [out appendString:@"no session — open after login"]; goto done; }
    {
        id ais = [self autofillInternalSettingsForSession:session];
        if (ais) {
            [self callBool:ais sel:@"setDebugFooterEnabledWithEnabled:" value:YES];
            [out appendString:@"debugFooter=ON; "];
            if (ON(@"sci_apply_force_bloks"))    { [self callVoid:ais sel:@"setForceBloksExperienceOn"]; [out appendString:@"bloks=ON; "]; }
            if (ON(@"sci_apply_bloks_prefetch"))  { [self callBool:ais sel:@"setBloksPrefetchEnabledWithEnabled:" value:YES]; [out appendString:@"prefetch=ON; "]; }
        } else {
            [out appendString:@"autofillInternalSettings unavailable; "];
        }
    }
    if (ON(@"sci_apply_liquidglass")) [out appendString:[self applyLiquidGlass]];
done:
    [SCIDogfoodObjectRuntime noteAction:@"applyInternalSettingsNative"
                                 status:(session ? @"ok" : @"no-session") detail:out];
    APLOG("applyNow: %{public}@", out);
    return out.length ? out : @"nothing applied";
}

+ (void)scheduleAutoApplyIfEnabled {
    if (!ON(@"sci_apply_internal_native")) return;
    double d[] = {4.0, 8.0, 16.0};
    for (NSUInteger i = 0; i < 3; i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(d[i]*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if ([SCIDogfoodObjectRuntime activeUserSession]) [SCIInternalSettingsApplier applyNow];
        });
}
@end
