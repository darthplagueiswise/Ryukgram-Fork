# Binary validation notes

This branch does not treat hook signatures or MobileConfig serialization as guessed interfaces. The current implementation was revalidated against the supplied arm64 binaries and JSON samples before the ABI-dependent code was finalized.

## Validation inputs

- Instagram executable: SHA-256 `e0cd6b965b3ce6b64c596e31809bcef02d49c3647302243767f50e5b3d406126`
- FBSharedFramework: SHA-256 `9d9c3fe54408da58b3abbffc8364d937c61bc1795541db40686fdebdc6b3b52b`
- `id_name_mapping.json`: SHA-256 `65b9bf0d65b1c79742b5ad6696c9daded24be1fc808f0b1f3054c70b74214419`
- previous `mc_overrides.json`: SHA-256 `b023ca6131e73cf6d14cc1dc335c143d754ba27524846b8abc986fb60ee192d6`
- current `mc_overrides(3).json`: SHA-256 `e6df7d7dd0608f5edbabeb79103ed4c10c459bc87ec2d9b4d1ce11e89cfb499b`

The uploaded application binaries were inspected directly as Mach-O/arm64 using `llvm-objdump` plus explicit parsing of Objective-C relative method lists, dyld chained fixups and the MobileConfig parameter table. These notes preserve that one-time ABI validation; the normal dogfood build no longer reruns a post-build LIEF/Capstone/radare2 validation stage.

## Easy Gating

`EasyGatingGetBoolean_Internal_DoNotUseOrMock` is a mapping wrapper. Its arm64 body maps the incoming selector/index and branches to `EasyGatingPlatformGetBoolean`, whose second argument is the final mapped gate ID.

The earlier implementation patched `EasyGatingPlatformGetBoolean` inside signed `FBSharedFramework.__TEXT`. On sideloaded builds that can invalidate the 16 KiB code-signing page. The current implementation instead rebinds only Instagram's imported wrapper slot with fishhook, calls the untouched native wrapper, and decodes the wrapper's validated read-only mapper to recover the final gate ID. If the expected arm64 instructions do not match, the call stays native and is not exposed as an editable gate.

Validated platform register contract:

- `x0`: opaque context
- wrapper `w1`: selector/index; validated mapper output: final gate ID
- `w2`: Boolean/default value
- `w3`: exposure flag
- return: Boolean in `w0`

The auth-data-context variant and the signed platform text remain untouched because their safe rebinding/complete argument contracts have not been proven to the same standard.

## Objective-C BOOL runtime browser

The browser enumerates declared methods in the selected loaded image and accepts only methods whose runtime type encoding proves a strict BOOL return plus one of the supported argument shapes. It does not infer hookability from a method name.

Current FBShared metadata confirms, among others, the IGDS launcher gates used by IGWordMark and Prism/Liquid Glass as no-argument BOOL instance methods (`B16@0:8`).

## MobileConfig Objective-C ABI

`FBMobileConfigContextManager` exposes the typed getters with concrete Objective-C encodings. The relevant validated families are:

- `getBool:` / defaults / options: BOOL return, `{mc_bool_param_t=Q}` parameter
- `getInt64:` / defaults / options: signed 64-bit return, `{mc_long_param_t=Q}` parameter
- `getString:` / defaults / options: object return, `{mc_string_param_t=Q}` parameter
- `getDouble:` / defaults / options: double return, `{mc_double_param_t=Q}` parameter
- `getOverridesTablePath`: object return, no explicit argument

The `_configManager` ivar is an instance `std::shared_ptr<mobileconfig::FBMobileConfigManager>` at offset `0x248`, size 16. The implementation reads the first pointer only after locating the ivar through Objective-C runtime metadata.

## MobileConfig C++ ABI

`mobileconfig::typeFromParameter(unsigned long long)` is exactly:

```asm
ubfx x0, x0, #48, #6
ret
```

So the native parameter kind is encoded in bits 48...53 of the parameter ID.

The current exported overloads validate these native call shapes:

