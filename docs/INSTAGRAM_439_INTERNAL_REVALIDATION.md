# Instagram 439 — Employee, Dogfood and Internal Settings revalidation

## Audited binaries

- `Instagram(16)`
  - SHA-256: `fa19f499c560b188d2802e3a1a36642209ee6e42d7639c1ebe010f14b2c4cd9b`
- `FBSharedFramework(14)`
  - SHA-256: `a79c110c59e7c16e5608227e12807583c1afcf80cb2a2e38302f147dbf99c12b`
- Both Mach-O images are decrypted (`cryptid = 0`).

The Apple `otool` binary was not available on the Linux analysis host. Load commands, Objective-C metadata and Mach-O structures were checked with LLVM tooling; ARM64 control flow, chained fixups, symbols and raw data were independently inspected. No old offset was reused without revalidation.

## Names that no longer exist

The following literal names have zero ASCII and UTF-16 occurrences in both new binaries and are absent from symbols, imports, exports and chained bindings:

- `ig_is_employee`
- `ig_is_employee_or_test_user`
- `is_employee_or_test_user`
- `is_employee_or_employee_test_account`
- `ig_dogfooding_first_client`

The remaining `is_employee` strings belong to fields, ivars, selectors and reporting/telemetry surfaces. `_IGDeviceReportFBUserIsEmployeeKey`, `_is_employee`, `_is_employee_value_set` and `IGApplicationStateLogger ... isEmployee:` are not the authorization path for Internal Settings in this build.

## Availability resolver

The Swift type is `IGInternalSettingsAvailabilityStatus`.

- resolver: `Instagram + 0x09E5D194`
- VA in the audited image: `0x109E5D194`
- direct callers:
  - `0x104F54944`
  - `0x1059599F0`
  - `0x10633E3D0`
  - `0x10643E038`

Recovered decision flow:

```text
FBEndToEndIsRunningSapienz == true  -> 1
internal_only unavailable          -> 1
FBEndToEndIsRunningJestE2E == true -> 0
employeeOrTestUser == true         -> 0
employeeOrTestUser == false        -> 2
```

Raw values:

- `0`: allowed
- `1`: unavailable because the internal plugin/rollout is absent
- `2`: denied by employee/test-account identity

The existing `SCIEmployeeInternal.x` initializer hook remains the safe client-side place to set raw status `0` and the presentation booleans. It does not recreate removed plugin data.

## Canonical employee/test-user path

The generated fragment is obtained through:

```text
asIGUserIsEmployeeOrTestUserFragment
```

- Objective-C stub: `0x10A55FA5C`
- shared helper: `0x104177F3C`
- the helper has ten direct callers

It accepts the account through three routes:

1. `accountBadges` contains internal badge value `0`;
2. `graphQLID.integerValue` belongs to either reserved test range:
   - `90,010,000,000,000 <= ID < 90,020,000,000,000`
   - `15,812,502,200,005,009 <= ID < 15,852,502,200,005,009`
3. fallback MobileConfig boolean.

The fallback uses `_MC(context)`, `FBMobileConfigOptions.withoutLogging` and `-[FBMobileConfigContextManager getBool:withOptions:]` with packed parameter:

```text
0x008100A700000134
```

Decoded fields:

- type: `0x81` (boolean)
- config: `0x00A7` = `167`
- parameter: `0x00000134` = `308`

The verified framework implementation is at `FBSharedFramework + 0x47F070`, with encoding:

```text
B32@0:8{mc_bool_param_t=Q}16@24
```

`SCIInternal439MobileConfig.m` hooks the actual Objective-C methods, validates every runtime signature before installation and forces only this packed key and the Dogfooding Assistant key. It does not patch `__TEXT`.

## Dogfooding Assistant and MAISA

Dogfooding Assistant presentation boolean:

```text
0x00810A8A000139D6
```

Decoded:

- type: `0x81` (boolean)
- config: `0x0A8A` = `2698`
- parameter: `0x000139D6` = `80342`

MAISA UX variant:

```text
0x0082139D00001B09
```

Decoded:

- type: `0x82` (int64)
- config: `0x139D` = `5021`
- parameter: `0x00001B09` = `6921`

The caller normalizes raw value `4` to `0`. No MAISA value is forced by this patch because a useful native variant has not yet been established. It is mapped for inspection only.

## Bug Reporter menu ABI

Class:

```text
_TtC17IGBugReporterMenu29IGBugReportMenuViewController
```

Current initializer:

```text
initWithDeviceSession:
userSession:
reliabilityLogging:
navChain:
endpoint:
entryPoint:
style:
internalSettingsAvailabilityStatus:
showInternalSettings:
showLoggedOutInternalSettings:
showShakeToReportPreferenceToggle:
showDogfoodingAssistant:
maisaUXVariantRawValue:
```

