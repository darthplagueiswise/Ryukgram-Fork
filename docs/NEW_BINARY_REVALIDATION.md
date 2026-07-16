# Instagram(29) / FBSharedFramework(105) revalidation

Tools used: LIEF 1.0.0, Capstone 5.0.7 and llvm-objdump. `radare2` was attempted from apt and pip, but no usable `r2` binary is available in this container; no result below depends on r2.

## Parsed surface

- Instagram: 42,356 ObjC classes, 397,534 methods, 43,111 imports.
- FBSharedFramework: 5,323 ObjC classes, 64,680 methods, 28,811 exports.
- 253 `*ExperimentConfig` methods and 1,443 experiment-related BOOL methods were catalogued.
- 25,651 BOOL methods with zero or one supported ObjC/integer argument are candidates for the runtime browser.

## Confirmed replacement for the removed old reader

`IGMobileConfigBooleanValueForInternalUse` is absent from both binaries. It is not renamed in this patch.

The current generic experiment surfaces are:

- `FBCCIGExperimentManager -isFeatureEnabled:` (`B24@0:8Q16`)
- `FBCCIGExperimentManager -isFeatureEnabledWithoutLogging:` (`B24@0:8Q16`)
- `FBCustomExperimentManager -isFeatureEnabled:` (`B24@0:8Q16`)
- `FBCustomExperimentManager -isFeatureEnabledWithoutLogging:` (`B24@0:8Q16`)

Capstone confirms the feature identifier is received in `x2`; the methods return BOOL in `w0`.

The remaining C readers still are present as Instagram imports and FBSharedFramework exports are EasyGating, MSGC Sessioned, MCI Experiment/MCI Extension and METAExtensions Experiment readers. Their bodies perform real initialization/lookup work, so the replacements call the original with all `x0-x7` arguments before forcing the BOOL result.

## Runtime browser change

The old browser rejected every selector containing `:` and required exactly two ObjC arguments (`self`, `_cmd`). It therefore omitted both unified managers and `+isEnabled:` QuickExperiment config methods.

The browser now indexes BOOL methods with:

- no explicit argument;
- one object/class/selector argument; or
- one integer/pointer argument.

Each signature has its own original IMP and ABI-matching replacement. Unsupported floating-point, structure, block and multi-argument methods stay read-only/not indexed by this override engine.

## Internal/dev targets

Validated targets retained or added:

- both current `IGBugReportMenuViewController initWith...showInternalSettings...` variants;
- `RCTDevMenu` getters `devMenuEnabled`, `shakeToShow`, `hotLoadingEnabled`, `hotkeysEnabled`, and `keyboardShortcutsEnabled`;
- employee/internal gates already present in `SCIEmployeeInternal.x`.
