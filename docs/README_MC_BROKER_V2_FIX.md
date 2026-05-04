# MC Broker v2 cleanup applied

This branch cleanup makes the MobileConfig/EasyGating C broker path the only active owner of the central C bool broker hooks.

## Active owner

`src/Features/ExpFlags/SCIMobileConfigBrokerRouter.xm`

It installs real-body C hooks with `MSHookFunction` only when there is either:

- a saved per-value override under `mcbr:<brokerID>:<hex64>`, or
- an explicit pass-through observer toggle under `mcbr.hook:<brokerID>`.

The compact namespace used here is:

- `mcbr:<brokerID>:<hex64>` = per specifier/gate override
- `mcob:<brokerID>:<hex64>` = observed original value
- `mcbr.idx` = active override index
- `mcob.idx` = observed value index
- `mcbr.hook:<brokerID>` = pass-through observer install toggle
- `mcer:<brokerID>` = last install error

## Legacy paths disabled

These files are now shims and no longer fishhook MobileConfig/EasyGating C bool brokers:

- `MobileConfigCBooleanObserver.xm`
- `InternalGateObservers.xm`

`InternalModeHooks.xm` no longer hooks `IGMobileConfigBooleanValueForInternalUse` or `IGMobileConfigSessionlessBooleanValueForInternalUse`; it only keeps the separate `IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18` spoof.

`MobileConfigRuntimePatcher.xm` remains a lab-only raw patcher, but it skips itself when MC Broker v2 has active overrides/hooks.

## Build-sensitive fixes

- corrected v72 little-endian fingerprint for `_IGMobileConfigSessionlessBooleanValueForInternalUse` to `0x91129063b0ffee43`
- kept `_EasyGatingPlatformGetBoolean` as `0xa90557f6d10203ff`
- changed router to check per-value override before calling original
- added pending retry through dyld add-image callback for `FBSharedFramework`
- changed UI semantics: main switches install pass-through observers; per-specifier/per-gate overrides live inside the broker detail screen
