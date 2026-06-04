#!/usr/bin/env bash
set -euo pipefail

: "${THEOS:?THEOS must be set}"
SDK="$THEOS/sdks/iPhoneOS26.0.sdk"
UIKIT_HEADERS="$SDK/System/Library/Frameworks/UIKit.framework/Headers"

printf 'Validating SDK: %s\n' "$SDK"
[ -d "$SDK" ] || { echo "::error::Missing iPhoneOS26.0.sdk in $THEOS/sdks"; exit 1; }
[ -d "$UIKIT_HEADERS" ] || { echo "::error::Missing UIKit headers in iPhoneOS26.0.sdk"; exit 1; }

printf 'UIKit Glass/Liquid header candidates, if exported by this SDK:\n'
{ grep -R "Glass\|Liquid" "$UIKIT_HEADERS" 2>/dev/null || true; } | head -100

# Validate the SDK exports the Liquid Glass APIs actually referenced by this project.
grep -R "UIGlassEffect" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing UIGlassEffect"; exit 1; }
grep -R "UIGlassEffectStyleRegular" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing UIGlassEffectStyleRegular"; exit 1; }
grep -R "UIGlassEffectStyleClear" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing UIGlassEffectStyleClear"; exit 1; }
grep -R "glassButtonConfiguration" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing glassButtonConfiguration"; exit 1; }
grep -R "prominentGlassButtonConfiguration" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing prominentGlassButtonConfiguration"; exit 1; }
grep -R "clearGlassButtonConfiguration" "$UIKIT_HEADERS" >/dev/null 2>&1 || { echo "::error::Missing clearGlassButtonConfiguration"; exit 1; }

printf 'SDK 26 Liquid Glass headers: OK\n'
