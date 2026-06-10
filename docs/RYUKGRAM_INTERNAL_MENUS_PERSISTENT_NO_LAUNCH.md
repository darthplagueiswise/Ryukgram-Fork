# RyukGram — Internal menus persistent toggle without launch execution

This patch keeps `sci_internal_menus` persistent, but stops persisted ON from executing during Instagram launch / scene-create.

Behavior:

- The toggle remains ON/OFF across restarts through `NSUserDefaults`.
- `%ctor` does not install or force internal menu hooks.
- There is no manual Apply button.
- When the user explicitly flips the toggle ON inside Settings, `SCIInternalMenusForceApplyNow()` applies the local runtime hooks for the current session.
- The master toggle no longer fans out to `sci_force_ig_internal_employee`, `sci_force_internal_settings_menu`, or `sci_force_mc_internal_use_all`.

Reason:

The crash was a scene-create watchdog deadlock. Persisted startup execution drove Instagram into XPlugins/FBAnalytics during `FBAnalyticsCurrentSerializedAppIdentity()`'s `pthread_once`. Keeping persistence while removing launch execution prevents that path from running before the UI exists.
