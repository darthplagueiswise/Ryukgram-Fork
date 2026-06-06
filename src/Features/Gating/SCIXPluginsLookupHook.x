// SCIXPluginsLookupHook.x
//
// Hook de _XPluginsGetListLookupDataPair definido no binário principal do Instagram.
//
// POR QUE fishhook NÃO FUNCIONA AQUI:
//   fishhook reescreve entradas do GOT de *imports*. Esta função é EXPORTADA pelo
//   Instagram (não importada de outra dylib), portanto não existe entrada no GOT
//   do Instagram para ela. Solução: MSHookFunction que patcha o prólogo em memória.
//
// ANÁLISE ESTÁTICA (binário FBSharedFramework + Instagram arm64):
//
//   A função está EXPORTADA pelo Instagram com valor estático 0x1001b3e64.
//   No entanto, a primeira instrução nesse endereço é:
//       0x1001b3e64  b  <ret_null>     ; → mov x0,#0; ret
//   Ou seja, o símbolo exportado é um NULL-STUB: retorna NULL imediatamente.
//
//   Um body real existe em +4 (0x1001b3e68) mas está inacessível via o export:
//       0x1001b3e68  stp x20, x19, [sp, #-0x20]!
//       ...
//       0x1001b3e84  b  #0x100009028   ; tail call para epílogo padrão
//
//   Um inicializador encontrado em +0x24 (0x1001b3e88) guarda um function pointer
//   numa global (~0x100da3bbc → *[x9+0x520]) que possivelmente substitui o stub
//   em runtime pelo dispatch real via XPlugins.
//
//   O endereço runtime reportado via FLEX (0x105cde6c0) e o endereço estático
//   (0x1001b3e64) têm um delta (0x5b2a85c) que não é múltiplo de 0x4000,
//   sugerindo que o binário no dispositivo é uma versão diferente da estática
//   fornecida, OU que FLEX resolve a entrada dinâmica do XPlugins dispatch table.
//
// ESTRATÉGIA DO HOOK:
//   1. dlsym(RTLD_MAIN_ONLY, "_XPluginsGetListLookupDataPair") — resolve o endereço
//      correto no binário em execução, independente de ASLR e versão.
//   2. MSHookFunction — patcha o prólogo em memória (safe para sideload via ElleKit).
//   3. Default: modo observação — log + call-through.
//      NÃO retornamos par falso: o layout do struct de retorno é desconhecido.
//      Retornar uma pointer inválida aqui causaria crash no caller.
//
// ASSINATURA CONSERVADORA (derivada de XPluginsGetDataPair como referência):
//   _XPluginsGetDataPair(uint32_t id) faz binary search numa tabela com 0x8DA entradas,
//   cada entry de 16 bytes. Por analogia, GetListLookupDataPair provavelmente:
//   void *_XPluginsGetListLookupDataPair(void *list, void *key)
//   — retorna ponteiro para par {data, size} ou NULL se não encontrado.
//
// PARA AJUSTAR O TIPO DE RETORNO:
//   Ative sci_xplugins_observe=YES, abra os logs com:
//   log stream --predicate 'subsystem contains "SCIXPlugins"' --level debug
//   Os valores de list/key/result estarão visíveis. Então consulte FLEX para
//   inspecionar o conteúdo dos ponteiros e determinar o layout do struct.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <substrate.h>
#import <os/log.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIXPlugins] " fmt,##__VA_ARGS__)

// ── Pref key ───────────────────────────────────────────────────────────────
static NSString * const kXPluginsObserve = @"sci_xplugins_observe";

// ── Cache C-only ───────────────────────────────────────────────────────────
static volatile BOOL sCacheXPluginsObserve = NO;

// ── Tipo de retorno conservador ─────────────────────────────────────────────
// Ajustar quando o struct real for confirmado via runtime logs.
typedef void *(*XPluginsListLookup_t)(void *list, void *key);

static XPluginsListLookup_t orig_XPluginsList = NULL;

// ── Replacement ─────────────────────────────────────────────────────────────
// NÃO altera o retorno — apenas observa.
// Para interceptar e modificar o par, substituir o return pelo struct montado
// quando o layout for confirmado.
static void *my_XPluginsList(void *list, void *key) {
    void *result = orig_XPluginsList ? orig_XPluginsList(list, key) : NULL;
    if (sCacheXPluginsObserve) {
        // Os ponteiros são impressos como hexadecimal para inspeção offline via FLEX.
        // Exemplo de log esperado:
        //   [SCIXPlugins] XPluginsGetListLookupDataPair list=0x... key=0x... → 0x...
        SCILOG("XPluginsGetListLookupDataPair list=%p key=%p → result=%p",
               list, key, result);
    }
    return result;
}

// ── Instalação ─────────────────────────────────────────────────────────────
void SCIInstallXPluginsLookupHookIfNeeded(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;

    sCacheXPluginsObserve = [NSUserDefaults.standardUserDefaults boolForKey:kXPluginsObserve];

    // dlsym via RTLD_MAIN_ONLY: resolve o símbolo no executável principal (Instagram).
    // O nome para dlsym inclui o underscore — ao contrário do fishhook.
    void *sym = dlsym(RTLD_MAIN_ONLY, "_XPluginsGetListLookupDataPair");
    if (!sym) {
        SCILOG("dlsym falhou — símbolo não encontrado no binário principal");
        return;
    }
    SCILOG("dlsym → %p (MSHookFunction)", sym);

    // MSHookFunction patcha o prólogo em memória via vm_protect + BL rewrite.
    // Safe para sideload (ElleKit): não modifica o binário em disco.
    // NOTA: se o NULL-STUB (b→ret_null) foi substituído em runtime pelo XPlugins
    //       initializer, hookamos o stub. Se o initializer escreve um function ptr
    //       separado, este hook não intercepta chamadas diretas a esse ptr.
    //       Nesse caso, monitorar a global em *[x9+0x520] via FLEX para localizar
    //       o endereço real e instalar um segundo MSHookFunction nele.
    MSHookFunction(sym, (void *)my_XPluginsList, (void **)&orig_XPluginsList);
    SCILOG("MSHookFunction instalado (orig=%p)", orig_XPluginsList);
}

%ctor {
    @autoreleasepool {
        SCIInstallXPluginsLookupHookIfNeeded();
    }
}
