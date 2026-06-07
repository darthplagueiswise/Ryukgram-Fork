# Dogfood Browser repagination

This patch rebuilds `SCIDogfoodBrowserViewController` around four modes instead of one giant mixed table:

- Run: runtime readiness, authorized native openers and Autofill Internal actions.
- Runtime: static stubs, live objects captured by named hooks and settings targets.
- Captures: Notes Dogfooding persistence snapshots and optional MobileConfig dogfood/internal reads.
- Logs: recent open attempts, exceptions and runtime diagnostics.

The browser no longer prints the whole runtime state in section headers, no longer uses hard-coded row counts for actions, and no longer presents huge JSON blobs in `UIAlertController`. Row details now open in a pushed monospaced JSON/detail view with a copy action.

Functional fixes:

- `refreshAll` now populates MobileConfig reads before applying filters, so the table is not reloaded with stale/empty params first.
- Native Dogfood open state is exposed as readiness cards before attempting presentation.
- Autofill Internal actions ask for confirmation and log failures instead of silently firing from a row tap.
- Search is applied consistently across status rows, actions, stubs, live objects, settings targets, captures, params and logs.
- Runtime live objects are sorted by numeric `lastSeen` before being capped, so recent captures are not lost because of arbitrary `NSMapTable` enumeration order.
- The browser keeps the old no-global-heap-scan / no-global-UIViewController-hook model.

Selector policy:

The runtime/actions still use only selectors that were present in the static LIEF + Capstone dump. UI-only selectors such as `refreshAll` and `modeChanged:` are local controller methods and are not target hooks.
