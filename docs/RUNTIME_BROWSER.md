# Real-time multi-framework browser

The developer browser takes a fresh dyld snapshot whenever it refreshes. Its
image picker contains the loaded app executable plus app-owned frameworks and
dylibs. Selecting an image runs one of two live scanners:

- Objective-C runtime enumeration for ABI-safe arm64 `BOOL` methods with zero
  arguments or one object/integer/pointer argument;
- bounded `LC_SYMTAB` parsing for functions, data, undefined symbols, and their
  current ASLR-adjusted addresses.

There is no preloaded row table. Class lists, method lists, symbol rows, live
values, and addresses are rebuilt for the selected image and are never written
to disk. The only browser preferences are the stable bundle-relative image
identity, scan mode, filter scope, and exact user-created method overrides.

Structural/runtime noise is excluded before display or hook installation,
including `isEqual…`, `respondsToSelector…`, `canRespond…`, responder plumbing,
common gesture/text delegates, and mechanical view-state accessors. The
Employee/Dogfood scope filters the remaining live methods by employee,
dogfood, internal, launcher, staff, and metamate names.

Unknown methods are never invoked merely to populate a cell. A native boolean
appears only after the installed passthrough hook observes a real app call.
Long-pressing a row offers force true, force false, or native behavior. Exact
overrides are restored idempotently as their owning image loads.

The five-finger one-second shortcut is installed on each live `UIWindow`, not
on a version-specific Instagram root controller. New key windows and scenes
receive it automatically.
