# RyukGram-Fork — Plano de Hooks Validado (Instagram 429 + FBSharedFramework)

Todos os endereços/classes abaixo foram validados via `lief` + `capstone` nos binários
atuais. **Lição:** endereços hardcoded quebram entre versões → usar `dlsym` para
símbolos exportados e `NSClassFromString`/`%hook` para ObjC.

## Princípio de segurança (sideload)
- ObjC: `%hook` (Logos) ou `MSHookMessageEx` — patcha vtable, seguro com trampolines compartilhados
- C exportado: `dlsym` + `MSHookFunction` — **nunca hardcode endereço**
- C importado (GOT): `fishhook rebind_symbols`
- **Nunca**: `objc_copyClassList` no launch, `orig` único p/ múltiplos seletores, `MSHookFunction` em `__TEXT` por endereço fixo

---

## ÁREA 1 — dogfood / employee / internal
| Alvo | Local | Tipo | Estratégia |
|------|-------|------|-----------|
| `IGAutofillInternalSettings.isForceBloksExperienceOn` | IG | `B16@0:8` IMP 0x1031a6a4c | `%hook` → YES |
| `IGAutofillInternalSettings.getDebugFooterEnabled` | IG | trampoline 0x101c07890 | `%hook` (vtable) → YES |
| `IGFacebookUserInfo.isEmployee` | **FBShared** | selector STRIPPED | ⚠️ não resolve por nome — NÃO hookar por seletor |

**Correção:** o employee gate via `IGFacebookUserInfo.isEmployee` por nome era inválido
(seletores Swift stripados em FBShared). Usar apenas a classe IG confirmada.

## ÁREA 2 — debug menus / internal settings
| Alvo | Local | Assinatura | Estratégia |
|------|-------|-----------|-----------|
| `IGBugReportMenuViewController initWith...showInternalSettings:showLoggedOutInternalSettings:...` | IG | IMP 0x103a53b90, BOOLs em offset 80/84 | `%hook` o init, forçar args BOOL = YES |
| `IGBugReportMenuReliabilityLogger.markInternalSettingsEnabled:` | IG | IMP 0x101c074d8 | opcional |

**Este é o gate REAL do menu de internal settings** (shake-to-report), não o autofill.

## ÁREA 3 — internal-only / ig-only
| Alvo | Local | Estratégia |
|------|-------|-----------|
| `IGStoryOpaqueDebugUnderlayViewFactory.shouldShowDebugUnderlay` | IG | `%hook` → YES |
| `IGFeedPublishScreenInternalOnlySectionManager.isInternalOnly` | IG | `%hook` → YES |
| XPlugins `[IG-Only]`/`[Internal]` keys | IG export | sentinel (ver ÁREA 7) |

## ÁREA 4 — IGPlus (client benefits)
| Alvo | Local | Confirmado |
|------|-------|-----------|
| `IGConsumerSubsService` — 17 BOOL getters | IG | ✓ todos `B16@0:8` |
| `SUBSBenefitDataProvider.isBenefitActiveWithBenefitType:` | IG | ✓ |
| Peek eligibility (StoryPeek/DirectChat) | IG | ✓ INSTANCE methods (não class) |

`%hook` cada getter → YES. Já validado em `igconsumer_validation_report.md`.

## ÁREA 5 — MobileConfig / EasyGating
**Todos exportados de FBShared (dlsym-resolvable):**
| Função | FBShared VA | Tipo |
|--------|-------------|------|
| `IGMobileConfigBooleanValueForInternalUse` | 0xd539f8 | bool |
| `IGMobileConfigIntegerValueForInternalUse` | 0xd32d2c | int |
| `IGMobileConfigStringValueForInternalUse` | 0xd5399c | string |
| `IGMobileConfigSetConfigOverrides` | 0x121e548 | setter de overrides |
| `MCIExperimentCacheGetMobileConfigBoolean` | 0x6a7f4c | bool |
| `MCIExperimentCacheGetMobileConfigInt64` | 0x6a802c | int |
| `MSGCSessionedMobileConfigGetBoolean/Int64/String/Double` | 0x1668798/8668/8700/809c | sessioned |

**Estratégia:** Instagram importa via GOT → `fishhook rebind_symbols` no IG.
Master único `sci_force_all_mc_gates`. Por que só "Boolean" funcionava antes:
cada hook tinha pref separado; faltava o master.

## ÁREA 6 — Liquid Glass / IGDS / Prism
| Alvo | Local | Confirmado |
|------|-------|-----------|
| Classe `IGDSLauncherConfig` | **FBShared** `_OBJC_CLASS_$_IGDSLauncherConfig` | ✓ ObjC class real |
| `isLiquidGlass*` (12 métodos) | FBShared methnames | ✓ inclui `_isLiquidGlassEnabled`, `isLiquidGlassToggleEnabled` |
| `isPrism*` / `_isPrism*` (28 métodos) | FBShared methnames | ✓ underscore variants: `_isPrismEnabled`, `_isPrismDesignEnabled`, `_isPrismAvatarRingEnabled` |
| `isIGWordmark1a/1aAlt/1b/1bAlt Enabled` | FBShared methnames | ✓ mutuamente exclusivos |

`%hook`/`MSHookMessageEx` na classe `IGDSLauncherConfig`. **Correção:** versão
anterior usava `isPrismAvatarRingEnabled` (sem underscore) → não existia.

## ÁREA 7 — XPlugins
| Símbolo | IG VA (build atual) | Exported? |
|---------|--------------------|-----------|
| `XPluginsGetListLookupDataPair` | 0x101c4e6c0 | ✓ dynamic |
| `XPluginsGetDataPair` | 0x101c0158c | ✓ dynamic |

**Correção crítica:** versão anterior hardcodava 0x100da3bbc (binário ANTIGO).
Build atual = 0x101c4e6c0. **Solução:** `dlsym(RTLD_DEFAULT, "XPluginsGetListLookupDataPair")`
+ `MSHookFunction` — resolve em runtime, nunca quebra entre versões.
