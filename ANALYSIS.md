# Binary validation note

The current Developer/MobileConfig rebuild is validated against the supplied arm64 Instagram and FBSharedFramework binaries before hook ABI assumptions are committed. Easy Gating is hooked at `EasyGatingPlatformGetBoolean` after the public wrapper maps its selector/index to the final gate ID. MobileConfig JSON import/export follows the observed `id_name_mapping.json` and `mc_overrides.json` grammars, including `_qe_overrides_`.
