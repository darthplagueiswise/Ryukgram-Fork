// Force-enable Homecoming nav experiment. Gate: igt_homecoming.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL (*orig_nav_isHC)(id, SEL) = NULL;
static BOOL new_nav_isHC(id self, SEL _cmd) { return YES; }

static void hook(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, origOut);
}

%ctor {
    if (![SCIUtils getBoolPref:@"igt_homecoming"]) return;

    // SCI-FIX 2026-07-11: RE-VERIFICADO contra 433.0.283 com parser de chained-fixups
    // corrigido (a checagem da sessão anterior tinha um bug de parsing e relatou estas
    // classes como ausentes — na verdade elas ESTÃO presentes no binário). O problema real
    // não é a classe, é o SELETOR:
    //   - MetaLocalExperiment: PRESENTE, mas não tem `isInExperiment`. Os métodos reais são
    //     `groupName` / `peekGroupName` (retornam NSString, o nome do bucket/grupo — não BOOL).
    //   - FamilyLocalExperiment: PRESENTE, mas só expõe `initWithConfig:familyDeviceID:logger:`
    //     nesta imagem — sem getter de leitura aqui.
    //   - LIDExperimentGenerator: PRESENTE, mas não tem `isExperimentEnabled:`. Os métodos
    //     reais são `createLocalExperiment:` / `initWithDeviceID:logger:`.
    // Ou seja, os 3 hooks abaixo SEMPRE foram no-op (class_getInstanceMethod retorna nil
    // pro seletor errado), independente da versão do binário. Removidos.
    //
    // O único lever real e verificado (classe + seletor + tipo `B16@0:8` = BOOL sem args)
    // é este:
    hook(NSClassFromString(@"_TtC18IGNavConfiguration18IGNavConfiguration"),
         @"isHomecomingEnabled", (IMP)new_nav_isHC, (IMP *)&orig_nav_isHC);

    // Se quiser forçar via MetaLocalExperiment/LIDExperimentGenerator no futuro, o caminho
    // correto é hookar `groupName`/`peekGroupName` (retorno NSString) e devolver o nome do
    // grupo "enabled" — não descobri qual string o app espera para considerar habilitado,
    // então não fabriquei esse valor. Não reintroduza os hooks de BOOL antigos: eles nunca
    // existiram como método nessas classes, em nenhuma versão observada.
}

