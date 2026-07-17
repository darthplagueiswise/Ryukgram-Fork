# Instagram / FBSharedFramework — auditoria real com r2, Capstone e LIEF

Data: 2026-07-17

## Binários auditados

- `Instagram`: SHA-256 `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: SHA-256 `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`
- Ambos são Mach-O arm64.

## Ferramentas usadas

- radare2 `5.9.8`, backend Capstone 5
- Python Capstone `5.0.7`
- LIEF `1.0.0-d05b3499b`

O r2 foi usado em modo arm64 nos offsets virtuais obtidos da metadata Mach-O por LIEF. Os blocos críticos foram depois decodificados novamente com Python Capstone; os dois decoders deram a mesma estrutura de jump table, máscaras e branches.

## 1. Por que Internal Settings e Dogfooding Assistant aparecem, mas não recebem tap

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
- lazy storage de `dogfoodingAssistantSocket` em `0x85`, com um byte; não é `id` Objective-C.

O jump table de `tableView:didSelectRowAtIndexPath:` identifica os action tags Swift:

- action tag `6`: Dogfooding Assistant, branch `0x104aaf978`
- action tag `7`: Internal Settings, branch `0x104aaf69c`

Esses números são tags do modelo Swift, não `NSIndexPath.section`. A implementação anterior tratava `indexPath.section == 6/7` como se fosse o action tag, portanto podia não aplicar a correção na célula real.

O bloqueio principal está em `tableView:shouldHighlightRowAtIndexPath:`. Capstone em `0x106cf2ee0`:

```asm
and  w9, w0, #0xff
tst  w9, #0x1fe0
b.ne 0x106cf2f2c
mov  w19, #0
mov  w8, #0xe017
tst  w9, w8
b.ne 0x106cf2f30
```

Os action tags 6 e 7 falham no segundo teste e retornam `NO`. Logo, alterar apenas os ivars `showInternalSettings`/`showDogfoodingAssistant` faz as linhas aparecerem, mas não faz o delegate aceitar highlight/seleção.

Há mais dois gates:

1. `maisaUXVariant` control (`0`) e additive (`3`) deixam as action cells desabilitadas; rowsGrouped (`1`) satisfaz o predicado nativo.
2. No handler de Internal Settings, availability `0` abre, `1` retorna silenciosamente, `2` mostra access denied e `3` também retorna. Mais adiante, `style == 0` usa a rota logged-in, `style == 2` usa a rota logged-out e `style == 1` cai no no-op.

Correção publicada:

- identifica a célula real pelo título emitido pelo binário e grava um associated tag na própria célula;
- não usa mais `indexPath.section` como action tag;
- força interaction/highlight somente para as duas células-alvo e somente quando os gates correspondentes estão ativos;
- no tap exato de Internal Settings aplica availability `0`, `maisaUXVariant=1` e style `0` com sessão ou `2` sem sessão;
- no tap exato do Assistant aplica `showDogfoodingAssistant=1` e `maisaUXVariant=1`;
- encaminha sempre para o handler Swift original;
- captura `userSession` e `deviceSession` pelos offsets reais, mesmo com type encoding Swift vazio;
- nunca converte o socket Swift de um byte em objeto Objective-C e não usa DirectNotes como fallback.

## 2. Dogfooding Assistant

A rota nativa da action tag 6 usa o lazy storage Swift e um action/vtable call (`blr`) construído pelo próprio Instagram. O patch anterior procurava provider/socket apenas entre ivars Objective-C e não podia resolver o storage de um byte.

A correção não sintetiza esse socket. Ela torna a célula selecionável, preenche `deviceSession` por `IGUserSession.deviceSession` quando necessário e deixa o branch nativo `0x104aaf978` executar.

## 3. Sessionless MobileConfig

A cadeia `FBMobileConfigFBTGlobalSessionManager -> holder` não é suficiente neste processo: o runtime mostrou `sessionlessContextManagerHolder=nil`.

O executável contém chamadas do startup para `IGMobileConfigTryUpdateConfigsWithCompletion`. Na rota sessionless em torno de `0x102c5604c`, os objetos são obtidos do `IGDeviceSession`:

- `deviceSession.mobileConfig`
- `deviceSession.loggedOutNetworker`
- custom hours `nil`
- completion em `x3`

O export em FBSharedFramework fica em `0x72da74`. r2 e Capstone mostram:

```asm
mov w4, #0
b   0x72fee4
```

O quinto argumento privado é fornecido pelo wrapper OEM. A assinatura pública usada é:

```objc
void IGMobileConfigTryUpdateConfigsWithCompletion(
    id mobileConfig,
    id loggedOutNetworker,
    id customHours,
    void (^completion)(BOOL success)
);
```

A implementação resolve o `IGDeviceSession` vivo, valida os getters `mobileConfig` e `loggedOutNetworker`, resolve o export por `dlsym`, chama o wrapper OEM e registra o BOOL de conclusão. A captura inicial foi movida para antes de `UIApplicationDidBecomeActive` e cobre também os constructors/holders nativos quando eles existirem.

O texto remoto `Implement Bloks Action` não aparece nos binários auditados. Portanto ele não pode ser usado como seletor local confiável; a substituição do `UIAlertAction` limita-se ao título nativo `Force MobileConfig re-fetch`. O botão Dev chama diretamente a ponte OEM acima.

## 4. Employee, test user e dogfood

A varredura de metadata e strings encontrou zero getters Objective-C reais chamados `isTestUser`, `isDogfooder` ou `isEmployeeOrTestUser` com ABI BOOL sem argumentos. Esses métodos não são adicionados artificialmente.

Getters reais de identidade:

- `IGFacebookUserInfo -isEmployee` (`B16@0:8`)
- `IGAdPlatformLogger_objc -isEmployee`
- `_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift -isEmployee`

Employee/test-user também aparece no Pando em `asIGUserIsEmployeeOrTestUserFragmentImmutableModel` e `accountBadges` (`IS_EMPLOYEE` / `IS_TEST_USER`), não como getter BOOL genérico.

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
- `IGDirectSmartSuggestionsSuggestedActionHelpers directSmartSuggestionsIsForceBannerForDogfoodingEnabled:`;
- `IGBlendedSearchRecentItemsOrderStore shouldAttemptToForceRestoreRecentsForEmployee` e setter.

Todos os hooks validam classe, seletor e ABI exata e leem o master ao vivo. Os descritores `_ig_is_employee` e `_ig_is_employee_or_test_user` continuam tratados como DATA, nunca como funções.

## Arquivos publicados

- `src/Features/Dogfooding/SCIBugMenuOEMActivation.m`
- `src/Features/Dogfooding/SCIEmployeeIdentityConsumerHooks.m`
- `src/Features/Dogfooding/SCISessionlessMobileConfigEarlyCapture.m`
- `src/Features/Dogfooding/SCIValidatedOEMResolvers.m`
- `src/Features/Dogfooding/SCIDogfoodObjectRuntime.h`