Swift initializer address: `0x104F8C954`.

Direct callers:

- `0x1001A2854`
- `0x1011574A4`
- `0x104B5D6A8`
- `0x104F54A44`

Recovered scalar layout:

- `+0xC0`: `internalSettingsAvailabilityStatus`
- `+0xC8`: `showInternalSettings`
- `+0xC9`: `showLoggedOutInternalSettings`
- `+0xCA`: `showShakeToReportPreferenceToggle`
- `+0xCB`: `showDogfoodingAssistant`
- `+0xCC`: `maisaUXVariant`

`showInternalSettings` is originally built as:

```text
internal_only && !hide-internal-settings-in-bug-report-menu
```

Forcing the initializer and live scalar state can expose the top-level row and avoid raw status `2`. It does not restore the removed pinned socket described below.

## Critical XPlugins ABI correction

The former proposal to rebind `_XPluginsGetDataFuncOrAbort(0x64327C01)` to a function returning `x0 = 1` was invalid and must never be implemented.

Hash:

```text
0x64327C01
```

- wrapper: `0x10410D7E4`
- XPlugins data table: `0x10EA1BCA0`
- table entry index: `1788`
- entry address: `0x10EA22C60`
- provider target: `0x102BD80E4`

The target is a null data provider:

```asm
mov x0, #0
mov x1, #0
ret
```

The provider ABI is a pair `(data pointer, count)` in `x0/x1`, not a boolean. Confirmed consumers include:

```text
0x104F8CB24: ldr w20, [x0, #8]
0x105959A1C: ldr x8, [x0]
0x105959A1C: ldr w1, [x0, #8]
```

The descriptor element contains three 32-bit XPlugins function IDs at offsets `+0`, `+4` and `+8`. The ID at `+8` is resolved through `XPluginsGetFunctionPtrFromID`, receives a `SocketThreadLocalScope`, and participates in building the typed plugin collection.

Swift reflection identifies the nested item type as `IGPinnedInternalSettingsSocket.Plugin`, with fields:

- `cell_text`
- `description_text`
- `imageID`
- `pinnedByDefaultID`

A second provider, hash `0x253F21CF`, should supply the actual array of plugin rows. It is also compiled to the same null `(0, 0)` provider. The subsystem is therefore absent in two independent layers:

1. no descriptor containing the three function IDs;
2. no collection of `Plugin` rows.

Returning a sentinel pointer would make presence checks pass and then crash when functional consumers dereference address `0x1`. Supplying only three guessed IDs would still leave the row collection missing.

The action `ig.action.navigation.OpenInternalSettings` and function ID `0x20AA` remain registered, but the handler eventually reaches the same null provider through `0x10643E000`; it is not a provider-independent opener.

### Repository rule

The following are explicitly forbidden for this build:

- rebinding `0x64327C01` to a BOOL/sentinel provider;
- inline-hooking the wrapper in `__TEXT`;
- fabricating an incomplete `NIGPinnedInternalSettingsSocketPluginData` object;
- claiming that the native pinned Internal Settings socket has been restored.

The two XPlugins providers remain untouched.

## Applied patch

### Targeted runtime MobileConfig

`src/Features/Dogfooding/SCIInternal439MobileConfig.m`:

- installs only when Employee/Internal or the Internal Settings force toggles are enabled;
- hooks every present boolean getter variant after validating its runtime ABI;
- forces:
  - `0x008100A700000134` — employee/test-user fallback;
  - `0x00810A8A000139D6` — Dogfooding Assistant presentation;
- preserves all other MobileConfig values;
- performs no class scan, dyld image callback or `__TEXT` patch.

### Verified mapping overlay

`src/BundleAssets/id_name_mapping_internal439.json` contains analyst-verified aliases:

```text
167:308    is_employee_or_test_user_fallback
2698:80342 show_dogfooding_assistant
5021:6921  maisa_ux_variant
```

These are recovered semantic annotations for the audited build, not surviving upstream symbol names.

The overlay is embedded as `__DATA,__idmap439`. `SCIMCInternal439Overlay.m` merges it after every MobileConfig browser reload so the verified aliases override stale catalogue labels without rewriting the generated mapping.

The Internal preset now adds only the two verified boolean overrides. MAISA remains system-controlled.

## Scope and limitation

This patch restores the verified client-side identity fallback, Dogfooding Assistant gate and Bug Reporter presentation state. It does not impersonate backend authorization, invent server responses or reconstruct the removed pinned plugin collection.

Native controllers that still expose validated independent Objective-C/Swift entry points may be opened directly by `SCIInternalMenusLauncher`. Any controller whose only route is the null XPlugins socket remains unavailable until a complete native producer and collection ABI are recovered.
