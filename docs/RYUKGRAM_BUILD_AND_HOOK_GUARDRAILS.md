# RyukGram — checklist para evitar novos erros de build e crashes de startup

## Diagnóstico deste erro de build

Erro:

```text
src/Features/Gating/SCIIGDSLauncherConfigHook.x:192:8: error: expected identifier or '('
extern "C" void SCIIGDSEnsureHooksInstalled(void) { IGDSInstall(); }
       ^
```

Causa exata: `SCIIGDSLauncherConfigHook.x` é compilado pelo Logos como Objective-C/C, não como Objective-C++. `extern "C"` é sintaxe C++ e quebra em arquivo `.x`.

Correção:

```objc
void SCIIGDSEnsureHooksInstalled(void) { IGDSInstall(); }
```

Só use `extern "C"` em arquivo compilado como Objective-C++ (`.xm`/`.mm`) ou dentro de guard C++:

```objc
#ifdef __cplusplus
extern "C" {
#endif

void SCIIGDSEnsureHooksInstalled(void);

#ifdef __cplusplus
}
#endif
```

Em `.x`, prefira assinatura C pura.

## Validação do `RYUKGRAM_HOOK_PLAN.md`

O plano está correto em princípio: usar `NSClassFromString`/`MSHookMessageEx` para ObjC, `dlsym`/`MSHookFunction` para símbolos C exportados e `fishhook` para imports GOT. Também está correta a regra de não usar endereço hardcoded.

Mas o zip atual ainda contradiz parte do plano em pontos de startup:

1. O plano diz para não usar hooks agressivos no launch path, mas `SCIXPluginsLookupHook.x` agenda `MSHookFunction` via `%ctor` e `dispatch_after`.
2. `SCIIGDSLauncherConfigHook.x` chama `IGDSInstall()` no `%ctor`, antes do usuário entrar no menu.
3. `SCIInternalUseGateHook.x`, `SCIEasyGatingHook.x` e `SCISessionedMCGateHook.x` instalam `fishhook` no `%ctor`.
4. Se a regra funcional é “nenhum hook sem selecionar antes”, então cada `%ctor` deve fazer somente uma leitura barata de pref e retornar sem instalar nada quando o pref está OFF.
5. Qualquer hook C que depende de ABI/endereço precisa ser opt-in e deve ser testado isoladamente.

Conclusão: pode seguir o plano, mas não o aplique como “instala tudo no `%ctor`”. O plano só está seguro se cada hook for gated por pref antes de `MSHookFunction`, `MSHookMessageEx` ou `rebind_symbols`.

## Regras para não repetir erros de build

### 1. Extensão do arquivo manda na sintaxe permitida

- `.x`: Logos + Objective-C/C. Não usar `extern "C"`.
- `.xm`: Logos + Objective-C++. Pode usar `extern "C"`.
- `.m`: Objective-C/C. Não usar sintaxe C++.
- `.mm`: Objective-C++. Pode usar C++.

### 2. Não importar headers indisponíveis no iPhoneOS SDK

Evitar:

```objc
#import <mach/mach_vm.h>
```

No iPhoneOS26.2 SDK isso pode falhar com:

```text
mach_vm.h unsupported
```

Prefira APIs disponíveis como:

```objc
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
```

e validação por segmentos Mach-O carregados.

### 3. Não usar `performSelector` em build com ARC + Werror

Evitar:

```objc
[obj performSelector:sel];
```

Pode quebrar com:

```text
-Warc-performSelector-leaks
```

Use `objc_msgSend` tipado:

```objc
#import <objc/message.h>

id (*fn)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
id value = fn(obj, sel);
```

Para setter `void`:

```objc
void (*fn)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
fn(obj, sel, YES);
```

### 4. Sempre declarar/importar classe usada em Settings

Se `SCISettings_Advanced.m` usa:

```objc
[SCIIGDSLauncherConfigViewController new]
```

então precisa ter:

```objc
#import "../SCIIGDSLauncherConfigViewController.h"
```

e o `.m/.h` precisam estar dentro de `src/Settings/`.

### 5. Evitar `no known class method`

Se chamar:

```objc
[SCIBulkGatingPresets applyIGWordmarkMode:value];
```

então o método precisa estar declarado no `.h` e implementado no `.m`.

### 6. Não deixar validação grep pegar comentário

Validação ruim:

```sh
grep -R "mach_vm_region" file.x
```

Isso falha até se o texto estiver em comentário. Validação melhor: remover comentários antes ou validar com regex simples em Python.

### 7. Todo arquivo novo precisa entrar no Makefile automaticamente ou estar em `src/`

O Makefile atual compila:

```make
$(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m \))
```

Então arquivos novos precisam estar em `src/` e com extensão correta. Arquivo fora de `src/` não compila.

### 8. Cuidado com blocos usados como IMP

Para método com muitos argumentos, principalmente BOOLs em stack, `imp_implementationWithBlock` pode errar ABI se a assinatura não casar exatamente. Para inicializadores longos, prefira Logos `%hook` com `%orig` ou função C estática com assinatura idêntica.

## Regras para não repetir crash de startup

### 1. `%ctor` não deve instalar hook pesado sem pref

Errado:

```objc
%ctor {
    MSHookFunction(...);
}
```

Correto:

```objc
%ctor {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"pref_do_hook"]) return;
    MSHookFunction(...);
}
```

### 2. Não usar `objc_copyClassList` no launch

Isso causa lentidão e pode bater em classes ainda instáveis. Runtime browser deve enumerar classes somente quando a tela for aberta, não no `%ctor`.

### 3. Não usar um único `orig` para vários seletores

Errado:

```objc
static IMP orig;
MSHookMessageEx(cls, selA, hookA, &orig);
MSHookMessageEx(cls, selB, hookB, &orig);
```

Cada selector precisa do seu próprio original, ou dictionary por chave `classe#selector`.

### 4. Não reinstalar overrides persistidos automaticamente no startup

Se o usuário tinha overrides antigos salvos, reinstalar tudo ao abrir o app pode crashar antes da UI. Persistência deve existir, mas a reinstalação precisa ser controlada por toggle explícito ou crash guard robusto.

### 5. C hooks não podem chamar Objective-C dentro do replacement

Dentro de replacement C chamado por MobileConfig/EasyGating, não chamar:

```objc
NSUserDefaults.standardUserDefaults
NSString
NSArray
NSDictionary
```

Use somente cache C estático.

## Validação mínima antes de subir

Rodar localmente antes do push:

```sh
grep -R 'extern "C"' src/Features/Gating/*.x src/Features/Dogfooding/*.x src/Features/EasyGating/*.x src/Features/MobileConfig/*.x && exit 1 || true
grep -R '#import <mach/mach_vm.h>' src && exit 1 || true
grep -R 'performSelector:' src/Features src/Settings && echo "REVISAR performSelector" || true
git diff --check
git status --short
```

Para build no GitHub, também validar que o workflow está usando:

```text
iPhoneOS26.2.sdk
TARGET := iphone:clang:26.2:16.3
ARCHS = arm64
rootless only
```

## Estado deste patch

Este patch corrige apenas o erro de build atual em `SCIIGDSLauncherConfigHook.x` e adiciona este documento de regras. Ele não altera a lógica funcional dos hooks.
