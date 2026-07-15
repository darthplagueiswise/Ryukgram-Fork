// SCIExperimentForce.x — ver SCIExperimentForce.h para o desenho.
// Validado contra Instagram/FBSharedFramework build 438.

#import "SCIExperimentForce.h"
#import "../../Utils.h"
#import "../MobileConfig/SCIMobileConfigRuntime.h"
#import "../Dogfooding/SCIInstallOnce.h"
#import <objc/runtime.h>
#import <substrate.h>

// ─────────────────────────────────────────────────────────────────────────────
// G1 — managers unificados: FBCCIGExperimentManager / FBCustomExperimentManager
//      -isFeatureEnabled:(uint64) / -isFeatureEnabledWithoutLogging:(uint64)
//      -getFeatureIntValue:(uint64) / -getFeatureIntValueWithoutLogging:(uint64)
//
// Reutiliza o pipeline de captura + override SELETIVO por ID do
// SCIMobileConfigRuntime. Nunca força YES cego: só devolve override se o usuário
// registrou um pra aquele feature ID específico (mesmo fluxo do MobileConfig
// browser). Com captura desligada e sem override, é passthrough puro.
// ─────────────────────────────────────────────────────────────────────────────

#define DEFINE_EXP_MGR_SLOT(N) \
static BOOL (*orig_feat_##N)(id, SEL, unsigned long long); \
static BOOL new_feat_##N(id self, SEL _cmd, unsigned long long fid) { \
    BOOL v = orig_feat_##N ? orig_feat_##N(self, _cmd, fid) : NO; \
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) \
        [SCIMobileConfigRuntime recordParamID:fid type:@"bool" returned:@(v) defaultValue:nil sourceObject:self selector:NSStringFromSelector(_cmd)]; \
    id o = [SCIMobileConfigRuntime overrideForParamID:fid type:@"bool" original:@(v)]; \
    return o ? [o boolValue] : v; \
} \
static long long (*orig_featint_##N)(id, SEL, unsigned long long); \
static long long new_featint_##N(id self, SEL _cmd, unsigned long long fid) { \
    long long v = orig_featint_##N ? orig_featint_##N(self, _cmd, fid) : 0; \
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) \
        [SCIMobileConfigRuntime recordParamID:fid type:@"int" returned:@(v) defaultValue:nil sourceObject:self selector:NSStringFromSelector(_cmd)]; \
    id o = [SCIMobileConfigRuntime overrideForParamID:fid type:@"int" original:@(v)]; \
    return o ? [o longLongValue] : v; \
}

DEFINE_EXP_MGR_SLOT(0)
DEFINE_EXP_MGR_SLOT(1)

static void hookInstance(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls || !selName.length || !newImp || !origOut) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, origOut);
}

static void hookClassMethod(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls || !selName.length || !newImp || !origOut) return;
    SEL sel = NSSelectorFromString(selName);
    Class meta = object_getClass(cls);
    if (!class_getInstanceMethod(meta, sel)) return;   // class method lives on metaclass
    MSHookMessageEx(meta, sel, newImp, origOut);
}

static void installUnifiedManagerHooks(void) {
    // FBCCIGExperimentManager -> slot 0
    Class m0 = objc_getClass("FBCCIGExperimentManager");
    hookInstance(m0, @"isFeatureEnabled:",               (IMP)new_feat_0,    (IMP *)&orig_feat_0);
    hookInstance(m0, @"isFeatureEnabledWithoutLogging:", (IMP)new_feat_0,    (IMP *)&orig_feat_0);
    hookInstance(m0, @"getFeatureIntValue:",             (IMP)new_featint_0, (IMP *)&orig_featint_0);
    hookInstance(m0, @"getFeatureIntValueWithoutLogging:",(IMP)new_featint_0,(IMP *)&orig_featint_0);

    // FBCustomExperimentManager -> slot 1
    Class m1 = objc_getClass("FBCustomExperimentManager");
    hookInstance(m1, @"isFeatureEnabled:",               (IMP)new_feat_1,    (IMP *)&orig_feat_1);
    hookInstance(m1, @"isFeatureEnabledWithoutLogging:", (IMP)new_feat_1,    (IMP *)&orig_feat_1);
    hookInstance(m1, @"getFeatureIntValue:",             (IMP)new_featint_1, (IMP *)&orig_featint_1);
    hookInstance(m1, @"getFeatureIntValueWithoutLogging:",(IMP)new_featint_1,(IMP *)&orig_featint_1);
}

