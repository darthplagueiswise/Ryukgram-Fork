# Instagram / FBSharedFramework — auditoria real com r2, Capstone e LIEF

Data: 2026-07-17

## Binários auditados

- `Instagram`: SHA-256 `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: SHA-256 `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`
- Ambos são Mach-O arm64.

## Ferramentas usadas

- radare2 `5.9.8`, compilado com Capstone 5
- Python Capstone `5.0.7`
- LIEF `1.0.0-d05b3499b`

O r2 foi usado em modo raw/arm64 para os offsets virtuais obtidos da metadata Mach-O por LIEF; Capstone foi usado como segunda decodificação independente.

## 1. Por que Internal Settings aparece mas não executa

Classe: `_TtC17IGBugReporterMenu29IGBugReportMenuViewController`.

Initializer atual:

```
initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:
@104@0:8@16@24@32@40@48@56q64q72B80B84B88B92q96
```

Ivars reais:

- `deviceSession` em `0x10`
- `userSession` em `0x18`
- `style` em `0x20`
- `internalSettingsAvailabilityStatus` em `0x78`
- `showInternalSettings` em `0x80`
- `showLoggedOutInternalSettings` em `0x81`
- `showShakeToReportPreferenceToggle` em `0x82`
- `showDogfoodingAssistant` em `0x83`
- `maisaUXVariant` em `0x84`
- lazy storage de `dogfoodingAssistantSocket` em `0x85`, com apenas um byte — não é `id` Objective-C.

O jump table de `tableView:didSelectRowAtIndexPath:` identifica:

- seção 6: Dogfooding Assistant
- seção 7: Internal Settings

O `shouldHighlight` nativo já permite essas seções. O bloqueio real é duplo:

1. `maisaUXVariant` control(0) e additive(3) deixam as action cells desabilitadas; rowsGrouped(1) satisfaz o predicado nativo.
2. No handler de Internal Settings, `style == 2` usa a rota logged-out, `style == 0` usa a rota logged-in e `style == 1` chega ao no-op exato (`cbnz style -> cleanup`).

Correção publicada:

- força `maisaUXVariant=1` somente quando os gates internos estão ligados;
- normaliza `style` para 0 com sessão e 2 sem sessão na rota logged-out;
- reaplica o estado antes de construir a célula, no highlight e imediatamente antes do handler Swift original;
- captura `userSession` e `deviceSession` pelos offsets reais, sem rejeitar os ivars Swift por terem type encoding vazio;
- nunca transforma o socket Swift em objeto Objective-C e não usa DirectNotes como fallback.

## 2. Dogfooding Assistant

A rota nativa da seção 6 usa o lazy storage Swift e um action/vtable call (`blr`) construído pelo próprio Instagram. O patch anterior procurava provider/socket apenas entre ivars Objective-C e, por isso, não podia resolver o socket de um byte.

A correção mantém o handler Swift original autoritativo, garante `showDogfoodingAssistant=1`, `maisaUXVariant=1` e preenche `deviceSession` a partir de `IGUserSession.deviceSession` quando o menu recebeu nil.

## 3. Sessionless MobileConfig

A hipótese anterior `FBMobileConfigFBTGlobalSessionManager -> holder` não é suficiente neste processo: o print confirmou `sessionlessContextManagerHolder=nil`.

O executável contém três chamadas do startup para o import `IGMobileConfigTryUpdateConfigsWithCompletion`. Na rota sessionless em torno de `0x102c5604c`, os objetos são obtidos do `IGDeviceSession`:

- `deviceSession.mobileConfig`
- `deviceSession.loggedOutNetworker`
- custom hours nil
- completion em x3

O export em FBSharedFramework fica em `0x72da74` e é um wrapper de quatro argumentos:

```
mov w4, #0
b 0x72fee4
```

Logo, o quinto argumento privado é fornecido pelo próprio wrapper OEM. A assinatura pública usada pelo patch é:

```
void IGMobileConfigTryUpdateConfigsWithCompletion(
    id mobileConfig,
    id loggedOutNetworker,
    id customHours,
    void (^completion)(BOOL success)
);
```

A implementação publicada resolve o `IGDeviceSession` vivo, valida os getters `mobileConfig` e `loggedOutNetworker`, resolve o export por `dlsym`, chama o wrapper OEM e acompanha o BOOL de conclusão. O capture layer inicial também foi movido para antes de `UIApplicationDidBecomeActive` e cobre:

- `IGMobileConfigSessionlessContextManager initWithManager:` com ABI shared_ptr indireta;
- `FBMobileConfigFBTContextManager initWithFbtToMCIdMapping:mobileconfig:`;
- setup/getters/setters do holder e FBT manager;
- factories sessionless, substituindo o singleton vazio apenas quando há um contexto nativo capturado com manager válido.

## 4. Employee, test user e dogfood

A varredura completa de métodos Objective-C encontrou zero getters reais chamados `isTestUser`, `isDogfooder` ou `isEmployeeOrTestUser` com ABI BOOL sem argumentos. Esses nomes não foram inventados.

Getters reais de identidade:

- `IGFacebookUserInfo -isEmployee` (`B16@0:8`)
- `IGAdPlatformLogger_objc -isEmployee`
- `_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift -isEmployee`

A informação employee/test-user também aparece em Pando via `asIGUserIsEmployeeOrTestUserFragmentImmutableModel` e `accountBadges` (`IS_EMPLOYEE` / `IS_TEST_USER`), não como um getter BOOL genérico.

Foram adicionados hooks nos consumidores reais que recebem os booleans como argumentos:

- `IGFeedRequestQPLogger ... isEmployee:isTestUser:` — força ambos;
- `IGSeenStateLogger initWithIsEmployee:analyticsLogger:`;
- `IGSeenStateStore initWithDependencies:isEmployee:`;
- `IGLeadGenAnalyticsLogger ... isEmployee:`;
- `BKBloksLabDeeplinkHelper ... isEmployee:...`;
- `IGBugReportMenuReliabilityLogger markInternalSettingsEnabled:`.

Dogfood real adicional:

- `IGIdentitySwitcherGatingHelper isFbAcquisitionEpDogfoodModeEnabled`;
- `IGSearchSerpMediaGridRowSectionController showDogfoodFeedback`;
- `IGDirectSmartSuggestionsSuggestedActionHelpers directSmartSuggestionsIsForceBannerForDogfoodingEnabled:`.

Todos os hooks validam classe, seletor e ABI exata e leem o master ao vivo. Os descritores `_ig_is_employee` e `_ig_is_employee_or_test_user` continuam tratados como DATA, nunca como funções.

## Arquivos publicados

- `src/Features/Dogfooding/SCIBugMenuOEMActivation.m`
- `src/Features/Dogfooding/SCIEmployeeIdentityConsumerHooks.m`
- `src/Features/Dogfooding/SCISessionlessMobileConfigEarlyCapture.m`
- `src/Features/Dogfooding/SCIValidatedOEMResolvers.m`
- `src/Features/Dogfooding/SCIDogfoodObjectRuntime.h`
