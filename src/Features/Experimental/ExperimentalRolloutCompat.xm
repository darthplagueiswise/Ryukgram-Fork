// Experiment-name substring override. Gates: igt_directnotes_friendmap, igt_prism.
// (igt_quicksnap branch removed — Instants surface is gated by Swift-native
// logic on current IG and forcing the experiment names does nothing visible.)

#import "../../Utils.h"
#import "../Dogfooding/SCILauncherOverride.h"
#import "../Dogfooding/SCIInstallOnce.h"
#import <objc/runtime.h>
#import <substrate.h>

static inline BOOL containsAny(NSString *s, NSArray<NSString *> *needles) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return NO;
    NSString *lower = s.lowercaseString;
    for (NSString *n in needles) if ([lower containsString:n]) return YES;
    return NO;
}

static BOOL matchFriendMap(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_directnotes_friendmap"]) return NO;
    return containsAny(name, @[@"friendmap", @"friends_map", @"direct_notes",
                               @"ig_direct_notes_ios", @"_ig_ios_friendmap_", @"_ig_ios_friends_map_"]);
}

static BOOL matchPrism(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_prism"]) return NO;
    return containsAny(name, @[@"prism"]);
}

static NSArray<NSString *> *sciForcedExperiments(void) {
    id v = [[NSUserDefaults standardUserDefaults] arrayForKey:@"sci_forced_experiments"];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static BOOL matchUserForced(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
    NSString *lower = name.lowercaseString;
    for (NSString *needle in sciForcedExperiments()) {
        if ([needle isKindOfClass:[NSString class]] && needle.length &&
            [lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static inline BOOL shouldForceOn(NSString *name) {
    return matchFriendMap(name) || matchPrism(name) || matchUserForced(name);
}

static NSString *expNameOf(id obj) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), "_experimentGroupName");
    if (!iv) iv = class_getInstanceVariable(object_getClass(obj), "_experimentName");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        if ([v isKindOfClass:[NSString class]]) return v;
    } @catch (__unused id e) {}
    return nil;
}

static id (*orig_groupName)(id, SEL) = NULL;
static id new_groupName(id self, SEL _cmd) {
    if (shouldForceOn(expNameOf(self))) return @"test";
    return orig_groupName ? orig_groupName(self, _cmd) : nil;
}

static id (*orig_peekGroup)(id, SEL) = NULL;
static id new_peekGroup(id self, SEL _cmd) {
    if (shouldForceOn(expNameOf(self))) return @"test";
    return orig_peekGroup ? orig_peekGroup(self, _cmd) : nil;
}

static void hook(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, origOut);
}

%ctor {
    // SCI-FIX 2026-07-11: dispatch_after de 2s substituído por SCIInstallOnceOnActive
    // (mesmo padrão usado no resto do tweak pra evitar timer-source tardio mandando
    // mensagem pra objeto que ainda não existe / já morreu).
    if ([SCILauncherOverride totalOverrideCount] > 0) {
        SCIInstallOnceOnActive(^{
            [SCILauncherOverride replayPersistedOverrides];
        });
    }

    if (!([SCIUtils getBoolPref:@"igt_directnotes_friendmap"] ||
          [SCIUtils getBoolPref:@"igt_prism"] ||
          sciForcedExperiments().count > 0)) return;

    // SCI-FIX 2026-07-11: RE-VERIFICADO contra 433.0.283 (parser de chained-fixups
    // corrigido). `MetaLocalExperiment` está PRESENTE e `groupName`/`peekGroupName`
    // são métodos REAIS (retorno @ = NSString) — esses dois hooks abaixo são o lever
    // correto e continuam ativos.
    //
    // Removidos os 3 hooks que a sessão anterior mantinha "por precaução": eles
    // NUNCA existiram como método, em nenhum binário observado — não é uma questão
    // de versão:
    //   - MetaLocalExperiment.isInExperiment      → não existe (métodos reais: groupName/peekGroupName)
    //   - FamilyLocalExperiment.isInExperiment    → não existe (só init nesta imagem)
    //   - LIDExperimentGenerator.isExperimentEnabled: → não existe (métodos reais: createLocalExperiment:/initWithDeviceID:logger:)
    Class meta = NSClassFromString(@"MetaLocalExperiment");
    hook(meta, @"groupName",      (IMP)new_groupName,   (IMP *)&orig_groupName);
    hook(meta, @"peekGroupName",  (IMP)new_peekGroup,   (IMP *)&orig_peekGroup);
}

