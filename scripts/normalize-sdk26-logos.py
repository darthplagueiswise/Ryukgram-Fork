#!/usr/bin/env python3
"""Normalize legacy RyukGramPriv Logos syntax for the SDK 26.5 toolchain.

Do not rewrite `%orig` generically.  Current Logos accepts top-level `%orig` and
`%orig()` but rejects `%orig` when it is nested inside another Objective-C/C
expression or passed as a macro argument.  Rewrite only the exact legacy method
forms present in src/Tweak.x, preserving their behavior.
"""
from pathlib import Path

path = Path("src/Tweak.x")
text = path.read_text(encoding="utf-8")
original = text

# Liquid Glass gates: SCIUtils forces YES when liquid_glass_surfaces is enabled;
# otherwise the native gate is returned.  Keep %orig as a top-level return.
text = text.replace(
    'return [SCIUtils liquidGlassEnabledBool:%orig];',
    'if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) { return true; }\n    return %orig;'
)

# Screenshot hooks.  Rewrite complete method definitions instead of replacing
# macro arguments: partial substitutions confuse Logos' generated method braces.
void_methods = {
    '- (void)setShouldBlockScreenshot:(BOOL)arg1 viewModel:(id)arg2 { VOID_HANDLESCREENSHOT(%orig); }': '''- (void)setShouldBlockScreenshot:(BOOL)arg1 viewModel:(id)arg2 {
    if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return; }
    %orig;
}''',
    '- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 { VOID_HANDLESCREENSHOT(%orig); }': '''- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 {
    if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return; }
    %orig;
}''',
    '- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 { VOID_HANDLESCREENSHOT(%orig); }': '''- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 {
    if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return; }
    %orig;
}''',
}
for old, new in void_methods.items():
    text = text.replace(old, new)

nonvoid_methods = {
    '- (id)visualMessageViewerController:(id)arg1 didDetectScreenshotForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 { NONVOID_HANDLESCREENSHOT(%orig); }': '''- (id)visualMessageViewerController:(id)arg1 didDetectScreenshotForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 {
    if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return nil; }
    return %orig;
}''',
    '- (id)initForController:(id)arg1 { NONVOID_HANDLESCREENSHOT(%orig); }': '''- (id)initForController:(id)arg1 {
    if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) { return nil; }
    return %orig;
}''',
}
for old, new in nonvoid_methods.items():
    text = text.replace(old, new)

# These macros may remain defined for source compatibility, but no Logos
# directive may be passed through them after normalization.
for forbidden in ('VOID_HANDLESCREENSHOT(%orig)', 'NONVOID_HANDLESCREENSHOT(%orig)'):
    if forbidden in text:
        raise SystemExit(f"[sdk26-logos] unnormalized legacy call remains: {forbidden}")

if text != original:
    path.write_text(text, encoding="utf-8")
    print("[sdk26-logos] normalized exact legacy nested-%orig methods")
else:
    print("[sdk26-logos] no legacy constructs required normalization")
