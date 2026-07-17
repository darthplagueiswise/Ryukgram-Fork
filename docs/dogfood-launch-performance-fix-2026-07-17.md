# Dogfood / Internal — correção da regressão de launch

Data: 2026-07-17

## Sintoma confirmado

Depois da expansão dos hooks de Employee, test user, dogfood, Internal Settings e sessionless MobileConfig, o Instagram passou a demorar excessivamente para abrir.

A regressão não estava no fetch de MobileConfig. Ela estava no bootstrap da tweak:

- oito módulos registravam `_dyld_register_func_for_add_image` separadamente;
- cada registro recebe callbacks também para imagens já carregadas e continuava repetindo trabalho para imagens futuras;
- dois módulos percorriam `objc_getClassList` durante o launch;
- `SCIEmployeeTestDogfoodRuntimeHooks` agendava nova varredura ampla na main queue para cada imagem;
- `SCIEmployeeMobileConfigDescriptorHooks` repetia lookup/parsing de descritores no hot path de `getBool:`;
- `SCIBugMenuOEMActivation` e `SCIEmployeeInternal.x` hookavam o mesmo `tableView:didSelectRowAtIndexPath:`;
- `SCIDogfoodObjectRuntimeHooks.x` e `SCISessionlessMobileConfigEarlyCapture.m` hookavam novamente os mesmos initializers/factories sessionless.

## Arquitetura corrigida

`SCIDogfoodStartupBootstrap.m` é agora o único bootstrap desta família:

1. No constructor faz apenas lookups exatos e limitados de classes/selectors.
2. Usa um único observer one-shot de `UIApplicationDidFinishLaunchingNotification`.
3. Repete os lookups exatos uma única vez depois do launch, para classes Swift registradas tarde.
4. Após dois segundos, numa fila serial com `QOS_CLASS_UTILITY`, executa as duas únicas varreduras amplas:
   - readers de descritores MobileConfig;
   - aliases runtime employee/test/dogfood.
5. Não registra callback por imagem e não executa scan amplo na main queue.

## Ownership dos hooks

Cada rota crítica passou a ter um único dono:

- initializers, lifecycle e `tableView:didSelectRowAtIndexPath:` do Bug Reporter: `SCIEmployeeInternal.x`;
- `cellForRow` e `shouldHighlight`: `SCIBugMenuOEMActivation.m`;
- `IGBugReportActionCell` / `IGBugReportLinkActionCell`, botão interno e callbacks `bugReporting*CellButtonTapped:`: `SCIBugMenuActionCells.m`;
- captura de `IGMobileConfigSessionlessContextManager` e factories: `SCISessionlessMobileConfigEarlyCapture.m`;
- captura de Dogfooder/settings/user-session: `SCIDogfoodObjectRuntimeHooks.x`;
- closure exata de `Force MobileConfig re-fetch`: `SCILoggedOutMobileConfigActionHook.m`.

## Hot paths removidos

`SCIEmployeeMobileConfigDescriptorHooks.m` agora:

- resolve a tabela de IDs uma vez antes de instalar readers;
- percorre a lista de classes uma única vez;
- não chama `dlsym` nem reinterpreta descritores dentro de cada `getBool:`;
- não grava log para cada hit de MobileConfig;
- retorna imediatamente, sem lock, quando o master está desligado.

`SCIEmployeeTestDogfoodRuntimeHooks.m` agora:

- não escaneia classes em constructor;
- não registra callback dyld;
- não usa main queue para varredura;
- executa o scan uma vez, post-launch, em utility QoS;
- mudanças de defaults só sincronizam os dois descritores, sem repetir a varredura completa.

## Revalidação dos binários

Binários usados:

- `Instagram`: `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`

A decodificação independente com Python Capstone 5.0.7 confirmou novamente:

- `IGBugReportActionCell -setEnabled:` em `0x10970f808` preserva o BOOL de `x2` e o encaminha ao botão interno;
- `IGBugReportLinkActionCell -setEnabled:` em `0x10970f85c` faz a mesma coisa;
- os callbacks do controller começam em `0x1084c3a94` e `0x10851549c` e recebem a célula em `x2`;
- a closure logged-out começa em `0x105824584` com a assinatura `e0 03 1e aa 10 18 38 97 fe 03 00 aa fd 7b 05 a9`;
- `_IGMobileConfigTryUpdateConfigsWithCompletion` em `FBSharedFramework+0x72da74` executa `mov w4, #0` seguido de `b 0x72fee4`, confirmando o wrapper público de quatro argumentos que fornece o quinto internamente.

A auditoria completa de r2 + Capstone permanece em `docs/instagram-fbshared-r2-capstone-lief-analysis-2026-07-17.md`.

## Arquivos alterados para performance

- `src/Features/Dogfooding/SCIDogfoodStartupBootstrap.m`
- `src/Features/Dogfooding/SCIBugMenuActionCells.m`
- `src/Features/Dogfooding/SCIBugMenuOEMActivation.m`
- `src/Features/Dogfooding/SCIDogfoodObjectRuntimeHooks.x`
- `src/Features/Dogfooding/SCIEmployeeIdentityConsumerHooks.m`
- `src/Features/Dogfooding/SCIEmployeeMobileConfigDescriptorHooks.m`
- `src/Features/Dogfooding/SCIEmployeePandoIdentityHooks.m`
- `src/Features/Dogfooding/SCIEmployeeTestDogfoodRuntimeHooks.m`
- `src/Features/Dogfooding/SCILoggedOutMobileConfigActionHook.m`
- `src/Features/Dogfooding/SCISessionlessMobileConfigEarlyCapture.m`
