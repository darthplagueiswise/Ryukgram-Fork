# Instagram / FBSharedFramework — r2 + Capstone audit

Audited binaries:

- `Instagram`: `a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa`
- `FBSharedFramework`: `22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc`

Tools used on the real uploaded Mach-O files:

- Radare2 core through the `r2core` Emscripten build, configured as `asm.arch=arm`, `asm.cpu=v8`, `asm.bits=64`.
- Capstone ARM64 5.0.7/5.0.9.
- LIEF 1.0.0 for Mach-O segment mapping and export validation.

## 1. Why the rows were visible but not clickable

`-[IGBugReportMenuViewController tableView:shouldHighlightRowAtIndexPath:]`

- Instagram VA: `0x106cf2ea8`
- ABI: BOOL with `(UITableView *, NSIndexPath *)`

Both Radare2 and Capstone decode the same control flow:

```asm
0x106cf2edc  bl    0x101396afc
0x106cf2ee0  and   w9, w0, #0xff
0x106cf2ee8  tst   w9, #0x1fe0
0x106cf2eec  b.ne  0x106cf2f2c       ; selected row families -> YES
...
0x106cf2f04  ldrb  w8, [x21, x8]     ; compact Swift state byte
0x106cf2f08  cmp   w8, #0
0x106cf2f0c  ccmp  w8, #3, #4, ne
0x106cf2f10  b.eq  0x106cf2f24       ; state 0 or 3 -> NO
0x106cf2f18  ldr   x8, [x21, x8]     ; provider/state object
0x106cf2f1c  bl    0x10262f468       ; evaluate availability
...
0x106cf2f2c  mov   w19, #1
```

The previous tweak changed initializer flags and some ivars, but never hooked this exact method. Therefore the rows could be rendered while UIKit still refused highlight/selection.

The fix adds a class-specific ABI-validated hook and returns `YES` only for the exact visible titles enabled by RyukGram:

- `Internal Settings`
- `Dogfooding Assistant`
- `Logged Out Internal Settings`

Every other row calls the native original.

## 2. Internal Settings has a second employee-or-test-user decision

`-[IGBugReportMenuViewController tableView:didSelectRowAtIndexPath:]`

- Instagram VA: `0x104aaf610`
- ABI: `v32@0:8@16@24`

Radare2 resolves the jump-table dispatch and the explicit denied branch:

```asm
0x104aaf660  bl    0x101396afc
0x104aaf664  and   w11, w0, #0xff
0x104aaf668  adrp  x8, 0x10a702000
0x104aaf66c  add   x8, x8, #0x2dc
0x104aaf674  ldrsw x9, [x8, x11, lsl #2]
0x104aaf67c  br    x10
```

The denied path references:

```asm
0x104aaf850  add x8, x8, #0xe00   ; "Internal Settings Access Denied"
0x104aaf85c  add x8, x8, #0xe20   ; "Only employees or test accounts ..."
```

This proves that `showInternalSettings=YES` is only a display gate. The action repeats an employee-or-test-user decision.

The fix now combines three client-side surfaces without treating DATA as functions:

1. Existing zero-argument BOOL getters are discovered at runtime and hooked only after exact ABI validation (`B16@0:8`, `c16@0:8` or `C16@0:8`). Candidate selectors include existing `isEmployee`, `isTestUser`, employee-or-test-user, dogfood/dogfooder/dogfooding and internal-user getters. Missing selectors are never added.
2. Matching BOOL setters are forwarded as `YES` while the master is enabled.
3. The real 16-byte MobileConfig DATA descriptors `ig_is_employee` and `ig_is_employee_or_test_user` are forced through the descriptor-pointer-filtered MobileConfig BOOL reader. They are not passed to fishhook or `MSHookFunction` as callable functions.

For the exact `Internal Settings` row, the fix first invokes the already validated native `IGURLHandler` route (`instagram://internal_settings`). If that route cannot open, it falls back to the original row handler rather than replacing it with an unrelated screen.

## 3. Cell construction confirms separate display and provider gates

`-[IGBugReportMenuViewController tableView:cellForRowAtIndexPath:]`

- Instagram VA: `0x10462bf38`

Capstone resolves the native strings and conditions:

```asm
0x10462c040  cmp   x23, #2
0x10462c044  csel  x4, x8, xzr, eq
0x10462c054  adrp  x8, 0x10cad8000
0x10462c058  add   x8, x8, #0x170   ; "Internal Settings"
...
0x10462c0a4  ldrb  w21, [x9, x8]
0x10462c0a8  cmp   w21, #0
0x10462c0ac  ccmp  w21, #3, #4, ne
...
0x10462c114  adrp  x8, 0x10cabd000
0x10462c118  add   x8, x8, #0x1c0   ; "Dogfooding Assistant"
```

The menu uses both the availability enum and a compact provider/state byte. This is why forcing only `showDogfoodingAssistant` did not make the row actionable.

## 4. The FBT holder chain is not the logged-out owner in this process

The runtime alert proved:

```text
sessionlessContextManagerHolder=nil
```

Static analysis agrees that `setupFBTSessionlessContextManagerHolder:` only stores the supplied object at the holder offset. A nil holder means that graph was never populated for this Instagram path; repeatedly resolving it cannot produce a manager.

## 5. Exact logged-out MobileConfig fetch path

The Instagram startup path at `0x102c5604c` calls the import stub after preparing the device-session dependencies and completion in `x3`:

```asm
0x102c5603c  bl    0x1026c73b4
0x102c56040  bl    0x1026c73c0
0x102c56044  add   x3, sp, #8
0x102c56048  bl    0x10269f7dc
0x102c5604c  bl    0x109e5308c
```

LIEF resolves the FBSharedFramework export:

```text
IGMobileConfigTryUpdateConfigsWithCompletion = 0x72da74
```

Radare2 and Capstone decode its wrapper as:

```asm
0x72da74  mov w4, #0
0x72da78  b   0x72fee4
```

So the exported public wrapper receives `x0..x3` and supplies the private fifth argument itself. The correct call is:

```objc
IGMobileConfigTryUpdateConfigsWithCompletion(
    deviceSession.mobileConfig,
    deviceSession.loggedOutNetworker,
    nil,
    completion
);
```

The current resolver already uses this exact C bridge. This audit adds the missing strong runtime capture path for the `deviceSession` and `userSession` arguments from both real `IGBugReportMenuViewController` initializers. That removes the unresolved extern/capture gap and gives both the Dev row and the native logged-out Force Fetch action the same live dependencies.

## 6. Dogfooding Assistant

The binary contains:

- protocol `IGBugReportingDogfoodingAssistantMenuRowProviding`
- Swift lazy storage `$__lazy_storage_$_dogfoodingAssistantSocket`
- `showDogfoodingAssistant`

The socket is Swift opaque storage, not an Objective-C object that can be found by a generic ivar-as-`id` walk. The correction does not fabricate it and does not route to DirectNotes. It makes the exact row selectable, broadens the real local identity gates, preserves the native handler, and retains the existing native Dogfooding Settings fallback only when a real config/provider was captured.

## Implemented file

`src/Features/Dogfooding/SCIEmployeeDogfoodNativeBridge.m`

Main guarantees:

- exact initializer ABIs, exact `shouldHighlight` and `didSelect` ABIs;
- no global UITableView hook;
- no DirectNotes fallback;
- no DATA-as-function hook;
- type-aware Swift/ObjC ivar writes, trying both underscored and non-underscored runtime names;
- repeat-safe installation and late-loaded class rescan;
- descriptor overrides are owned by the Employee master and cleared when that master is disabled;
- unrelated bug-report rows always retain native behavior.
