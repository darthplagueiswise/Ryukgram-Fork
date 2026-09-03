#!/usr/bin/env python3
"""Normalize legacy Logos constructs rejected by the current Theos parser.

The upstream/private source predates the Logos parser shipped with the SDK 26.5
build environment.  Keep the source semantics intact while making nested %orig
expressions unambiguous for preprocessing.
"""
from pathlib import Path

path = Path("src/Tweak.x")
text = path.read_text(encoding="utf-8")
original = text

text = text.replace(
    '#define VOID_HANDLESCREENSHOT(orig) [SCIUtils getBoolPref:@"remove_screenshot_alert"] ? nil : orig;',
    '#define VOID_HANDLESCREENSHOT(orig) do { if (![SCIUtils getBoolPref:@"remove_screenshot_alert"]) { orig; } } while (0)'
)
text = text.replace(
    '#define NONVOID_HANDLESCREENSHOT(orig) return VOID_HANDLESCREENSHOT(orig)',
    '#define NONVOID_HANDLESCREENSHOT(orig) do { if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) return nil; return (orig); } while (0)'
)

# Current Logos needs an explicit call form when %orig is nested inside another
# Objective-C/C expression.  Bare top-level `%orig;` remains untouched.
text = text.replace('liquidGlassEnabledBool:%orig]', 'liquidGlassEnabledBool:%orig()]')
text = text.replace('VOID_HANDLESCREENSHOT(%orig);', 'VOID_HANDLESCREENSHOT(%orig());')
text = text.replace('NONVOID_HANDLESCREENSHOT(%orig);', 'NONVOID_HANDLESCREENSHOT(%orig());')

if text != original:
    path.write_text(text, encoding="utf-8")
    print("[sdk26-logos] normalized src/Tweak.x")
else:
    print("[sdk26-logos] no legacy constructs required normalization")
