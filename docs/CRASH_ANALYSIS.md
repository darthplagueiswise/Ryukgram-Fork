# Crash analysis · 2026-08-15

## Evidence

The supplied Instagram crash report records `EXC_CRASH (SIGABRT)`. The last
Objective-C exception is raised by
`-[NSURL(NSURLPathUtilities) URLByAppendingPathComponent:]` while resolving
`IGFamilyAppGroupContainerURL`.

The first injected caller is image 4 at offset `0x5CCC`:

- image: `pluginsinject.dylib`
- UUID: `CDD15DB1-5057-3E5A-BCED-76372D2B2D47`
- mapped size: 32 KiB

`RyukGram.dylib` is a separate image in the same process and is not the frame
that supplied the invalid path component. The old helper implementation passed
an unchecked App Group value into path construction and was injected in
addition to RyukGram.

The `RyukGram.dylib` extracted from build 849 is the exact image in this crash:
its Mach-O UUID is `633C7CC8-A021-32BA-B76D-200F0C8E45DB`, matching image 6 in
the `.ips`. LIEF identifies it as an arm64 dylib with 35 dependencies and a
2,855,968-byte `__text` section; it has no dependency or string marker for
`pluginsinject.dylib`/`zxPluginsInject.dylib`. That confirms the crashing helper
was added later as a second injected image rather than linked into RyukGram.

Capstone also decoded both RyukGram return addresses in the exception trace:

- `0xD4CA4` is `+0x18` inside the function beginning at `0xD4C8C`, immediately
  after an indirect `blr x8` call at `0xD4CA0`;
- `0x298858` is `+0x1C` inside the function beginning at `0x29883C`, immediately
  after another indirect `blr x8` call at `0x298854`.

Neither is the throw site. The throw is the later frame
`pluginsinject.dylib + 0x5CCC` calling
`-[NSURL URLByAppendingPathComponent:]`, exactly as the Objective-C exception
backtrace reports.

## Fix in `dogfood`

- App Group, Keychain and CloudKit sideload compatibility now compiles directly
  into `RyukGram.dylib` from `src/Compatibility`.
- App Group input must be a nonempty `NSString` without path separators,
  `.`/`..`, or NUL before it can participate in a path.
- Every private Objective-C compatibility hook is installed only after its live
  method encoding is verified to have the expected object-return/object-argument
  ABI. Missing or changed CloudKit methods are skipped.
- The native container resolver runs first for a valid identifier. A real
  entitled mapping is preferred; the fallback is an app-local Application
  Support directory.
- Keychain rewriting is limited to an access group the installed app actually
  owns. CloudKit changes are gated by the process's real iCloud entitlements.
- All package workflows reject the former secondary fixer dylib names.
- “No plugins” now means only that `.appex` bundles are stripped. It uses the
  same self-contained RyukGram dylib as every other package mode.

## Binary gate

CI parses the produced arm64 Mach-O with LIEF, disassembles its `__text` section
with Capstone, checks the integrated compatibility/browser/glass markers, and
fails if an external fixer dependency or artifact is present.
