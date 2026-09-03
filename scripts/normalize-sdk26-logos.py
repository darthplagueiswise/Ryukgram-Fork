#!/usr/bin/env python3
"""Normalize only the legacy nested-%orig constructs used by RyukGramPriv.

Current Logos accepts top-level `%orig`/`%orig()` calls, but rejects passing the
directive through another Objective-C expression or a C macro argument.  This
pass rewrites only those known legacy callsites and deliberately leaves every
other `%orig()` in the source untouched.
"""
from pathlib import Path

path = Path("src/Tweak.x")
text = path.read_text(encoding="utf-8")
original = text

# IGDSLauncherConfig Liquid Glass gates.  SCIUtils returns YES when the tweak's
# liquid_glass_surfaces preference is enabled and otherwise returns the native
# gate.  Express that directly so %orig is a top-level return expression.
text = text.replace(
    'return [SCIUtils liquidGlassEnabledBool:%orig];',
    'if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) { return true; }\n    return %orig;'
)

# IMPORTANT: replace NONVOID first because its token contains the complete
# substring "VOID_HANDLESCREENSHOT".  Reversing this order creates `NONif`.
text = text.replace(
    'NONVOID_HANDLESCREENSHOT(%orig);',
    'if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return nil; } return %orig;'
)
text = text.replace(
    'VOID_HANDLESCREENSHOT(%orig);',
    'if (![SCIUtils getBoolPref:@"remove_screenshot_alert"]) { %orig; }'
)

if text != original:
    path.write_text(text, encoding="utf-8")
    print("[sdk26-logos] normalized legacy nested %orig constructs")
else:
    print("[sdk26-logos] no legacy constructs required normalization")
