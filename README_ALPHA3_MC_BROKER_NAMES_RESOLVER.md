# MC Broker v2 names resolver — alpha3

## Scope

This package contains the complete edited files for the alpha3 MC Broker v2 resolver layer.

The goal is **not** to add more hooks. The hook/observer/C-broker timing stays owned by:

```text
src/Features/ExpFlags/SCIMobileConfigBrokerRouter.xm
```

The files here only make the broker UI and store use a per-value namespace and resolve MobileConfig IDs into names when the data exists.

## Active owner

`SCIMobileConfigBrokerRouter.xm` remains the only active owner of the C bool broker hooks.

It should install real-body C hooks only when there is either:

- a saved per-value override under `mcbr:<brokerID>:<hex64>`; or
- an explicit pass-through observer toggle under `mcbr.hook:<brokerID>`.

## Compact namespace

```text
mcbr:<brokerID>:<hex64> = per specifier/gate override
mcob:<brokerID>:<hex64> = observed original value
mcbr.idx                 = active override index
mcob.idx                 = observed value index
mcbr.hook:<brokerID>     = pass-through observer install toggle
mcer:<brokerID>          = last install error
```

## Resolver order

`SCIMobileConfigIDResolver` resolves IDs in this order:

1. manual label saved by the user;
2. runtime name saved by ObjC observers through `noteResolvedName:detail:brokerID:value:source:`;
3. known anchors such as `ig_is_employee` and `ig_is_employee_or_test_user`;
4. `SCIMobileConfigMapping` / `id_name_mapping.json`, when present;
5. `SCIExpMobileConfigMapping`, when present;
6. `SCIMachODexKitResolver`, which indexes loaded Mach-O data tables and string ranges;
7. decoded fallback with tag/family/param/normalized.

## Important behavior

- No new startup hook is added here.
- No global blanket override is added here.
- The UI switch on the broker list enables pass-through observation for that broker.
- Per-specifier/per-gate overrides are inside the broker detail screen.
- EasyGating pointer-like runtime tokens are marked as runtime tokens instead of being falsely named.

## Build-sensitive notes

The Makefile no longer filters out `src/Features/ExpFlags/SCIMachODexKitResolver.m`.

The `before-all` schema generation step is guarded: if `scripts/embed_mobileconfig_schema.py` is absent, the build creates a minimal generated schema source instead of failing.
