# Binary validation notes

This branch does not treat hook signatures or MobileConfig serialization as guessed interfaces. The current implementation was revalidated against the supplied arm64 binaries and JSON samples before the ABI-dependent code was finalized.

## Validation inputs

- Instagram executable: SHA-256 `e0cd6b965b3ce6b64c596e31809bcef02d49c3647302243767f50e5b3d406126`
- FBSharedFramework: SHA-256 `9d9c3fe54408da58b3abbffc8364d937c61bc1795541db40686fdebdc6b3b52b`
- `id_name_mapping.json`: SHA-256 `65b9bf0d65b1c79742b5ad6696c9daded24be1fc808f0b1f3054c70b74214419`
- `mc_overrides.json`: SHA-256 `b023ca6131e73cf6d14cc1dc335c143d754ba27524846b8abc986fb60ee192d6`

The uploaded application binaries were inspected directly as Mach-O/arm64 using `llvm-objdump` plus explicit parsing of Objective-C relative method lists, dyld chained fixups and the MobileConfig parameter table. These notes preserve that one-time ABI validation; the normal dogfood build no longer reruns a post-build LIEF/Capstone/radare2 validation stage.

## Easy Gating

`EasyGatingGetBoolean_Internal_DoNotUseOrMock` is a mapping wrapper, not the stable per-gate hook point. Its arm64 body maps the incoming selector/index and branches to `EasyGatingPlatformGetBoolean`. The platform function receives the final mapped gate ID. `RYGEasyGatingRuntime` therefore hooks only `EasyGatingPlatformGetBoolean` and persists overrides in a new v2 namespace keyed by the final numeric gate ID.

Validated platform register contract:

- `x0`: opaque context
- `w1`: final mapped gate ID
- `w2`: Boolean/default value
- `w3`: exposure flag
- return: Boolean in `w0`

The auth-data-context variant remains untouched because its complete argument contract has not been proven to the same standard.

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
