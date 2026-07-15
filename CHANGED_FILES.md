# Arquivos alterados — sessões 2026-06-11 + 2026-07-11 (cumulativo)

Diff unificado completo: **`PATCH_full_diff.diff`** (623 linhas, 36K), contra o upload original.
Tudo verificado contra o binário **433.0.283** (parser de chained-fixups próprio,
`objc_dump.py`/`sym_dump.py`/`q.py`, validado contra verdade-terreno conhecida).
**Não compilado/testado em device** — ver `ERROS_E_CORRECOES.md §5`.

## Novos arquivos
- `src/Features/Dogfooding/SCIInstallOnce.h` — helper `SCIInstallOnceOnActive` (install único em `DidBecomeActive`, sem escada de timer).
- `disabled/` — 10 arquivos "disable-by-rename" (`.txt`/`.xm_`/`.m_`/`.x_`) movidos pra fora de `src/`, com README explicando cada um.
- `REVISAO_CODIGO_RyukGram.md`, `ERROS_E_CORRECOES.md`, `CRASH_ANALISE_433.0.283.md`, `CLAUDE.md`, `CHANGED_FILES.md` (este arquivo), `PATCH_full_diff.diff`.

## Arquivos deletados (não movidos — conteúdo removido de verdade)
- `src/Features/Gating/SCIRuntimeBoolForce.m` / `.h` — Mecanismo D inferior, pedido explícito de remoção.
- `src/Features/Gating/SCIIGDSLauncherConfigHook.txt` — rascunho superado pelo `.x` ativo homônimo.
- `src/Features/Gating/SCILaunchAutoForceHooks.removed.txt` — era só uma nota de texto.

## Arquivos movidos (conteúdo preservado em `disabled/`, path antigo removido)
`SCIDebugConsole.m_`, `ExpFlagsHooks.xm_`, `SCIExpFlags.m_`, `EnableAllTextEffects.xm_`,
`EnableHomecomingUI.x_`, `QuickSnapCompat.xm_`, `QuickSnapMCCompat.xm_`,
`SCIXPluginsLookupHook.txt`, `ProfileCopyButton.x_`, `SCIExpFlagsViewController.m_`.

## Fontes modificados (18)

**MobileConfig / EasyGating** (revisão nova):
- `src/Features/MobileConfig/SCIMobileConfigRuntimeHooks.x` — 4 slots `FBMobileConfig*` mortos retargeted; escada `dispatch_after` removida.
- `src/Features/MobileConfig/SCIInternalUseGateHook.x` — install passou a incondicional (toggle em runtime agora funciona sem relançar).
- `src/Features/EasyGating/SCIEasyGatingHook.x` — idem.
- `src/Features/EasyGating/SCISessionedMCGateHook.x` — idem.

**LiquidGlass / IGWord / Stories Tray:**
- `src/Features/Gating/SCIBulkGatingPresets.m` — 3 seletores fantasma removidos de `applyLiquidGlass:` (sessão 1); todos os outros métodos (`applyLiquidGlass:`, `applyStoryTray:`, `applyWordmark:`, `applyStatusBarOldSchool:`) revalidados e confirmados corretos nesta sessão.
- `src/Features/Experimental/HomecomingCompat.xm` — 2 hooks que miravam seletor inexistente (`isInExperiment` em classes que na verdade só têm `groupName`) removidos; mantido o único lever real (`IGNavConfiguration.isHomecomingEnabled`).
- `src/Features/Experimental/ExperimentalRolloutCompat.xm` — mesma correção (3 hooks mortos removidos, `groupName`/`peekGroupName` mantidos por já estarem corretos); `dispatch_after` de replay trocado por `SCIInstallOnceOnActive`.
- `src/Features/Experimental/DirectNotesCompat.xm` — retarget pro helper de exposição correto (sessão 1).

**IGPlus:**
- `src/Features/Dogfooding/SCIIGPlusEligibilityHook.x` — **bug real**: 5 de 6 hooks usavam `instance:YES` pra seletores que só existem como método de classe → no-op silencioso desde sempre. Corrigido pra `instance:NO`; 2 seletores extras adicionados.
- `src/Features/Dogfooding/SCIIGConsumerSubsHook.x` — revalidado (todos os 18 seletores corretos); escada de retry já removida na sessão 1.

**Debug Menus:**
- `src/Features/Dogfooding/SCIIGEmployeeForceHook.x` — alt name inexistente removido (pedido explícito).
- `src/Features/Dogfooding/SCIInternalMenusForce.x` — migrado de `SCIRuntimeBoolForce` (deletado) pra `SCIGatingCatalog` (Mecanismo C).

**Crash / remoção de escadas de `dispatch_after` (sessão 1):**
- `SCIExperimentalNavHook.x` *(principal suspeito do crash)*, `SCIIGUserSessionHook.x`, `SCIDogfoodObjectRuntimeHooks.x`, `SCIDogfoodingSettingsPersistenceHooks.x`, `SCILauncherClientHook.x`.

**Build:**
- `Makefile` — `-Wno-incompatible-pointer-types` removido (pedido explícito). Sem `-Werror` no projeto, então isso só revela avisos, não quebra o build.

## Recomendado mas NÃO alterado
- `SCIXPluginsLookupHook.txt` (agora em `disabled/`) — técnica correta documentada (dlsym, não endereço hardcoded), mas o símbolo-alvo é definido dentro do próprio Instagram no launch path — reativar com cuidado extra de timing (ver `CLAUDE.md §4`).
- `SCIInternalGatePrefs.m` / `SCIInternalSettingsApplier.m` — `dispatch_after` revisados e mantidos de propósito (session-gated, null-guarded ou só tocam defaults) — ver `ERROS_E_CORRECOES.md §3`.