- `FBMobileConfigOverridesTable::updateOverrideForParam(unsigned long long, bool, bool)`
- `FBMobileConfigOverridesTable::updateOverrideForParam(unsigned long long, long long, bool)`
- `FBMobileConfigOverridesTable::updateOverrideForParam(unsigned long long, std::string const&, bool)`
- `FBMobileConfigOverridesTable::updateOverrideForParam(unsigned long long, double, bool)`
- `FBMobileConfigOverridesTable::removeOverrideForParam(unsigned long long, bool)`
- `FBMobileConfigManager::getOrCreateOverridesTable(bool)`

`getOrCreateOverridesTable(bool)` returns a non-trivial `std::shared_ptr`; the arm64 implementation uses the hidden `x8` structure-return destination. `RYGSharedPtr` intentionally remains non-trivial so the compiler uses that ABI.

## Native parameter table

`kMobileConfigParamsSize` reports `0x88fc` = **35,068** rows. Decoding the chained pointer in `kMobileConfigParamsList` resolves the array, whose row stride is **40 bytes**. The validated fields used by the browser are:

- `+16`: parameter index (`uint32_t`)
- `+20`: ordinal mix (`uint32_t`; low 16 bits are the ordinal)
- `+24`: type/serial (`uint32_t`; high 16 bits are the native type discriminator, low 16 bits the serial)
- `+36`: config number (`uint32_t`)

Across all 35,068 rows the native discriminator distribution is 24,401 type-1, 7,131 type-2, 1,497 type-3 and 2,039 type-4 rows.

Cross-checking those rows against the supplied mapping and canonical override values establishes the native parameter-ID discriminator as:

- `1 = bool`
- `2 = int64`
- `3 = string`
- `4 = double`

This matters: an earlier source enum had string/double reversed. The current enum and every live read/write/import path use the corrected order.

## Canonical JSON formats

The supplied `id_name_mapping.json` is an array of strings with grammar:

```text
<configId>:<configName>[:<paramIndex>:<paramName>]*
```

The supplied `mc_overrides.json` is an object whose normal keys use `<configId>:` and whose values are arrays of strings:

```text
<paramIndex>: : <value>
```

The special `_qe_overrides_` array is preserved. Import validates the complete file before applying any live value, and unsupported/mapping-only rows are preserved rather than assigned a fabricated parameter ID or type.

The current sample contains 448 config keys and 2,387 entries (2,349 Boolean and 38 integer values). Every entry passed the canonical `<paramIndex>: : <value>` grammar check.

## Developer runtime surfaces

The supplied executable also confirms the exact native names used by the rebuilt Developer menu:

- IGWordMark: `IGDSLauncherConfig` with runtime fallback to `_TtC11BSLDSConfig11BSLDSConfig`.
- Prism: the currently loaded BOOL-returning methods declared by those two IGDS/BSLDS owners; method rows are not bundled.
- Stories: `isTrayAttachedToHeaderEnabled:` and `isDynamicTabStoryGridEnabled` (singular `Story`, matching the executable).
- Liquid Glass Throwback: `_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper` and `overrideIsEnabled:`.
- Direct dogfood: `notesDogfoodingSettingsOpenOnViewController:userSession:` and `sessionBrowserViewController:userSession:`. Both are invoked only after the Objective-C runtime proves their full object/return ABI and a real session has been captured.
- Bug Report: both observed `IGBugReportMenuViewController` initializer forms, including the full form with logged-out settings, shake preference and Dogfooding Assistant visibility arguments.

IG-only/internal-only, settings visibility, bug-report and sandbox browsing are filtered views over the selected currently loaded Mach-O image. The index is an in-memory snapshot with explicit refresh; there is no preloaded class, selector or Boolean table. Structural introspection methods such as `isEqual:`, `respondsToSelector:` and `canRespond...` are excluded semantically.

## Analysis tooling

The current binaries were parsed with LIEF 1.0.0 and Capstone 5.0.x from the local analysis virtual environment. LIEF reports one arm64 slice, 56 sections and 39,174 symbols for Instagram; FBSharedFramework has one arm64 slice, 56 sections and 35,030 symbols. Capstone disassembly resolves `_EasyGatingGetBoolean_Internal_DoNotUseOrMock` at `0x50e234` and confirms its wrapper prologue/branch sequence before the read-only mapper is trusted. `r2pipe` is installed for radare2 automation; radare2 itself is a native executable (not a Python package) and the repository's bootstrap workflow downloads that binary separately.
