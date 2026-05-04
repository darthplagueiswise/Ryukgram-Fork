# SCI DexKit v2.0 drop-in

This package is a clean replacement for the fragmented DexKit v1 path.

Core guarantees:
- zero DexKit hooks at startup when there are zero saved overrides;
- startup reinstalls only `dexkit.bool:*` overrides from `dexkit.bool.__index`;
- menu open performs metadata-only scan using `objc_copyImageNames` + `objc_copyClassNamesForImage`;
- curated mode is owner-first and `B`-return only by default;
- `c` return types are debug/raw only;
- overrides are `NSUserDefaults` bool-or-absent, no enum on disk;
- observed defaults use `dexkit.observed.bool:*` and are invalidated by app build;
- router validates exact method owner, signature, and image before `MSHookMessageEx`;
- pending overrides are retried through dyld add-image callback;
- crash guard quarantines the last applying override after repeated unstable launches.

Replace old files with this tree and ensure the project Makefile includes all `.m` and `.xm` under `src`.
