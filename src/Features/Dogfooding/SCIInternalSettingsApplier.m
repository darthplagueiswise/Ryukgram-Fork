#import "SCIInternalSettingsApplier.h"
#import "SCIDogfoodObjectRuntime.h"
#import "SCIInternalGatePrefs.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

#define APLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] Applier " fmt, ##__VA_ARGS__)
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs objCGateEnabledForKey:k]; }

@implementation SCIInternalSettingsApplier

// Resolve the live IGAutofillInternalSettings from the captured session.
+ (id)autofillInternalSettings {
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) return nil;
    SEL s = NSSelectorFromString(@"autofillInternalSettings");
    if ([session respondsToSelector:s]) {
        id ais = ((id(*)(id,SEL))objc_msgSend)(session, s);
        if (ais) return ais;
    }
    // Fallback: construct one bound to the session.
    Class C = NSClassFromString(@"AutofillInternalSettingsInstagram.IGAutofillInternalSettings");
    if (!C) C = NSClassFromString(@"IGAutofillInternalSettings");
    if (!C) C = NSClassFromString(@"_TtC33AutofillInternalSettingsInstagram26IGAutofillInternalSettings");
    if (C) {
        SEL iwus = NSSelectorFromString(@"initWithUserSession:");
        id obj = [C alloc];
        if ([obj respondsToSelector:iwus])
            return ((id(*)(id,SEL,id))objc_msgSend)(obj, iwus, session);
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
    Class H = NSClassFromString(@"IGLiquidGlassExperimentHelper.IGLiquidGlassNavigationExperimentHelper");
    if (!H) H = NSClassFromString(@"IGLiquidGlassNavigationExperimentHelper");
    if (!H) H = NSClassFromString(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper");
    if (!H) return @"";
    SEL sharedSel = NSSelectorFromString(@"shared");
    id shared = [H respondsToSelector:sharedSel] ? ((id(*)(id,SEL))objc_msgSend)(H, sharedSel) : nil;
    if (!shared) return @"";
    BOOL on = YES; // override to enabled
    [self callBool:shared sel:@"overrideIsEnabled:" value:on];
    [self callBool:shared sel:@"overrideIsGlassRenderingOptimizationEnabled:" value:on];
    [self callBool:shared sel:@"overrideLegibilityBlurEnabled:" value:on];
    return @"LiquidGlass override; ";
}

+ (NSString *)applyNow {
    NSMutableString *out = [NSMutableString string];
    id ais = [self autofillInternalSettings];
    if (ais) {
        // Debug footer is the gateway to the internal/debug menus.
        [self callBool:ais sel:@"setDebugFooterEnabledWithEnabled:" value:YES];
        [out appendString:@"debugFooter=ON; "];
        if (ON(@"sci_apply_force_bloks")) { [self callVoid:ais sel:@"setForceBloksExperienceOn"]; [out appendString:@"bloksExp=ON; "]; }
        if (ON(@"sci_apply_bloks_prefetch")) { [self callBool:ais sel:@"setBloksPrefetchEnabledWithEnabled:" value:YES]; [out appendString:@"bloksPrefetch=ON; "]; }
    } else {
        [out appendString:@"no live session/autofillInternalSettings yet; "];
    }
    if (ON(@"sci_apply_liquidglass")) [out appendString:[self applyLiquidGlass]];
    APLOG("applyNow: %{public}@", out);
    [SCIDogfoodObjectRuntime noteAction:@"applyInternalSettingsNative" status:(ais?@"ok":@"no-session") detail:out];
    return out.length ? out : @"nothing applied";
}

+ (void)scheduleAutoApplyIfEnabled {
    if (!ON(@"sci_apply_internal_native")) return;
    // Session only exists post-login; retry a few times off the main thread cadence.
    double delays[] = {4.0, 8.0, 14.0};
    for (NSUInteger i=0;i<sizeof(delays)/sizeof(delays[0]);i++){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delays[i]*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([SCIDogfoodObjectRuntime activeUserSession]) [SCIInternalSettingsApplier applyNow];
        });
    }
}
@end
