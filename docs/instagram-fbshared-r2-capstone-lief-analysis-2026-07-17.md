# Instagram / FBSharedFramework — auditoria real com Radare2, Capstone e LIEF

Data: 2026-07-17

## Binários auditados

- `Instagram`: SHA-256 `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: SHA-256 `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`
- Ambos são Mach-O arm64.

## Ferramentas realmente executadas

- Radare2 core por meio do build Emscripten `r2core`, em `asm.arch=arm`, `asm.cpu=v8`, `asm.bits=64`.
- Python Capstone `5.0.7`, modo ARM64 little-endian.
- LIEF `1.0.0-d05b3499b` para segmentos, offsets virtuais e exports Mach-O.
- `llvm-objdump --macho --objc-meta-data` como verificação adicional da metadata Objective-C.

Os blocos críticos foram extraídos do Mach-O real, decodificados pelo Radare2 e novamente pelo Capstone. Os dois decoders produziram as mesmas branches, máscaras, jump tables e passagem de argumentos.

## 1. Por que Internal Settings e Dogfooding Assistant aparecem, mas não recebem tap

Classe: `_TtC17IGBugReporterMenu29IGBugReportMenuViewController`.

Initializer atual:

```text
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

Esses números são tags do modelo Swift, não `NSIndexPath.section`. A implementação antiga não cobria o gate real de highlight.

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

Os action tags 6 e 7 falham no segundo teste e retornam `NO`. Logo, alterar apenas `showInternalSettings` e `showDogfoodingAssistant` faz as linhas aparecerem, mas não faz o delegate aceitar highlight ou seleção.

Há mais dois gates:

1. `maisaUXVariant` control (`0`) e additive (`3`) deixam essas action cells desabilitadas; rowsGrouped (`1`) satisfaz o predicado nativo.
2. No handler de Internal Settings, availability `0` abre, `1` retorna silenciosamente, `2` mostra access denied e `3` também retorna. `style == 0` usa a rota logged-in, `style == 2` usa a rota logged-out e `style == 1` cai no no-op.

Correção publicada:

- identifica a célula real pelo título emitido pelo binário e grava um associated tag na própria célula;
- não usa `indexPath.section` como action tag;
- força interaction/highlight somente para `Internal Settings` e `Dogfooding Assistant`, e somente quando os gates correspondentes estão ativos;
- no tap de Internal Settings aplica availability `0`, `maisaUXVariant=1` e style `0` com sessão ou `2` sem sessão;
- no tap do Assistant aplica `showDogfoodingAssistant=1` e `maisaUXVariant=1`;
- encaminha sempre para o handler Swift original;
- captura `userSession` e `deviceSession` pelos offsets reais;
- nunca converte o socket Swift de um byte em objeto Objective-C e não usa DirectNotes como fallback.

## 2. Internal Settings repete a decisão employee/test-user

`-[IGBugReportMenuViewController tableView:didSelectRowAtIndexPath:]`

- VA `0x104aaf610`
- ABI `v32@0:8@16@24`

Radare2 e Capstone resolvem o jump-table dispatch:

```asm
0x104aaf660  bl    0x101396afc
0x104aaf664  and   w11, w0, #0xff
0x104aaf668  adrp  x8, 0x10a702000
0x104aaf66c  add   x8, x8, #0x2dc
0x104aaf674  ldrsw x9, [x8, x11, lsl #2]
0x104aaf67c  br    x10
```

O branch negado referencia diretamente:

```asm
0x104aaf850  "Internal Settings Access Denied"
0x104aaf85c  "Only employees or test accounts ..."
```

Portanto `showInternalSettings=YES` é apenas um gate de exibição. O tap repete uma decisão employee-or-test-user.

## 3. Dogfooding Assistant

A rota nativa da action tag 6 usa lazy storage Swift e um action/vtable call (`blr`) construído pelo próprio Instagram. O patch antigo procurava provider/socket apenas entre ivars Objective-C e não podia resolver o storage de um byte.

