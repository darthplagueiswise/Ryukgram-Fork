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

`SCIDogfoodStartupBootstrap.m` é o bootstrap central dos módulos novos:

1. O constructor apenas lê as preferências e registra um observer one-shot quando a família está habilitada.
2. O callback de `UIApplicationDidBecomeActiveNotification` apenas agenda o trabalho.
3. Após 350 ms, uma fila serial `QOS_CLASS_UTILITY` executa uma passagem limitada de classes e seletores exatos.
4. Após quatro segundos, e somente com Employee / Internal ligado, a mesma fila executa as duas varreduras amplas:
   - readers tipados de descritores MobileConfig;
   - aliases runtime employee/test/dogfood.
5. Não há callback por imagem nos módulos desta correção.
6. `SCIDogfoodDeferredBootstrap.m`, o segundo observer concorrente, foi removido.
7. O módulo antigo `SCIEmployeeInternal.x` continua sendo o único dono de initializers, lifecycle e `tableView:didSelectRowAtIndexPath:`; seu instalador é idempotente.

Os logs agora medem separadamente:

- tempo da passagem exata pós-ativação;
- tempo das varreduras utilitárias adiadas.

## Ownership dos hooks

Cada rota crítica tem um dono:

- initializers, lifecycle e `tableView:didSelectRowAtIndexPath:` do Bug Reporter: `SCIEmployeeInternal.x`;
- `cellForRow` e `shouldHighlight`: `SCIBugMenuOEMActivation.m`;
- `IGBugReportActionCell` / `IGBugReportLinkActionCell`, botão interno e callbacks `bugReporting*CellButtonTapped:`: `SCIBugMenuActionCells.m`;
- captura de Dogfooder/settings/user-session: `SCIDogfoodObjectRuntimeHooks.x`;
- closure exata de `Force MobileConfig re-fetch`: `SCILoggedOutMobileConfigActionHook.m`;
- bridge sessionless: `SCIValidatedOEMResolvers.m`, usando `IGDeviceSession.mobileConfig`, `IGDeviceSession.loggedOutNetworker` e o wrapper público `IGMobileConfigTryUpdateConfigsWithCompletion`.

A camada antiga `SCISessionlessMobileConfigEarlyCapture.m` foi removida porque mantinha referências fortes, substituía factories e insistia numa cadeia FBT cujo holder apareceu `nil` no runtime do aparelho.

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

## Revalidação local dos binários

Binários usados:

- `Instagram`: `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`

A decodificação independente feita novamente com LIEF `1.0.0-d05b3499b` e Python Capstone `5.0.7` confirmou:

- `IGBugReportActionCell -setEnabled:` em `0x10970f808` preserva o BOOL recebido em `x2` e o encaminha ao botão interno;
- `IGBugReportLinkActionCell -setEnabled:` em `0x10970f85c` faz o mesmo;
- os callbacks do controller começam em `0x1084c3a94` e `0x10851549c` e recebem a célula em `x2`;
- a action construction em `0x104aaf748` carrega a closure `0x105824584` em `x3`;
- `_IGMobileConfigTryUpdateConfigsWithCompletion` em `FBSharedFramework+0x72da74` executa `mov w4, #0` e salta para `0x72fee4`, confirmando o wrapper público de quatro argumentos que fornece o quinto internamente;
- o call site `Instagram+0x2c5604c` chama o stub importado depois de preparar o completion em `x3`.

O executável `r2` não pôde ser reinstalado neste container isolado porque ele não possui saída de rede; por isso nenhuma nova saída de r2 foi atribuída a esta reprodução. O relatório histórico de r2 permanece separado e não é usado como substituto para os bytes confirmados acima.

## Arquivos da correção de performance

- `src/Features/Dogfooding/SCIDogfoodStartupBootstrap.m`
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
