# RyukGram — Feature Gating / Story Tray sem retry

## Decisão

Remover `dispatch_after` retry de Feature Gating/Story Tray.

## Motivo

O retry não veio de uma técnica validada em RyukGram/Watusi. Ele foi um paliativo para classe Swift carregada tarde, mas adiciona trabalho assíncrono no main queue e pode dar sensação de lag.

O padrão mais correto é:

1. persistir o override escolhido pelo usuário;
2. tentar instalar o hook uma vez na ação explícita;
3. não reinstalar hooks persistidos no startup;
4. se uma classe Swift ainda não carregou, o usuário pode aplicar de novo quando a superfície existir, ou o menu específico pode expor botão "Aplicar" manual.

## Mantido

`setRuntimeBoolOverride` continua persistindo antes de tentar hookar. Isso evita perder o estado do Story Tray se a classe ainda não existir.

## Removido

Bloco:

```objc
NSArray<NSNumber *> *delays = @[@1.5, @4.0, @8.0];
for (NSNumber *delay in delays) {
    dispatch_after(...);
}
```

## Bootstrap

O bootstrap fica startup-safe: só reconcilia crash guard e instala observer passivo de wordmark. Não reinstala overrides persistidos automaticamente.
