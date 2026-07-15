# Revisão 438 — migração de MobileConfig, novo framework de experiments, e revalidação completa

**Data:** 2026-07-15 · **Binários:** Instagram 438 + FBSharedFramework 438
**UUIDs:** IG `4c4c4424-5555-3144-a12a-21f40609aaf2` · FBShared `4c4c446a-5555-3144-a1ad-1fc955150ec5`
**Método:** parser de chained-fixups próprio (`objc_dump.py`/`sym_dump.py`/`q.py`), validado contra verdade-terreno conhecida (`isPrismAvatarRingEnabled` presente / `isLiquidGlassEnabled` ausente). IG: 42356 classes; FBShared: 5323 classes.
**Honestidade:** nada compilado/testado em device (sem Theos/iPhone no ambiente) — só checagem estática de balanceamento e validação de classe/seletor/tipo contra os binários.

---

## 1. A migração do MobileConfig (433 → 438) — o ponto central

Na 433 o acesso a MobileConfig bool passava por **funções C soltas** exportadas pelo FBSharedFramework, incluindo `IGMobileConfigBooleanValueForInternalUse`. Na 438 essas funções foram **removidas** e tudo migrou para **métodos ObjC nos context managers**:

- **Substituto exato e completo de `IGMobileConfigBooleanValueForInternalUse`:**
  `-[IGMobileConfigContextManager getBool:(mc_bool_param_t)]` (e as variantes
  `getBool:withDefault:`, `getBool:withOptions:`, `getBool:withOptions:withDefault:`),
  além dos mesmos métodos em `FBMobileConfigContextManager`, `FBMobileConfigContextObjcImpl`,
  `FBMobileConfigUserSessionContextManager` e `FBMobileConfigSessionlessContextManager`.
  A assinatura é `B24@0:8{mc_bool_param_t=Q}16` — recebe um param ID (uint64 embrulhado
  num struct de 1 campo) e devolve BOOL. É **estruturalmente idêntico** ao antigo símbolo C,
  só que agora é um método ObjC.
- **Não sobrou nenhuma função C de "internal use bool"** — confirmado varrendo todos os
  símbolos importados pelo IG ∩ exportados pelo FBShared. Os únicos símbolos C que restaram
  são de gerência (`getMobileConfigManager(id<FBMobileConfigContext>)`,
  `getMobileConfigGlobalContextInstance()`, `IGMobileConfigSetConfigOverrides`,
  `IGMobileConfigForceUpdateConfigs`), todos retornando/operando sobre o manager ObjC.

**Consequência prática (por que "ficou melhor e mais fácil"):** um único hook em `getBool:`
no context manager intercepta **todas** as leituras de MobileConfig — inclusive as
internal-use — em vez de exigir dezenas de hooks em funções C fragmentadas. O tweak **já tem**
essa infraestrutura: `SCIMobileConfigRuntimeHooks.x` hooka `getBool:`/`getInt64:`/`getDouble:`/
`getString:` (todas as variantes) nos 7 context managers e faz **captura + override seletivo
por param ID** (`recordParamID:` / `overrideForParamID:`). Ou seja, o caminho ObjC unificado já
cobre o que o `SCIInternalUseGateHook.x` (símbolo C) fazia.

**Ajuste aplicado:** em `SCIInternalUseGateHook.x`, o símbolo `IGMobileConfigBooleanValueForInternalUse`
foi anotado como removido na 438 (o rebind vira no-op seguro, mantido pra builds <438). Os outros
2 símbolos do arquivo (`IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18`,
`MEBIsMinosDogfoodMekEncryptionVersionEnabled`) continuam presentes e válidos.

---

## 2. Novo framework de experiments (438) — módulo `SCIExperimentForce`

Mapeei três superfícies novas e criei um módulo dedicado (`src/Features/Experimental/SCIExperimentForce.{h,x}`)
que as cobre com **override seletivo** (nunca "força YES cego", que quebraria o app com experiments
conflitantes/mutuamente exclusivos).

### G1 — Managers unificados (o mecanismo genérico mais poderoso)
- `FBCCIGExperimentManager` e `FBCustomExperimentManager`
- `-isFeatureEnabled:(uint64)` / `-isFeatureEnabledWithoutLogging:(uint64)` → `B24@0:8Q16`
- `-getFeatureIntValue:(uint64)` / `-getFeatureIntValueWithoutLogging:(uint64)` → `q24@0:8Q16`
- Estrutura idêntica ao `getBool:(param_t)` do MobileConfig (ID → valor). O hook **reusa o
  mesmo pipeline** do `SCIMobileConfigRuntime` (captura por ID + override por ID, tipo `bool`/`int`),
  então a **mesma UI de override do MobileConfig browser** serve pra forçar feature IDs de
  experiment individualmente. Passthrough puro quando não há override.

### G2 — QuickExperiment configs (`*ExperimentConfig`)
- Padrão `+[<Nome>ExperimentConfig isEnabled:(id)context]` — **class method**, `B24@0:8@16`.
  Cada classe é UM experimento nomeado (24 classes na 438; descoberta é dinâmica varrendo a
  runtime por sufixo `ExperimentConfig` + `+isEnabled:` **definido na própria classe**, com
  validação de assinatura BOOL/1-arg pra evitar overloads).
