# RyukGram startup hook audit — repo zip 877675d

## Veredito

Sim: no zip analisado há hooks de startup que contrariam o `RYUKGRAM_BUILD_AND_HOOK_GUARDRAILS.md` e podem explicar o crash/lentidão no launch.

## Pontos críticos encontrados

### 1. `SCIGatingCatalogBootstrap.x`

Estado no zip:
- chama `installPersistedDirectOverrideHooks` no `%ctor`;
- repete isso em `dispatch_after` 2s, 5s e 9s.

Risco:
- se sobrou override antigo em `NSUserDefaults`, ele reinstala hooks antes da UI aparecer;
- isso contradiz a regra do guardrail: não reinstalar overrides persistidos automaticamente no startup.

### 2. `SCIIGDSLauncherConfigHook.x`

Estado no zip:
- `%ctor { IGDSInstall(); }`;
- `SCIIGDSEnsureHooksInstalled` está `no-op`.

Risco:
- está invertido: startup tenta aplicar; botão/toggle não aplica nada;
- se alguma pref IGDS antiga estiver ON, hooks entram antes da tela abrir.

Correção esperada:
- `%ctor` não instala nada;
- `SCIIGDSEnsureHooksInstalled()` chama `IGDSInstall()` quando o usuário toca/troca toggle.

### 3. `StoryTrayActions.x`

Estado no zip:
- instala hook global em `UIViewController presentViewController:animated:completion:` sempre no `%ctor`;
- só checa `story_tray_actions` dentro do replacement.

Risco:
- mesmo pref OFF, o hook global fica instalado;
- contradiz “nenhum hook sem selecionar antes”.

### 4. `SCIEmployeeDefaults.m` + `SCIIGEmployeeForceHook.x`

Estado no zip:
- `SCIIGEmployeeForceHook.x` chama `SCIInstallAllGates()` no `%ctor`;
- `SCIEmployeeDefaults.installHooksIfNeeded` instala hooks de `NSUserDefaults` antes de confirmar pref ON.

Risco:
- hook de `NSUserDefaults` no launch path é particularmente sensível;
- mesmo que o replacement retorne original quando cache OFF, o hook já alterou a classe global.

### 5. `SCIIGConsumerSubsHook.x`

Estado no zip:
- instala hooks de IGPlus no `%ctor`, com retries;
- os replacements são gated, mas os hooks entram antes de pref explícito.

Risco:
- baixo/médio, mas ainda viola o guardrail de “hook só após pref”.

### 6. `SCIInternalSettingsMenuHook.x`

Estado no zip:
- tenta instalar hooks do menu interno no `%ctor` e em retries.

Risco:
- se a classe/assinatura mudou, pode quebrar launch;
- deve ser gated pelo pref `sci_force_internal_settings_menu`.

### 7. `SCIXPluginsLookupHook`

No zip está como:

```text
src/Features/Gating/SCIXPluginsLookupHook.txt
```

Então não compila como hook. Não é causa de crash neste zip, mas também não funciona como hook.

## C hooks MobileConfig/EasyGating

`SCIInternalUseGateHook.x`, `SCIEasyGatingHook.x` e `SCISessionedMCGateHook.x` já têm guard de pref antes de `rebind_symbols`. Eles ainda têm observer de defaults, mas não devem instalar fishhook quando tudo está OFF.

## Patch gerado

O patch `ryukgram-startup-hook-quarantine-and-storytray-fix.zip` aplica:

1. remove reinstalação automática ampla de Feature Gating no startup;
2. mantém `reconcileCrashGuardOnLaunch`;
3. muda `SCIGatingCatalog.m` para persistir override primeiro e fazer retries apenas do getter selecionado pelo usuário;
4. torna `SCIIGDSEnsureHooksInstalled()` funcional e remove `IGDSInstall()` do `%ctor`;
5. protege `StoryTrayActions.x` para só instalar hook global se `story_tray_actions` estiver ON no startup;
6. impede `SCIEmployeeDefaults` de hookar `NSUserDefaults` se nenhum pref employee/internal estiver ON;
7. protege `SCIIGEmployeeForceHook`, `SCIIGConsumerSubsHook` e `SCIInternalSettingsMenuHook` para não instalar hooks se os prefs deles estiverem OFF.

## Trade-off

Com esse patch, hooks persistidos antigos não são reinstalados automaticamente no startup. Isso é intencional para parar crash antes da UI. Feature Gating/StoryTray aplicam ao serem selecionados na UI, com retries específicos do getter escolhido.
