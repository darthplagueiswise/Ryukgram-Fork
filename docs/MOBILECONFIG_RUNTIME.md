# MobileConfig runtime model

`dogfood` does not ship a parameter table. The former
`src/BundleAssets/ryg_mc_names.bin` is removed and the build validator rejects
it if it returns.

## How the real system is obtained

RyukGram does not allocate or fabricate Instagram's private MobileConfig
manager. With the MobileConfig developer option enabled at launch it:

1. finds the live `FBMobileConfigContextManager` or
   `IGMobileConfigContextManager` class;
2. verifies each getter's Objective-C method encoding before installing a hook;
3. captures the real manager instance and opaque 64-bit parameter IDs only when
   Instagram calls those getters;
4. resolves the current process's exported `mobileconfig` symbols at scan time;
5. enumerates `kMobileConfigParamsList` only after the symbol, count, candidate
   array, detected stride, and complete byte range have been proven to lie in a
   readable loaded Mach-O segment;
6. asks Instagram's live `typeFromParameter` implementation to validate each
   reconstructed ID.

If a class, symbol, ABI, count, stride, or mapped range does not match, the scan
returns no rows. It never falls back to a bundled catalogue or stale offsets.
Hook installation is retried as frameworks are loaded, so constructor timing
does not permanently disable the monitor.

## Names, values, and overrides

Names are joined at refresh time from Instagram's current
`id_name_mapping.json`, MobileConfig sync dumps, or the user's explicitly
imported mapping overlay. Live values are read through the captured manager
only when the expected getter exists. Writes use the runtime-validated
`FBMobileConfigStartupConfigs` override bridge and then synchronize canonical
JSON beside Instagram's active table. The old direct private-C++/`_configManager`
path is not used.

`getOverridesTablePath` is the only authority for disk placement. Its result is
normalized to the actual `Documents/mobileconfig/<native-id>.data` directory;
RyukGram accepts either the native table path or that exact `.data` directory.
It never guesses an account/user id and never writes into the parent
`Documents/mobileconfig` directory. Canonical filenames inside the resolved
directory are `id_name_mapping.json` and `mc_overrides.json`.

The UI is instantiated with `[RYGMobileConfig shared]`, followed by `prepare` or
`reloadFromRuntime`. The manager itself is intentionally never instantiated by
the tweak.

Only explicit user intent persists:

- `mc_overrides.plist` stores validated numeric/string overrides keyed by the
  canonical opaque parameter ID;
- `mc_notes.plist` stores user notes;
- `mc_launch.plist` is the crash-loop guard.

The Developer UI can import or export `id_name_mapping.json`, import/apply or
export `mc_overrides.json`, and explicitly reapply the active in-process
overrides. Import is transactional: the complete document is validated first,
and a failed native application restores the previous override state.

Enumerated configs, parameter names, live values, call sites, rows, pointers,
and addresses remain memory-only and are rebuilt from the running app.
