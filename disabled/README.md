# disabled/

Código intencionalmente fora do build. Antes ficava dentro de `src/` com extensão
trocada (`.txt`/`.xm_`/`.m_`/`.x_`) — o Makefile globa só `.x/.xm/.m`, então
"funcionava" por acidente de nomenclatura. Isso é frágil: um `git mv`/rename
alterando só a extensão reativa o arquivo sem ninguém perceber.

Movido pra fora de `src/` por isso (SCI-FIX 2026-07-11). Nada foi deletado por
conteúdo — só reorganizado — exceto 2 arquivos confirmados obsoletos e removidos:
- `SCIIGDSLauncherConfigHook.txt` — rascunho superado pelo `.x` ativo do mesmo nome
  (idêntico em espírito, o `.x` é a versão validada contra o 433.0.283).
- `SCILaunchAutoForceHooks.removed.txt` — era só uma nota de texto dizendo que 4
  arquivos foram removidos; a informação já está nos docs de revisão.

## Reativar um arquivo daqui

1. Copie pra `src/.../` com a extensão real (`.x`/`.xm`/`.m`).
2. **Revalide contra o binário atual** antes de confiar em qualquer classe/seletor
   citado nos comentários — a build pode ter mudado desde que foi desativado.
3. Garanta que instala só sob pref (early-return no `%ctor`/install se OFF) e que
   não usa escada de `dispatch_after` (ver `CLAUDE.md`).

## Conteúdo

| Arquivo | Por que estava desativado (conforme comentários originais) |
|---|---|
| `SCIDebugConsole.m_` | console de debug standalone, não integrado ao settings ativo |
| `ExpFlagsHooks.xm_` / `SCIExpFlags.m_` / `SCIExpFlagsViewController.m_` | trio de ExpFlags — feature não finalizada |
| `EnableAllTextEffects.xm_` | text effects — não validado nesta build |
| `EnableHomecomingUI.x_` | UI de Homecoming — ver `HomecomingCompat.xm` ativo pro lever real |
| `QuickSnapCompat.xm_` / `QuickSnapMCCompat.xm_` | QuickSnap — comentário no `ExperimentalRolloutCompat.xm` ativo diz que o surface é gated por lógica Swift-nativa e forçar o nome do experimento não muda nada visível |
| `SCIXPluginsLookupHook.txt` | abordagem via `dlsym`+`MSHookFunction` pra `_XPluginsGetListLookupDataPair` — ver `CLAUDE.md` §4: esse símbolo é definido DENTRO do Instagram (launch path); fishhook nele no launch crasha. Mantido aqui como referência da técnica correta (dlsym, não endereço hardcoded), não reativar sem cuidado extra de timing. |
| `ProfileCopyButton.x_` | botão de copiar perfil — feature isolada, não integrada ao settings ativo |