// ─────────────────────────────────────────────────────────────────────────────
// G2 — QuickExperiment configs: +[<Nome>ExperimentConfig isEnabled:(id)context]
//
// Descoberta dinâmica: varre a runtime por classes cujo nome termina em
// "ExperimentConfig" e que respondem a +isEnabled:. Força YES SELETIVAMENTE:
//   - sci_qe_force_all == YES  → força todas (pref de risco explícita)
//   - sci_qe_force_<NomeClasse> == YES → força só aquela
// Passthrough caso contrário.
// ─────────────────────────────────────────────────────────────────────────────

static NSMutableDictionary<NSString *, NSValue *> *sQEOrig;   // className -> original +isEnabled: IMP
static NSMutableArray<NSString *> *sQENames;

static BOOL sciQEShouldForce(NSString *className) {
    if ([SCIUtils getBoolPref:@"sci_qe_force_all"]) return YES;
    if (!className.length) return NO;
    NSString *k = [@"sci_qe_force_" stringByAppendingString:className];
    return [SCIUtils getBoolPref:k];
}

static BOOL qe_isEnabled_replacement(id self, SEL _cmd, id ctx) {
    // self é a própria classe (class method). Descobre o nome e o IMP original.
    NSString *name = NSStringFromClass((Class)self);
    NSValue *ov = sQEOrig[name];
    BOOL (*orig)(id, SEL, id) = ov ? (BOOL (*)(id, SEL, id))[ov pointerValue] : NULL;
    BOOL v = orig ? orig(self, _cmd, ctx) : NO;
    if (sciQEShouldForce(name)) return YES;
    return v;
}

static void installQuickExperimentHooks(void) {
    if (!sQEOrig)  sQEOrig  = [NSMutableDictionary new];
    if (!sQENames) sQENames = [NSMutableArray new];

    unsigned int count = 0;
    Class *all = objc_copyClassList(&count);
    if (!all) return;
    SEL sel = @selector(isEnabled:);

    for (unsigned int i = 0; i < count; i++) {
        Class cls = all[i];
        const char *cn = class_getName(cls);
        if (!cn) continue;
        NSString *name = [NSString stringWithUTF8String:cn];
        if (![name hasSuffix:@"ExperimentConfig"]) continue;

        Class meta = object_getClass(cls);

        // Só considera classes que DEFINEM +isEnabled: elas mesmas (não herdado) —
        // o replacement compartilhado resolve o IMP original por nome de classe, o
        // que só é correto pra quem define o método diretamente. Varre a própria
        // method list da metaclasse.
        BOOL definesOwn = NO;
        char retType = 0; unsigned int nargs = 0;
        unsigned int mcount = 0;
        Method *mlist = class_copyMethodList(meta, &mcount);
        if (mlist) {
            for (unsigned int j = 0; j < mcount; j++) {
                if (sel_isEqual(method_getName(mlist[j]), sel)) {
                    definesOwn = YES;
                    char r[8] = {0};
                    method_getReturnType(mlist[j], r, sizeof(r));
                    retType = r[0];
                    nargs = method_getNumberOfArguments(mlist[j]);
                    break;
                }
            }
            free(mlist);
        }
        if (!definesOwn) continue;
        if (retType != 'B' && retType != 'c') continue;   // precisa ser BOOL
        if (nargs != 3) continue;                          // self, _cmd, ctx

        if (sQEOrig[name]) continue;   // já instalado

        IMP origIMP = NULL;
        MSHookMessageEx(meta, sel, (IMP)qe_isEnabled_replacement, &origIMP);
        if (origIMP) {
            sQEOrig[name] = [NSValue valueWithPointer:(const void *)origIMP];
            [sQENames addObject:name];
        }
    }
    free(all);
}

// ─────────────────────────────────────────────────────────────────────────────
// G3 — helpers específicos curados (todos validados: classe + seletor + tipo BOOL).
// Força YES seletivamente por (classe, seletor) só quando sci_exp_helpers == YES.
// Evita de propósito seletores que quebram semântica (ex.: isNoOverrideEnabled) e
// os que recebem param-ID uint64 (isSwiftMigrationEnabledWithParam:), que teriam o
// mesmo problema de "forçar tudo" dos managers.
// ─────────────────────────────────────────────────────────────────────────────

typedef struct { const char *cls; const char *sel; BOOL classMethod; } SCIHelperTarget;

