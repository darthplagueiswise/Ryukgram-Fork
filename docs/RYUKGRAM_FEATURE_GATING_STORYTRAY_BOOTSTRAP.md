# RyukGram — Feature Gating e Story Tray bootstrap

## O que quebrou

Os hooks do Feature Gating pararam porque o bootstrap foi reduzido para apenas:

```objc
[SCIGatingCatalog reconcileCrashGuardOnLaunch];
```

Isso removeu:

```objc
[SCIGatingCatalog installPersistedDirectOverrideHooks];
```

Sem essa chamada, os overrides persistidos continuam salvos em `NSUserDefaults`, mas não viram hooks depois do restart.

## Por que o Story Tray também falha

O botão `Story Tray` em Advanced chama:

```objc
[SCIBulkGatingPresets applyStoryTray:on];
```

Essa função usa:

```objc
[SCIGatingCatalog setRuntimeBoolOverride:...]
```

para instalar hooks nos getters da `IGNavConfiguration.IGHomecomingConfiguration`.

Se a classe Swift ainda não estiver carregada quando o usuário toca no toggle, o código antigo fazia:

```objc
if (![self installRuntimeBoolHookForClass:...]) return;
```

e retornava antes de persistir o override. Resultado: o toggle parecia ação de UI, mas nada ficava salvo e nada era reinstalado depois.

## Correção aplicada

1. Restaura `installPersistedDirectOverrideHooks` no bootstrap.
2. Adiciona retries em 2s, 5s e 9s para classes Swift registradas tardiamente.
3. Ajusta `setRuntimeBoolOverride` para persistir o override antes da tentativa de hook. Assim, mesmo se a classe ainda não estiver carregada, o override fica salvo e o bootstrap/retry tenta aplicar depois.

## Regra

Isto não instala hooks aleatórios em clean install. Ele reinstala apenas overrides que já foram explicitamente selecionados pelo usuário e persistidos.
