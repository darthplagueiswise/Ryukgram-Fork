// SCIXPluginsLookupHook.x
//
// _XPluginsGetListLookupDataPair — função EXPORTADA pelo binário do Instagram.
//
// ESTRATÉGIA (convertida de observação para interceptação):
//
//   1. dlsym(RTLD_MAIN_ONLY, "_XPluginsGetListLookupDataPair") resolve o endereço
//      no binário em execução (ASLR-safe).
//
//   2. O símbolo exportado aponta para um NULL-STUB em builds estáticos analisados.
//      O initializer do XPlugins pode substituir esse stub em runtime. Por isso,
//      a instalação do hook é ATRASADA para 2s e 5s após o launch, dando tempo ao
//      inicializador do XPlugins de rodar e potencialmente corrigir o endereço.
//
//   3. MODO FORCE (sci_xplugins_force_igonly):
//      Para chaves IG-Only/Internal/Dogfood, se orig retornar NULL (stub ou
//      usuário não-employee), retornamos um sentinel estático não-nulo.
//      Os callers desse lookup tipicamente fazem apenas null-check; o sentinel
//      zeroed-bytes é seguro pois campos nulos = "entrada vazia mas existente".
//      O employee/internal checker (hookeado via SCIIGEmployeeForceHook +
//      SCIIGInternalBuildHook) então libera o item no segundo estágio.
//
//   4. MODO OBSERVAÇÃO (sci_xplugins_observe): mantido para diagnóstico.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIXPlugins] " fmt,##__VA_ARGS__)

static NSString *const kObserve = @"sci_xplugins_observe";
static NSString *const kForce   = @"sci_xplugins_force_igonly";

static volatile BOOL sCacheObserve = NO;
static volatile BOOL sCacheForce   = NO;

typedef void *(*XPluginsListLookup_t)(void *list, void *key);
static XPluginsListLookup_t orig_XPluginsList = NULL;

// Chaves que identificam menus internos/IG-Only no parâmetro key
static BOOL isIGOnlyKey(void *key) {
    if (!key) return NO;
    @try {
        const char *s = (const char *)key;
        if (!s) return NO;
        return (strncmp(s, "[IG-Only]", 9) == 0 ||
                strncmp(s, "[IG-only]", 9) == 0 ||
                strncmp(s, "[ig-only]", 9) == 0 ||
                strncmp(s, "[Internal", 9) == 0 ||
                strncmp(s, "[INTERNAL", 9) == 0 ||
                strncmp(s, "[ig-Only]", 9) == 0);
    } @catch (...) { return NO; }
}

// Sentinel: struct zeroed de 128 bytes.
// Campos zero = "nenhum dado", o que é seguro para callers que inspecionam
// tamanho ou ponteiro antes de usar. Não-nulo → passa o null-check do caller.
static char gSentinel[128];

static void *my_XPluginsList(void *list, void *key) {
    void *result = orig_XPluginsList ? orig_XPluginsList(list, key) : NULL;

    if (sCacheObserve) {
        SCILOG("list=%p key=%p → %p  keyStr=%s",
               list, key, result,
               (key ? (const char *)key : "(null)"));
    }

    // Interceptação: força retorno não-nulo para chaves IG-Only
    if (sCacheForce && result == NULL && isIGOnlyKey(key)) {
        memset(gSentinel, 0, sizeof(gSentinel));
        result = gSentinel;
        if (sCacheObserve) {
            SCILOG("FORCE: retornando sentinel para key=%s", (const char *)key);
        }
    }

    return result;
}

static BOOL sHookInstalled = NO;

static void SCIInstallXPluginsHook(void) {
    if (sHookInstalled) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    sCacheObserve = [ud boolForKey:kObserve];
    sCacheForce   = [ud boolForKey:kForce];

    if (!sCacheObserve && !sCacheForce) return; // nenhum dos modos ativo

    void *sym = dlsym(RTLD_MAIN_ONLY, "_XPluginsGetListLookupDataPair");
    if (!sym) { SCILOG("dlsym falhou"); return; }

    SCILOG("dlsym → %p  observe=%d force=%d", sym, sCacheObserve, sCacheForce);
    MSHookFunction(sym, (void *)my_XPluginsList, (void **)&orig_XPluginsList);
    sHookInstalled = YES;
    SCILOG("hook instalado orig=%p", orig_XPluginsList);
}

%ctor {
    @autoreleasepool {
        // Delays: o null-stub pode ser substituído pelo XPlugins initializer
        // alguns milissegundos após o launch. Hookamos tarde para pegar a versão real.
        double delays[] = {2.0, 5.0};
        for (NSUInteger i = 0; i < 2; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i]*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                SCIInstallXPluginsHook();
            });
        }
    }
}