- Override seletivo: `sci_qe_force_<NomeClasse>` força só aquela; `sci_qe_force_all` (pref de
  **risco explícita**) força todas. Passthrough caso contrário.

### G3 — Helpers específicos (curados e validados)
- `IGExperimentalNavigationState.isNavigationOptionSelectionEnabled` / `.isReelsFirstOverrideEnabled`
  (instance, `B16@0:8`) e `IGAnimatedImageGating.isAnimatedImageOOMFixEnabled` (class, `B16@0:8`),
  forçados por `sci_exp_helpers`.
- **Deixados de fora de propósito:** `isNoOverrideEnabled` (forçar YES anularia as outras
  seleções) e helpers que recebem param-ID uint64 como `isSwiftMigrationEnabledWithParam:`
  (teriam o mesmo problema de "forçar tudo" — candidatos ao override por ID do G1).

Segurança/instalação: gate por pref (`+anyEnabled`), install único em `DidBecomeActive`
(`SCIInstallOnceOnActive`, sem escada de timer — ver `CLAUDE.md`), varredura de classlist e
`objc_getClass` são seguras em qualquer ponteiro, e só `MSHookMessageEx` em métodos ObjC. As
prefs mestras foram registradas no crash-guard (`SCIExperimentalGuard`).

---

## 3. Revalidação ponto a ponto (o que já existia, contra 438)

| Área | Resultado na 438 | Ação |
|---|---|---|
| **Símbolos C EasyGating** (4) | todos import IG + export FB ✓ | sem mudança |
| **Símbolos C MobileConfig InternalUse** (3) | 2 ✓; `IGMobileConfigBooleanValueForInternalUse` **removido** | anotado (§1) |
| **Símbolos C SessionedMC** (3) | todos ✓ | sem mudança |
| **MobileConfigRuntimeHooks** — 7 context managers + IGDogfooderProd | todos presentes ✓ (as 4 classes FB reais retargeted na sessão anterior seguem certas; as 4 antigas seguem ausentes) | sem mudança |
| **SCIIGDSLauncherConfigHook** — 46 getters | 45 ✓; `isPrismIndigoButtonM1DirectEnabled` **removido** na 438 | anotado + **4 getters M4 novos adicionados** (`isPrismCameraIconM4Enabled`, `...Compose...`, `...Photo...`, `...Save...`) |
| **LiquidGlass** — 8 getters no LauncherConfig | cobertura completa ✓ | sem mudança |
| **Wordmark (IGWord)** — 4 getters | todos ✓ | sem mudança |
| **LiquidGlassTabBarMode** — `setScaleProgress:`/`scaleDownWithInteraction:` | ✓ | sem mudança |
| **applyLiquidGlass** — alvos ObjC/Swift | ✓, exceto `isPanGestureEnabled` **removido** de `IGLiquidGlassInteractiveTabBar` | trocado pelo getter novo real `accidentalSwipeOptimizationEnabled` |
| **Story Tray** — `IGHomecomingConfiguration` | 3 dos 6 sumiram | `isFeedCullingOnStoriesAccessEnabled`→**renomeado** `isFeedCullingOnStatusBarEnabled`; removidos `showCinemaStoriesTrayOnSwipeUp`/`isVerticalStoriesTray`; **adicionados** `isOverlayStoriesTrayEnabled` + `enableCollapsedTrayBackground` (cosmético, a pedido) |
| **IGPlus Eligibility** — 8 alvos | todos ✓ com kind instance/class correto (fix da sessão anterior segue válido) | sem mudança |
| **IGPlus ConsumerSubs** — 17 benefitSels + isBenefitActive: + isPeekActive | todos ✓ | **4 benefícios novos adicionados** (`isChatFontsBenefitEnabled`, `isStoryFontsBenefitEnabled`, `isLinksInMediaBenefitEnabled`, `isStoryViewNotifyBenefitEnabled`) com prefs alinhadas |
| **Employee / Debug Menus** — 10 alvos | todos ✓ | **classe Swift nova adicionada**: `IGAdPlatformLogger_swift.isEmployee` (caminho Swift de employee que não existia na 433) |

---

## 4. Verificação pendente (device)

1. `make clean && make` — não compilei. Checagem estática de `{}`/`()`/`[]` e `#import` OK em tudo que toquei.
2. Boot real + toggles. Em especial, validar em device:
   - o novo `SCIExperimentForce` (G1 captura no MobileConfig browser; G2 `sci_qe_force_<Nome>`; G3 `sci_exp_helpers`);
   - os 4 getters Prism M4 e os 4 benefícios IGPlus novos;
   - a troca de `isPanGestureEnabled`/culling e o overlay/collapsed tray.
3. G2 descobre as `*ExperimentConfig` por varredura de runtime — confirmar que `sci_qe_force_all` não ativa combinações que quebrem o app (por isso é pref de risco separada; comece por classes individuais).
