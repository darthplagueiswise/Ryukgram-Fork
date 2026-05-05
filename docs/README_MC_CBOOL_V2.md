# MobileConfig/EasyGating C Broker Router v2

This package adds a separate router for C functions in FBSharedFramework. It does not replace DexKit ObjC getter scanning.

Namespaces:

- `dexkit.cbool:<image>:<symbol>:specifier:<hex64>` for IGMobileConfig/MCI specifiers
- `dexkit.cbool:<image>:<symbol>:gate:<hex64>` for EasyGating-like gates
- `dexkit.observed.cbool:<image>:<symbol>:specifier:<hex64>` for observed values
- `dexkit.observed.cbool:<image>:<symbol>:gate:<hex64>` for observed values
- `dexkit.cbool.hook:<brokerID>` enables a pass-through/observe hook for a broker
- `dexkit.cbool.__index` stores active overrides
- `dexkit.cbool.hooks` stores enabled broker observers

Primary canary brokers:

- `ig` = `_IGMobileConfigBooleanValueForInternalUse`
- `igsl` = `_IGMobileConfigSessionlessBooleanValueForInternalUse`

Complementary brokers:

- `egp` = `_EasyGatingPlatformGetBoolean`
- `mci` = `_MCIMobileConfigGetBoolean`

Compat/advanced brokers are included but disabled by default. Enable them only per broker and then force per observed specifier/gate.
