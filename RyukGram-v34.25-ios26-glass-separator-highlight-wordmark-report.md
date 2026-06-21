# RyukGram v34.25 — iOS 26 Liquid Glass list/menu corrective

Base: `Ryukgram-Fork-v34.24-ios26-title-bubble-liquidglass.zip`

## Changes

- Increased the menu title bubble emphasis without making it taller:
  - title font 19 -> 20 pt bold
  - tighter vertical padding
  - slightly wider intrinsic sizing for shorter titles
- Reduced glass panel opacity globally:
  - dark fill alpha 0.30 -> 0.20
  - light fill alpha 0.44 -> 0.34
  - separator alpha reduced slightly
- Fixed long full-width separators:
  - `UITableView` separator inset is now 16/16 by default
  - `UITableViewSeparatorInsetFromCellEdges` is requested when available
  - table layout margins and cell separator insets are consistently 16/16
- Added reusable selected/highlight styling:
  - `SCIUIKit26ApplyTableCellSelectionTint(UITableViewCell *, BOOL)`
  - current picker choice now gets a subtle primary-tinted Liquid Glass fill
  - pressed/highlighted rows use a softer label tint instead of a harsh edge-to-edge flash
- Reverted the IG wordmark picker/accessory back to the same menu path as the rest of the tweak:
  - removed the custom wordmark accessory-only button path from settings rows
  - wordmark menu options keep real titles instead of blank rows
  - wordmark now uses the same `UIButtonConfiguration`/native `UIMenu` behavior as other menu rows
- SCIOptionSheet no longer switches into special wordmark presentation mode; if that path is used, it renders the same generic option rows and selection highlight as every other picker.

## Validation

- `git diff --no-index --check /mnt/data/rgf_base /mnt/data/rgf_edit` emitted no whitespace/conflict-marker diagnostics.
- Theos build was not run in this container because `$THEOS` and iPhoneOS26.2.sdk are not installed here.

## Files touched

- `src/UI/SCIUIKit26LiquidGlass.h`
- `src/UI/SCIUIKit26LiquidGlass.m`
- `src/UI/SCIOptionSheet.m`
- `src/Settings/SCISetting.m`
- `src/Settings/SCISettingsViewController.m`