// Cada IMP forçado é trivial (return YES), instalado só se a assinatura for BOOL
// no-arg-ish. Guardamos os originais num dic pra poder desligar via passthrough.
static NSMutableDictionary<NSString *, NSValue *> *sHelperOrig;

#define HELPER_FORCE(TAG) \
static BOOL (*orig_help_##TAG)(id, SEL); \
static BOOL new_help_##TAG(id self, SEL _cmd) { \
    if ([SCIUtils getBoolPref:@"sci_exp_helpers"]) return YES; \
    return orig_help_##TAG ? orig_help_##TAG(self, _cmd) : NO; \
}

// Curadoria: SOMENTE helpers no-arg BOOL (B16@0:8) — passthrough (id,SEL) é exato.
HELPER_FORCE(navSelection)   // IGExperimentalNavigationState.isNavigationOptionSelectionEnabled
HELPER_FORCE(reelsFirst)     // IGExperimentalNavigationState.isReelsFirstOverrideEnabled
HELPER_FORCE(animOOM)        // IGAnimatedImageGating.isAnimatedImageOOMFixEnabled

static void installCuratedHelperHooks(void) {
    // IGExperimentalNavigationState (instance, no-arg BOOL getters)
    Class navState = objc_getClass("_TtC33IGExperimentalNavigationSelection29IGExperimentalNavigationState");
    hookInstance(navState, @"isNavigationOptionSelectionEnabled", (IMP)new_help_navSelection, (IMP *)&orig_help_navSelection);
    hookInstance(navState, @"isReelsFirstOverrideEnabled",        (IMP)new_help_reelsFirst,   (IMP *)&orig_help_reelsFirst);
    // Nota: isNoOverrideEnabled NÃO é forçado — forçar YES nele anularia as outras seleções.

    // IGAnimatedImageGating (class method, no-arg BOOL)
    Class animGating = objc_getClass("_TtC21IGAnimatedImageGating21IGAnimatedImageGating");
    hookClassMethod(animGating, @"isAnimatedImageOOMFixEnabled", (IMP)new_help_animOOM, (IMP *)&orig_help_animOOM);

    // IGStoriesTabExperimentHelper / IGSwiftMigrationExperiment recebem argumento
    // (launcherSet / uint64 param) e são deixados fora da curadoria "force YES" por
    // segurança — são candidatos ao override seletivo por ID (G1) ou por preset.
}

// ─────────────────────────────────────────────────────────────────────────────
// Instalação
// ─────────────────────────────────────────────────────────────────────────────

static void installAll(void) {
    installUnifiedManagerHooks();   // G1
    installQuickExperimentHooks();  // G2
    installCuratedHelperHooks();    // G3
}

void SCIInstallExperimentForceHooksIfNeeded(void) {
    if (![SCIExperimentForce anyEnabled]) return;

    // Managers e configs podem ser realizados tarde (Swift). Instala uma vez em
    // DidBecomeActive (sem escada de timer — ver CLAUDE.md). objc_getClass/varredura
    // de classlist é seguro em qualquer ponteiro; MSHookMessageEx em métodos ObjC.
    SCIInstallOnceOnActive(^{
        installAll();
    });
}

@implementation SCIExperimentForce

+ (NSArray<NSString *> *)prefKeys {
    return @[ @"sci_exp_mgr_capture", @"sci_qe_force_all", @"sci_exp_helpers" ];
}

+ (BOOL)anyEnabled {
    // Liga se qualquer superfície foi pedida: captura de managers, force-all de QE,
    // helpers, OU qualquer pref por-classe sci_qe_force_<Nome> individual.
    if ([SCIUtils getBoolPref:@"sci_exp_mgr_capture"]) return YES;
    if ([SCIUtils getBoolPref:@"sci_qe_force_all"]) return YES;
    if ([SCIUtils getBoolPref:@"sci_exp_helpers"]) return YES;
    if ([SCIMobileConfigRuntime runtimeHooksEnabled]) return YES; // captura G1 compartilhada
    NSDictionary *dom = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *k in dom) {
        if ([k hasPrefix:@"sci_qe_force_"] && [dom[k] respondsToSelector:@selector(boolValue)] && [dom[k] boolValue])
            return YES;
    }
    return NO;
}

+ (NSArray<NSString *> *)discoveredQuickExperimentConfigNames {
    return sQENames ? [sQENames copy] : @[];
}

@end

%ctor {
    @autoreleasepool {
        SCIInstallExperimentForceHooksIfNeeded();
    }
}
