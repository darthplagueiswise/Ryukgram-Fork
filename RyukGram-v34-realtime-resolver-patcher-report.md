# RyukGram v34 — Unified Runtime Browser: realtime resolver + patcher

Base: `Ryukgram-Fork-experimental2.zip` (v33 ABI browsers). Branch: `experimental2`.

The browser stops being a "patch plan viewer". Each symbol is now resolved live,
the sideload-safe strategy is auto-selected, and a working Apply/Revert drives the
same persisted install backends used everywhere in the tweak.

## What's new

### 1. `SCIRuntimeXrefScanner` (new file, `src/Features/Gating/`)
Realtime, in-process, **read-only** ARM64 xref resolver. Given a DATA descriptor's
runtime address it scans the defining image's `__text` for `adrp+add` computing
that address, then the following `bl`, and resolves the callee via `dladdr` →
the concrete consumer/reader (e.g. `IGMobileConfigBooleanValueForInternalUse`).

- Bounded by an instruction budget (default 6M) and a max-hit count.
- Runs off the main thread; completion on main.
- Strictly in-bounds (`__text` only, range-checked). Cannot write or crash code.
- adrp/add/bl decode unit-validated in gcc **and** against the real Instagram binary.

### 2. Engine widened safely (`SCICSymbolStub`)
The MobileConfig descriptor reader-filter now accepts **runtime-confirmed**
descriptors (`+canForceAsParamDescriptor:` = curated list OR dlsym-resolvable).
This is safe to widen because the filter matches by the descriptor **pointer**
against the reader's argument — a symbol that is not the consumed descriptor
simply never matches, so the original value is returned unchanged.

### 3. Interactive resolver + patcher detail screen
`SCICRealtimeDetailViewController` rebuilt as an inset-grouped, glass table:
- **Resolution**: kind, owning image, section, symtab addr, live dlsym addr, ABI.
- **Patch**: auto-selected strategy + working **Apply** / **Revert** + live state/hits.
- **Realtime xref / consumer**: runs the scan on open (DATA) or on demand; lists
  resolved consumers with caller / load site / image.
- **Disassembly / bytes**: lightweight ARM64 decode or hexdump.
- Copy/export of the full resolved report.

Apply routes to the existing persisted backends: fishhook BOOL hardstub, fishhook
typed force (int64/double/string), MobileConfig descriptor reader-filter, and ObjC
IMP swizzle (`SCISymbolBrowserEngine`). Originals are kept for revert.

## Binary validation (Instagram 434 / FBShared, this upload)
- Typed readers (`IGMobileConfigInteger/StringValueForInternalUse`,
  `EasyGatingGetInt32/Int64/Double/CopyString`) are all imported → typed force works.
- DATA descriptors (`ig_is_employee`, …) are referenced by the exec but are opaque;
  a fake-pointer rebind is unsafe, so the resolver uses the reader-filter (safe).
- `SUBSBenefitDataProvider` is a **Swift** class (`_TtC23SUBSBenefitDataProvider…`),
  stripped, not exposed as a classic ObjC class → resolved at runtime; if its calls
  are Swift direct-dispatch there is **no sideload-safe patch** (jailbreak only), and
  the resolver says so honestly rather than installing a no-op.

## Honest sideload boundary (unchanged, enforced)
- No `__TEXT` code patching (W^X). No blind DATA byte-patch without a validated layout.
- C-symbol stubs (BOOL/typed/param) are re-attached **in-session**, not at cold launch
  — forcing MobileConfig/MCI readers at cold launch caused the documented startup
  crash. ObjC overrides do reapply at cold launch. The Apply cell states which applies.
- The xref scan resolves FB-internal consumers reliably; exec-side GOT/Swift-dispatched
  consumers may not resolve and are reported as such.
