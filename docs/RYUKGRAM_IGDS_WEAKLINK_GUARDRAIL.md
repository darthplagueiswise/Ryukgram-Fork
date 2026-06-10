# RyukGram — linker/build guardrails para hooks opcionais

## Erro

```text
Undefined symbols for architecture arm64:
  "_SCIIGDSEnsureHooksInstalled", referenced from:
      -[SCIIGDSLauncherConfigViewController applyTapped]
      -[SCIIGDSLauncherConfigViewController swChanged:]
```

## Causa

`SCIIGDSLauncherConfigViewController.m` chamava `SCIIGDSEnsureHooksInstalled()` como símbolo forte:

```objc
extern void SCIIGDSEnsureHooksInstalled(void);
```

Se `SCIIGDSLauncherConfigHook.x` não existir, não for incluído pelo `find src`, for removido em rebase, ou falhar na preprocess/compile, o link quebra.

## Regra

UI não deve depender de símbolo forte de hook opcional. Use weak import + helper:

```objc
extern void SCIIGDSEnsureHooksInstalled(void) __attribute__((weak_import));

static BOOL SCIIGDSApplyHooksIfAvailable(void) {
    if (SCIIGDSEnsureHooksInstalled) {
        SCIIGDSEnsureHooksInstalled();
        return YES;
    }
    return NO;
}
```

Assim:
- se o hook real existir, a UI chama ele normalmente;
- se o hook não entrou na build, a build não quebra;
- o problema fica visível em runtime pela mensagem da UI;
- evita linker quebrado por arquivo removido/rebase parcial.

## Coisas para cuidar

1. `.x` é Objective-C/Logos, não Objective-C++. Não usar `extern "C"` em `.x`.
2. Função usada por outro arquivo não pode ser `static`.
3. Se uma função é opcional/experimental, a UI deve usar weak import.
4. Não criar chamada forte de UI para hook experimental sem garantir o arquivo no `Makefile`.
5. Depois de rebase, validar com:

```sh
grep -R 'SCIIGDSEnsureHooksInstalled' -n src
grep -R 'extern "C"' -n src/Features/Gating src/Features/Dogfooding src/Features/MobileConfig
```

6. Build CI deve falhar cedo se houver `extern "C"` em `.x`:

```sh
find src -name '*.x' -o -name '*.xm' | xargs grep -n 'extern "C"' && exit 1 || true
```
