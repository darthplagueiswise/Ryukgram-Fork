# RyukGram StartupGuard patch

Add `SCIStartupGuard.m` to:

`src/Features/ExpFlags/SCIStartupGuard.m`

The existing Makefile auto-discovers `.m/.xm/.x` files under `src`, so no Makefile change is needed.

What it does:

- Tracks the active override signature at launch.
- If the same signature fails to reach the 20s stable marker 3 launches in a row, disables:
  - active MobileConfig broker overrides: `mcbr:<brokerID>:<hex>`
  - enabled broker observer hooks: `hook:<brokerID>`
  - selected experimental prefs/toggles from the allowlist
- Stores debug data in:
  - `sci.startupguard.last_report`
  - `sci.startupguard.event_log`
  - `sci.startupguard.last_disabled`
- Shows a one-time alert on the next stable launch with what was disabled.

Build:

```sh
make clean
make package FINALPACKAGE=1
```
