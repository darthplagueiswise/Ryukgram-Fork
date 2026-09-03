#!/usr/bin/env python3
"""Normalize legacy Logos constructs rejected by the current Theos parser.

The RyukGramPriv source contains old patterns where `%orig` is nested inside an
Objective-C message or passed through a macro.  Current Logos rejects those
forms.  Rewrite only the known constructs into equivalent top-level `%orig`
statements/returns before preprocessing, without changing tweak behaviour.
"""
from pathlib import Path

path = Path("src/Tweak.x")
text = path.read_text(encoding="utf-8")
original = text

# Liquid Glass: never nest %orig inside an Objective-C message.  SCIUtils only
# forces YES when liquid_glass_surfaces is enabled; otherwise it returns the
# original gate.  Spell that logic out so Logos sees a plain `return %orig;`.
text = text.replace(
    'return [SCIUtils liquidGlassEnabledBool:%orig];',
    'if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) { return true; }\n    return %orig;'
)

# Screenshot hooks: passing %orig through a C macro is rejected by current
# Logos.  Expand the two legacy helpers at each callsite instead.  The macros
# can remain defined because they are no longer invoked with Logos directives.
text = text.replace(
    'VOID_HANDLESCREENSHOT(%orig);',
    'if (![SCIUtils getBoolPref:@"remove_screenshot_alert"]) { %orig; }'
)
text = text.replace(
    'NONVOID_HANDLESCREENSHOT(%orig);',
    'if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return nil; } return %orig;'
)

# Guard against reintroducing the invalid transformations from the earlier
# compatibility pass.
text = text.replace('%orig()', '%orig')

if text != original:
    path.write_text(text, encoding="utf-8")
    print("[sdk26-logos] normalized legacy nested %orig constructs")
else:
    print("[sdk26-logos] no legacy constructs required normalization")
