# Android 439 MobileConfig mapping audit

## Artifact

- Package: `com.instagram.android_439.0.0.0.74-384506337_1dpi_5feat_d77507f3290c5d24854103c0f2790b40_apkmirror.com.apkm`
- APKM SHA-256: `008e3a567f862ab6cdeee02fe1de6ae2274b68aa5b243000673647a0dbd57600`
- Archive coverage: outer APKM plus all seven nested APKs, 17,098 entries total.

## Baksmali result

The native Instagram Android implementation does not download the mapping.

`com.facebook.mobileconfig.factory.MobileConfigFactoryImpl` is `LX/2fc`; method `A0H` obtains the base path from `LX/42f.A00` and checks these files in order:

1. `<base>/id_name_mapping.json`
2. `<base>/mobileconfig/id_name_mapping.json`

It opens the selected file through `FileReader` and `BufferedReader`, constructs a `JSONArray`, iterates its strings, and splits each string on `:`. The expected record is therefore:

```text
config_id:config_name:param_id:param_name[:param_id:param_name...]
```

No `id_name_mapping.json` is embedded in the APKM. The packaged `assets/params_map.txt` is a separate binary ID table with 5,575 configs and 39,364 params; it does not supply the human-readable names.

## Dev-options gate

InstaEclipse resolves and hooks a shared `(UserSession) -> boolean` employee gate. Its structural DexKit tier finds minimal wrappers that call `MobileConfigUnsafeContext(long) -> boolean`, then selects the high-fan-in wrapper. This unlocks Instagram's native Developer Options; it does not create an Internal Settings controller.

## iOS parity decision

- Treat `ig_is_employee` and `ig_is_employee_or_test_user` as DATA descriptors.
- Derive each evaluator index from the descriptor's first little-endian `u32` at runtime.
- Rebind the shared evaluator imports before session construction.
- Force only the matching index: plain EasyGating receives its index in `w0`; MCQ EasyGating receives it in `w1`.
- Let every unrelated index return the original evaluator result.
- Keep mapping refresh separate from mapping load: RyukGram may download or bundle JSON, but the host MobileConfig factory remains responsible for reading the disk file after restart.
