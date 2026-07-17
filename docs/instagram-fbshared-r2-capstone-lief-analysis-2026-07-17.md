# Instagram / FBSharedFramework — auditoria real com radare2 e Capstone

Data: 2026-07-17

## Binários auditados

- `Instagram`: SHA-256 `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: SHA-256 `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`
- Ambos: Mach-O arm64.

## Ferramentas

- radare2 `6.1.8`, backend Capstone 5
- Python Capstone `5.0.7`
- LIEF `1.0.0-d05b3499b` para metadata/segmentos; nos blocos grandes, um mapper Mach-O independente extraiu as slices exatas e evitou depender de um único parser.

Cada bloco crítico abaixo foi decodificado por r2 e novamente por Python Capstone. Os endereços, branches e instruções relevantes coincidiram.

## 1. Por que as linhas apareciam mas continuavam sem tap

Classe do menu:

`_TtC17IGBugReporterMenu29IGBugReportMenuViewController`

Ivars reais:

- `deviceSession`: `0x10`
- `userSession`: `0x18`
- `style`: `0x20`
- `internalSettingsAvailabilityStatus`: `0x78`
- `showInternalSettings`: `0x80`
- `showLoggedOutInternalSettings`: `0x81`
- `showShakeToReportPreferenceToggle`: `0x82`
- `showDogfoodingAssistant`: `0x83`
- `maisaUXVariant`: `0x84`
- lazy storage Swift de `dogfoodingAssistantSocket`: `0x85`, um byte; não é `id` Objective-C.

Action tags Swift no `tableView:didSelectRowAtIndexPath:`:

- `6`: Dogfooding Assistant, branch `0x104aaf978`
- `7`: Internal Settings, branch `0x104aaf69c`

Esses valores não são `NSIndexPath.section`.

O patch anterior corrigia `shouldHighlight`, `didSelect` e `userInteractionEnabled`, mas isso ainda não alcançava o controle que recebe o toque. As linhas são subclasses próprias com um `IGTextButton` interno:

- `_TtC17IGBugReporterMenu21IGBugReportActionCell`
- `_TtC17IGBugReporterMenu25IGBugReportLinkActionCell`

Métodos exatos:

- Action cell `setEnabled:` em `0x10970f808`
- Link action cell `setEnabled:` em `0x10970f85c`
- Action cell `tapped` em `0x105e6c810`
- Link action cell `tapped` em `0x105e6c824`
- Controller `bugReportingActionCellButtonTapped:` em `0x1084c3a94`
- Controller `bugReportingLinkActionCellButtonTapped:` em `0x10851549c`

r2 e Capstone mostram que ambos os `setEnabled:` carregam o botão interno e encaminham o BOOL de `x2` ao controle. Portanto habilitar apenas a `UITableViewCell` não habilita o botão.

As rotas `tapped` são thunks para o delegate próprio. Logo, `tableView:didSelectRowAtIndexPath:` não é a única nem a principal rota para essas action cells.

### Correção

`SCIBugMenuActionCells.m` agora:

- intercepta `setCellText:` e identifica exatamente `Dogfooding Assistant` e `Internal Settings`;
- força os getters/setters `enabled` das duas classes somente para as células-alvo e somente com o master correspondente;
- chama o `setEnabled:YES` nativo, que habilita o `IGTextButton` interno;
- intercepta os dois callbacks `bugReporting*CellButtonTapped:`;
- antes do callback Swift original, aplica os ivars exatos, availability `0`, `maisaUXVariant=1` e style `0` com sessão ou `2` sem sessão;
- sempre encaminha ao handler nativo original;
- não cria socket, provider ou controller sintético.

## 2. Internal Settings e Dogfooding Assistant

No branch Internal Settings (`0x104aaf69c`):

- raw availability `0` segue para abertura;
- raw `1` e `3` retornam silenciosamente;
- raw `2` entra no alerta de acesso negado;
- style `0` é a rota logged-in;
- style `2` é a rota logged-out;
- style `1` é no-op.

No branch Assistant (`0x104aaf978`), o Instagram usa o lazy storage Swift e um witness/vtable call nativo. A correção preserva esse branch e não tenta transformar o storage de um byte em objeto Objective-C.

## 3. Sessionless MobileConfig real

O alerta de runtime provou que `FBMobileConfigFBTGlobalSessionManager.sessionlessContextManagerHolder` pode ser `nil` neste processo. Portanto essa cadeia não pode ser requisito para o fetch.

A rota startup real no executável chama `IGMobileConfigTryUpdateConfigsWithCompletion` em torno de `0x102c5604c` com:

- `x0 = deviceSession.mobileConfig`
- `x1 = deviceSession.loggedOutNetworker`
- `x2 = nil`
- `x3 = completion`

Export no FBSharedFramework:

`_IGMobileConfigTryUpdateConfigsWithCompletion` em `0x72da74`

r2 e Capstone:

```asm
0x72da74  mov w4, #0
0x72da78  b   0x72fee4
```

O wrapper público recebe quatro argumentos e fornece o quinto privado internamente.

A implementação resolve o `IGDeviceSession` vivo, valida `mobileConfig` e `loggedOutNetworker`, resolve o export por `dlsym` e chama a ponte com a ABI de quatro argumentos.

A chamada manual anterior a `_refreshStartupConfigs(mobileConfig, nil, nil)` foi removida. A função real em `0x95577c` preserva e usa três objetos e percorre uma tabela grande; os call sites nativos constroem dependências próprias. Chamar com argumentos inventados não era equivalente ao fluxo OEM.

## 4. Botão nativo Force MobileConfig re-fetch

O action builder no branch Internal Settings passa em `x3` a closure Swift exata:

- construção da action: `0x104aaf748`
- closure: `0x105824584`

Primeiros 16 bytes validados:

```text
e0 03 1e aa 10 18 38 97 fe 03 00 aa fd 7b 05 a9
```

Capstone:

```asm
mov x0, x30
bl  0x10262a5c8
mov x30, x0
stp x29, x30, [sp, #0x50]
```

O action não é garantidamente `UIAlertAction`; por isso o hook global em `+[UIAlertAction actionWithTitle:style:handler:]` foi removido.

`SCILoggedOutMobileConfigActionHook.m` usa `MSHookFunction` somente no VA auditado e somente depois de validar a assinatura de instruções. A closure chama a ponte OEM concreta. Se a ponte não tiver os objetos vivos, encaminha para a closure Swift original; se o fetch foi iniciado, não reentra no placeholder remoto.

## 5. Employee, test user, dogfood, dogfooder e internal

A metadata dos dois binários não contém getters Objective-C no-arg BOOL reais chamados genericamente `isTestUser`, `isDogfooder` ou `isEmployeeOrTestUser`. Esses seletores não são inventados.

Getters diretos reais incluem:

- `IGFacebookUserInfo -isEmployee`
- `IGAdPlatformLogger_objc -isEmployee`
- `IGAdPlatformLogger_swift -isEmployee`

Consumidores reais com argumentos employee/test-user cobertos:

- `IGFeedRequestQPLogger ... isEmployee:isTestUser:`
- `IGSeenStateLogger initWithIsEmployee:analyticsLogger:`
- `IGSeenStateStore initWithDependencies:isEmployee:`
- `IGLeadGenAnalyticsLogger ... isEmployee:`
- `BKBloksLabDeeplinkHelper ... isEmployee:...`
- `IGBugReportMenuReliabilityLogger markInternalSettingsEnabled:`

Dogfood real coberto:

- `IGIdentitySwitcherGatingHelper isFbAcquisitionEpDogfoodModeEnabled`
- `IGSearchSerpMediaGridRowSectionController showDogfoodFeedback`
- `IGDirectSmartSuggestionsSuggestedActionHelpers directSmartSuggestionsIsForceBannerForDogfoodingEnabled:`
- `IGBlendedSearchRecentItemsOrderStore shouldAttemptToForceRestoreRecentsForEmployee` e setter

O runtime adicional percorre somente classes relevantes e instala aliases de employee/test/dogfood/internal apenas quando o método já existe e sua ABI é exatamente BOOL getter/setter. Ele não adiciona seletor inexistente.

Os descritores `ig_is_employee` e `ig_is_employee_or_test_user` permanecem DATA e são forçados pelo reader de MobileConfig filtrado pelo endereço do descritor; nunca são chamados como função.

Pando continua coberto pelos accessors reais:

- `asIGUserIsEmployeeOrTestUserFragmentImmutableModel`
- `asIGDogfooderInformationFragmentImmutableModel`
- `asIGFirstTimeDogfooderFragmentImmutableModel`
- `asIGDogfoodingFirstShowIssueFragmentImmutableModel`
- `asIGInternalSettingsAvailabilityFragmentImmutableModel`

## Arquivos finais

- `src/Features/Dogfooding/SCIBugMenuOEMActivation.m`
- `src/Features/Dogfooding/SCIBugMenuActionCells.m`
- `src/Features/Dogfooding/SCIEmployeeIdentityConsumerHooks.m`
- `src/Features/Dogfooding/SCIEmployeeTestDogfoodRuntimeHooks.m`
- `src/Features/Dogfooding/SCISessionlessMobileConfigEarlyCapture.m`
- `src/Features/Dogfooding/SCILoggedOutMobileConfigActionHook.m`
- `src/Features/Dogfooding/SCIValidatedOEMResolvers.m`
