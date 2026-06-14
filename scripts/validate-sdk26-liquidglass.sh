#!/usr/bin/env bash
set -euo pipefail

: "${THEOS:?THEOS must be set}"
SDK="$THEOS/sdks/iPhoneOS26.2.sdk"
UIKIT_HEADERS="$SDK/System/Library/Frameworks/UIKit.framework/Headers"

printf 'Validating SDK: %s\n' "$SDK"
[ -d "$SDK" ] || { echo "::error::Missing iPhoneOS26.2.sdk in $THEOS/sdks"; exit 1; }
[ -d "$UIKIT_HEADERS" ] || { echo "::error::Missing UIKit headers in iPhoneOS26.2.sdk"; exit 1; }

printf 'UIKit Glass/Liquid header candidates, if exported by this SDK:\n'
{ grep -R "Glass\|Liquid" "$UIKIT_HEADERS" 2>/dev/null || true; } | head -100

grep -R "UIGlassEffect" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing UIGlassEffect"; exit 1; }
grep -R "UIGlassEffectStyleRegular" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing UIGlassEffectStyleRegular"; exit 1; }
grep -R "UIGlassEffectStyleClear" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing UIGlassEffectStyleClear"; exit 1; }
grep -R "glassButtonConfiguration" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing glassButtonConfiguration"; exit 1; }
grep -R "prominentGlassButtonConfiguration" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing prominentGlassButtonConfiguration"; exit 1; }
grep -R "clearGlassButtonConfiguration" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing clearGlassButtonConfiguration"; exit 1; }

printf 'SDK 26 Liquid Glass headers: OK\n'

printf 'Validating project-side SDK 26 UI compatibility rules...\n'
if grep -RIn --include='*.x' --include='*.xm' '%hook[[:space:]]\+UIScrollEdgeEffect' src >/tmp/sdk26_ui_forbidden.log 2>/dev/null; then
  cat /tmp/sdk26_ui_forbidden.log
  echo "::error::Do not Logos-hook UIScrollEdgeEffect directly; resolve it dynamically with NSClassFromString/MSHookMessageEx because the host app deployment target/minOS is below iOS 26."
  exit 1
fi
if grep -RIn --include='*.x' --include='*.xm' 'SCIUIKit26' src >/tmp/sdk26_ui_forbidden.log 2>/dev/null; then
  cat /tmp/sdk26_ui_forbidden.log
  echo "::error::RyukGram-owned UIKit 26 visual helpers must not be used from Instagram hook files."
  exit 1
fi
if grep -RIn --include='*.h' 'export:(SEL)export\|[[:space:]]export[),;]' src >/tmp/sdk26_ui_forbidden.log 2>/dev/null; then
  cat /tmp/sdk26_ui_forbidden.log
  echo "::error::Public headers are imported by Objective-C++ files; do not use export as a parameter identifier."
  exit 1
fi
if grep -RIn 'SCIAdaptiveGlass\|SCIGlassParamCell\|SCIGlassSearchBar\|SCIApplyLiquidGlassToViewTree\|SCIRealLiquidGlassAutoHooks' src >/tmp/sdk26_ui_forbidden.log 2>/dev/null; then
  cat /tmp/sdk26_ui_forbidden.log
  echo "::error::Old temporary AdaptiveGlass/global-tree styling symbols are not allowed."
  exit 1
fi
test -f src/UI/SCIUIKit26LiquidGlass.h || { echo "::error::Missing UIKit 26 Liquid Glass helper header"; exit 1; }
test -f src/UI/SCIUIKit26LiquidGlass.m || { echo "::error::Missing UIKit 26 Liquid Glass helper implementation"; exit 1; }
printf 'Project SDK 26 UI compatibility: OK\n'
