# Dogfood / Internal — correção da regressão de launch

Data: 2026-07-17

## Sintoma confirmado

Depois da expansão dos hooks de Employee, test user, dogfood, Internal Settings e sessionless MobileConfig, o Instagram passou a demorar excessivamente para abrir.

A regressão estava no bootstrap da tweak, não no fetch de MobileConfig:

- vários módulos registravam `_dyld_register_func_for_add_image` separadamente;
- cada registro repetia lookups para todas as imagens já carregadas e para imagens futuras;
- dois módulos percorriam `objc_getClassList` perto do launch;
- havia dois observers de ativação e dois instaladores para a mesma família;
- `SCIBugMenuOEMActivation` e `SCIEmployeeInternal.x` encadeavam `tableView:didSelectRowAtIndexPath:`;
- initializers/factories sessionless eram interceptados por mais de uma camada.

## Arquitetura corrigida

`SCIDogfoodStartupBootstrap.m` é agora o único bootstrap desta família:

1. O constructor apenas lê as preferências e registra um observer one-shot quando a família está habilitada.
2. O callback de `UIApplicationDidBecomeActiveNotification` apenas agenda o trabalho.
3. Após 500 ms, uma fila serial `QOS_CLASS_UTILITY` executa uma passagem limitada de classes e seletores exatos.
4. Após cinco segundos, e somente com Employee / Internal ainda ligado, a mesma fila executa as duas varreduras amplas:
   - readers tipados de descritores MobileConfig;
   - aliases runtime employee/test/dogfood.
5. Não há callback por imagem nos módulos desta correção.
6. `SCIDogfoodDeferredBootstrap.m`, o segundo observer concorrente, foi removido.
7. `SCISessionlessMobileConfigEarlyCapture.m`, que duplicava factories e insistia na cadeia FBT vazia, foi removido.
8. `SCIValidatedOEMResolvers.m` não possui constructor próprio; seus quatro hooks exatos são instalados pelo bootstrap central depois da ativação.
9. `SCIEmployeeIdentityConsumerHooks.m` usa cada IMP original como guard idempotente, permitindo uma repetição exata limitada para classes Swift tardias sem callback dyld.
10. O `%ctor` legado de `SCIEmployeeInternal.x` foi removido. O módulo conserva a propriedade exclusiva dos initializers, lifecycle e `tableView:didSelectRowAtIndexPath:`, mas só é instalado pelo bootstrap central.

Os logs medem separadamente:

- tempo da passagem exata pós-ativação;
- tempo das varreduras utilitárias adiadas;
- quantidade dos consumers exatos de identidade realmente instalados.

## Ownership dos hooks

Cada rota crítica tem um dono:

- bootstrap e agendamento: `SCIDogfoodStartupBootstrap.m`;
- initializers, lifecycle e `tableView:didSelectRowAtIndexPath:` do Bug Reporter: `SCIEmployeeInternal.x`;
- `cellForRow` e `shouldHighlight`: `SCIBugMenuOEMActivation.m`;
- `IGBugReportActionCell` / `IGBugReportLinkActionCell`, botão interno e callbacks `bugReporting*CellButtonTapped:`: `SCIBugMenuActionCells.m`;
- captura de Dogfooder/settings/user-session: `SCIDogfoodObjectRuntimeHooks.x`;
- closure exata de `Force MobileConfig re-fetch`: `SCILoggedOutMobileConfigActionHook.m`;
- bridge sessionless: `SCIValidatedOEMResolvers.m`, usando `IGDeviceSession.mobileConfig`, `IGDeviceSession.loggedOutNetworker` e o wrapper público `IGMobileConfigTryUpdateConfigsWithCompletion`.

## Hot paths removidos

`SCIEmployeeMobileConfigDescriptorHooks.m` agora:

- resolve a tabela de IDs uma vez antes de instalar readers;
- percorre a lista de classes uma única vez;
- não chama `dlsym` nem reinterpreta descritores dentro de cada `getBool:`;
- não registra callback dyld;
- é executado somente na fase utilitária adiada e com o master ainda ligado.

`SCIEmployeeTestDogfoodRuntimeHooks.m` agora:

- não escaneia classes em constructor;
- não registra callback dyld;
- não usa a main queue para varredura;
- executa o scan uma vez na fila utilitária;
- mudanças de defaults sincronizam apenas os descritores, sem repetir a lista completa de classes.

## Correção adicional encontrada na auditoria do menu

A desmontagem mostra que os valores `6` e `7` no jump table Swift são discriminadores internos de action, e não `NSIndexPath.section`.

O código anterior tratava qualquer célula nas seções 6 ou 7 como Internal Settings/Dogfooding Assistant. Isso podia alterar highlight e interação de linhas não relacionadas. `SCIBugMenuOEMActivation.m` agora identifica somente os títulos nativos exatos, usando também `contentConfiguration.text` quando o `textLabel` está vazio.

## Revalidação dos binários

Binários usados:

- `Instagram`: `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`

O relatório `docs/instagram-fbshared-r2-capstone-lief-analysis-2026-07-17.md` contém a passagem de radare2 `6.1.8`, backend Capstone 5, sobre exatamente esses hashes. A reprodução independente com LIEF `1.0.0-d05b3499b` e Python Capstone `5.0.7` confirmou os mesmos blocos:

- `IGBugReportActionCell -setEnabled:` em `0x10970f808` preserva o BOOL recebido em `x2` e o encaminha ao botão interno;
- `IGBugReportLinkActionCell -setEnabled:` em `0x10970f85c` faz o mesmo;
- os callbacks do controller começam em `0x1084c3a94` e `0x10851549c` e recebem a célula em `x2`;
- a action construction em `0x104aaf748` carrega a closure `0x105824584` em `x3`;
- `_IGMobileConfigTryUpdateConfigsWithCompletion` em `FBSharedFramework+0x72da74` executa `mov w4, #0` e salta para `0x72fee4`, confirmando o wrapper público de quatro argumentos que fornece o quinto internamente;
- o call site `Instagram+0x2c5604c` chama o stub importado depois de preparar o completion em `x3`.

As slices ARM64 usadas na reprodução foram gravadas em `tools/reverse/arm64-audit-fixtures.json`, vinculadas aos hashes completos dos dois Mach-O. Isso permite repetir a decodificação dos blocos críticos sem depender de offsets ou arquivos de outra versão.

## Arquivos da correção de performance

- `src/Features/Dogfooding/SCIDogfoodStartupBootstrap.m`
- `src/Features/Dogfooding/SCIEmployeeInternal.x`
- `src/Features/Dogfooding/SCIBugMenuActionCells.m`
- `src/Features/Dogfooding/SCIBugMenuOEMActivation.m`
- `src/Features/Dogfooding/SCIDogfoodObjectRuntimeHooks.x`
- `src/Features/Dogfooding/SCIEmployeeIdentityConsumerHooks.m`
- `src/Features/Dogfooding/SCIEmployeeMobileConfigDescriptorHooks.m`
- `src/Features/Dogfooding/SCIEmployeePandoIdentityHooks.m`
- `src/Features/Dogfooding/SCIEmployeeTestDogfoodRuntimeHooks.m`
- `src/Features/Dogfooding/SCILoggedOutMobileConfigActionHook.m`
- `src/Features/Dogfooding/SCIValidatedOEMResolvers.m`

Removidos:

- `src/Features/Dogfooding/SCIDogfoodDeferredBootstrap.m`
- `src/Features/Dogfooding/SCISessionlessMobileConfigEarlyCapture.m`
