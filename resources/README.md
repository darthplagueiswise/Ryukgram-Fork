# Persisted GraphQL schema resource

Put the full Instagram iOS persisted query map here when you want the tweak to embed it directly at build time:

```text
resources/igios-instagram-schema_client-persist.json
```

The Makefile runs:

```bash
python3 scripts/embed_mobileconfig_schema.py "$(SCHEMA_JSON)" "src/Generated/SCIEmbeddedMobileConfigSchema.m"
```

Default:

```bash
SCHEMA_JSON=resources/igios-instagram-schema_client-persist.json
```

You can also build with an external file without committing the JSON:

```bash
make SCHEMA_JSON=/absolute/path/to/igios-instagram-schema_client-persist.json
```

Runtime fallback is still implemented through `NSBundle.mainBundle.privateFrameworksPath`, so the changing iOS container UUID is not hardcoded. If the embedded file is missing, the catalog tries the JSON inside `FBSharedFramework.framework` once and indexes it in memory.
