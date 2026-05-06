# Alpha3 MC Broker v2 runtime-callsite resolver integration

This patch uses the uploaded ObjC pass-through observer/resolver base and wires MC Broker v2 to consume `SCIDexKitNameResolver`.

What changed:

- `SCIObjCMobileConfigGetterObserver.xm` remains ObjC pass-through only.
- No C body hook was added.
- No MC Broker override model was changed.
- `getBool*` feeds `SCIDexKitNameResolver` with class, selector, specifier, default, original, final and caller metadata.
- `_getTranslatedSpecifier:` and `getStableIdFromParamSpecifier:` stay ABI-checked and pass-through.
- `SCIMobileConfigBrokerStore` now enriches MC Broker snapshots and rows through `SCIDexKitNameResolver`.
- `SCIMobileConfigBrokerViewController` now displays resolved title/source/runtimeObserved/callsite when present.

Important: this does not invent feature names. If no exact mapping exists, the UI may show `runtime-callsite` or decoded-id honestly.