A correção não sintetiza esse socket. Ela torna a célula selecionável, preenche `deviceSession` por `IGUserSession.deviceSession` quando necessário e deixa o branch nativo `0x104aaf978` executar.

## 4. Sessionless MobileConfig

A cadeia `FBMobileConfigFBTGlobalSessionManager -> holder` não é o owner confiável neste processo: o runtime mostrou `sessionlessContextManagerHolder=nil`.

O executável contém a rota OEM em `IGAppJobsDefaultRunner startupAnalyzerDidEnd`. Na chamada sessionless em torno de `0x102c5604c`, os objetos vêm do `IGDeviceSession`:

- `deviceSession.mobileConfig`
- `deviceSession.loggedOutNetworker`
- custom hours `nil`
- completion em `x3`

O export em FBSharedFramework fica em `0x72da74`. Radare2 e Capstone mostram:

```asm
mov w4, #0
b   0x72fee4
```

O quinto argumento privado é fornecido pelo wrapper OEM. A assinatura pública validada é:

```objc
void IGMobileConfigTryUpdateConfigsWithCompletion(
    id mobileConfig,
    id loggedOutNetworker,
    id customHours,
    void (^completion)(BOOL success)
);
```

A implementação agora resolve o `IGDeviceSession` vivo, valida `mobileConfig` e `loggedOutNetworker`, resolve o export por `dlsym`, chama o wrapper OEM e registra o BOOL de conclusão. A captura cobre os argumentos dos initializers reais do Bug Reporter e também os constructors/holders nativos quando estes existirem.

O texto remoto `Implement Bloks Action` não aparece nos binários auditados. A substituição local limita-se à ação nativa `Force MobileConfig re-fetch`; o botão Dev chama diretamente a ponte OEM acima.

## 5. Employee, test user, dogfood, dogfooder, dogfooding e internal

Os descritores `ig_is_employee` e `ig_is_employee_or_test_user` são DATA de 16 bytes. Eles não são funções e nunca devem ser entregues a fishhook/MSHookFunction como BOOL callables.

Getters confirmados diretamente:

- `IGFacebookUserInfo -isEmployee` (`B16@0:8`)
- `IGAdPlatformLogger_objc -isEmployee`
- `_TtC28IGAdInsertionLoggingKitSwift24IGAdPlatformLogger_swift -isEmployee`

A string de seletor `isTestUser` existe uma vez no Mach-O, mas não apareceu como getter BOOL validado na metadata estática. Por isso a extensão runtime não inventa método: ela percorre apenas classes relevantes já carregadas e instala hook somente quando a classe realmente declara um dos aliases e a ABI é exatamente `B16@0:8`, `c16@0:8` ou `C16@0:8`.

Aliases cobertos quando realmente existentes:

- `isTestUser`, `isTestAccount`
- `isEmployeeOrTestUser`, `isEmployeeOrTestAccount`
- `isDogfooder`, `isDogfood`, `isDogfooding`
- `isInternalUser`, `isInternal`
- `isMetaEmployee`, `isFacebookEmployee`
- setters BOOL correspondentes

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

Além disso, enquanto o master Employee / Internal está ativo, `ig_is_employee` e `ig_is_employee_or_test_user` são forçados pelo reader MobileConfig filtrado pelo ponteiro exato do descriptor. O estado anterior de cada override é salvo e restaurado quando o master é desligado.

## Arquivos publicados

- `src/Features/Dogfooding/SCIBugMenuOEMActivation.m`
- `src/Features/Dogfooding/SCIEmployeeIdentityConsumerHooks.m`
- `src/Features/Dogfooding/SCIEmployeeTestDogfoodRuntimeHooks.m`
- `src/Features/Dogfooding/SCISessionlessMobileConfigEarlyCapture.m`
- `src/Features/Dogfooding/SCIValidatedOEMResolvers.m`
- `src/Features/Dogfooding/SCIDogfoodObjectRuntime.h`
