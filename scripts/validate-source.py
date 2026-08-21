#!/usr/bin/env python3
"""Fail fast on migration/build regressions before invoking Theos."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"source validation error: {message}", file=sys.stderr)
    raise SystemExit(1)


def logos_orig_tail(line: str) -> str | None:
    for match in re.finditer(r"%orig\b", line):
        cursor = match.end()
        while cursor < len(line) and line[cursor].isspace():
            cursor += 1
        if cursor < len(line) and line[cursor] == "(":
            depth = 0
            while cursor < len(line):
                char = line[cursor]
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                    if depth == 0:
                        cursor += 1
                        break
                cursor += 1
            if depth:
                return line[match.end():]
        tail = line[cursor:]
        if not re.fullmatch(r"\s*;\s*", tail):
            return tail
    return None


makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
if "TARGET := iphone:clang:26.5:15.0" not in makefile:
    fail("Makefile must build with the iOS 26.5 SDK and iOS 15 deployment target")
if "-include src/RYGPrefix.h" not in makefile:
    fail("RYGPrefix.h is not the forced prefix header")
if "src/Compatibility" not in makefile:
    fail("the integrated compatibility-layer contract is missing")

if (ROOT / "src/BundleAssets/ryg_mc_names.bin").exists():
    fail("preloaded MobileConfig catalog ryg_mc_names.bin must not ship")

for legacy_module in (ROOT / "modules/zxPluginsInject", ROOT / "modules/SideloadPatch"):
    if legacy_module.exists() and any(legacy_module.iterdir()):
        fail(f"separate compatibility module still exists: {legacy_module.relative_to(ROOT)}")

# Competing implementations that previously stacked hooks/renderers remain
# forbidden. RYGRuntimeClassBrowser is intentionally NOT on this list: it is the
# structural, non-classifying Class -> methods/properties enumerator used by the
# live Runtime Browser.
for obsolete in (
    "src/Debug/RYGDeveloperFeatureViewController.m",
    "src/Debug/RYGDeveloperGateViewController.m",
    "src/Debug/RYGDeveloperExactSurfaceViewController.m",
    "src/Debug/RYGDeveloperRuntimeBrowserViewController.m",
    "src/Debug/RYGDeveloperEasyGatingControls.m",
    "src/Debug/RYGCFunctionOverrideEngine.m",
    "src/Debug/RYGDeveloperRuntimeScanner.m",
    "src/UI/RYGSettingsMenuGlassFix.m",
    "src/Settings/RYGSettingsMenuLiquidGlass.m",
    "src/Features/ExpFlags/RYGMobileConfigExternalSeenTracker.m",
    "src/Features/ExpFlags/RYGMobileConfigParamTableCompatibility.m",
    "src/Features/ExpFlags/RYGMobileConfigNativeSync.m",
):
    if (ROOT / obsolete).exists():
        fail(f"obsolete competing implementation returned: {obsolete}")

mc_header_path = ROOT / "src/Features/ExpFlags/RYGMobileConfig.h"
mc_impl_path = ROOT / "src/Features/ExpFlags/RYGMobileConfig.xm"
mc_json_path = ROOT / "src/Features/ExpFlags/RYGMobileConfigJSONIO.m"
easy_path = ROOT / "src/Debug/RYGEasyGatingRuntime.m"
mobile_config_bridge_path = ROOT / "src/Features/ExpFlags/RYGMobileConfigBridge.m"
runtime_engine_path = ROOT / "src/Debug/RYGRuntimeBrowserEngine.m"
runtime_index_path = ROOT / "src/Debug/RYGRuntimeIndex.m"
runtime_view_path = ROOT / "src/Debug/RYGFastRuntimeBrowserViewController.m"
topic_path = ROOT / "src/Debug/RYGDeveloperTopicViewController.m"
setting_path = ROOT / "src/Settings/RYGSetting.m"
settings_entry_path = ROOT / "src/Features/General/RYGSettingsMenuEntry.x"
liquid_glass_path = ROOT / "src/UI/RYGLiquidGlass.m"

mc_header = mc_header_path.read_text(encoding="utf-8")
for type_name, discriminator in (
    ("RYGMCTypeBool", 1),
    ("RYGMCTypeInt", 2),
    ("RYGMCTypeString", 3),
    ("RYGMCTypeDouble", 4),
):
    if not re.search(rf"\b{type_name}\s*=\s*{discriminator}\b", mc_header):
        fail(f"native MobileConfig discriminator drifted: {type_name} must equal {discriminator}")
if "RYGMCTypeIsRuntimeValue" not in mc_header:
    fail("MobileConfig type validation helper is missing")

mc_impl = mc_impl_path.read_text(encoding="utf-8")
for marker in (
    "_ZN12mobileconfig17typeFromParameterEy",
    "_ZN12mobileconfig23kMobileConfigParamsListE",
    "_ZN12mobileconfig23kMobileConfigParamsSizeE",
    '@"FBMobileConfigStartupConfigs"',
    '@"setOverrideForParam:andValue:"',
    '@"removeOverrideForParam:"',
    "descriptorAt:",
    "exportedParamCount",
    "rygCanonicalPointerValue",
):
    if marker not in mc_impl:
        fail(f"validated MobileConfig contract marker is missing: {marker}")
for forbidden in (
    "getOrCreateOverridesTable",
    "FBMobileConfigOverridesTable22updateOverrideForParam",
    'class_getInstanceVariable([manager class], "_configManager")',
):
    if forbidden in mc_impl:
        fail(f"obsolete C++ MobileConfig override path returned: {forbidden}")
if "dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC))" in mc_impl:
    fail("MobileConfig overrides must not be auto-reapplied during app startup")

mc_json = mc_json_path.read_text(encoding="utf-8")
for marker in ('@"_qe_overrides_"', '@": : "', "RYGMCParseCanonicalJSONValue"):
    if marker not in mc_json:
        fail(f"canonical MobileConfig JSON contract marker is missing: {marker}")
json_header = (ROOT / "src/Features/ExpFlags/RYGMobileConfigJSONIO.h").read_text(encoding="utf-8")
if "RYGMCNameMappingImportModeMerge" not in json_header or "mode:(RYGMCNameMappingImportMode)mode" not in mc_json:
    fail("id_name_mapping Replace/Merge import contract is missing")

easy = easy_path.read_text(encoding="utf-8")
for marker in (
    'name = "EasyGatingGetBoolean_Internal_DoNotUseOrMock"',
    "rebind_symbols_image",
    "RYGResolveFinalGateID",
    "wrapperAddress + 0x34",
    "RYGEasyGatingImageRangeHasProtection",
    "VM_PROT_READ | VM_PROT_EXECUTE",
):
    if marker not in easy:
        fail(f"sideload-safe Easy Gating wrapper/final-ID contract is missing: {marker}")
if re.search(r'dlsym\s*\([^\n]*"EasyGatingPlatformGetBoolean"', easy):
    fail("Easy Gating must not patch the signed FBSharedFramework platform function")
if "ryg_easy_gating_platform_bool_overrides_v2" not in easy:
    fail("Easy Gating final-ID persistence namespace is missing")

mobile_config_bridge = mobile_config_bridge_path.read_text(encoding="utf-8")
for forbidden in (
    "RYGBridgeDataDirectoryScore",
    "RYGBridgeResolveSignedAppGroupDataDirectory",
    "RYGBridgeSignedApplicationGroups",
    "containerURLForSecurityApplicationGroupIdentifier",
):
    if forbidden in mobile_config_bridge:
        fail(f"MobileConfig guessed App Group/account fallback returned: {forbidden}")
for marker in ("hasSuffix:@\".data\"", "there is deliberately no guessed fallback"):
    if marker not in mobile_config_bridge:
        fail(f"exact native MobileConfig data-directory contract is missing: {marker}")

runtime_engine = runtime_engine_path.read_text(encoding="utf-8")
for marker in (
    "objc_copyClassNamesForImage",
    "objc_getClassList",
    "class_getImageName",
    "method_getReturnType",
    "method_getArgumentType",
    "method_getNumberOfArguments",
    'strchr("BcC"',
):
    if marker not in runtime_engine:
        fail(f"direct Runtime Browser ABI/image marker is missing: {marker}")
if "__attribute__((constructor))" in runtime_engine or "_dyld_register_func_for_add_image" in runtime_engine:
    fail("Runtime Browser must not reinstall developer overrides at process startup/image load")
if "NSUserDefaults" in runtime_engine and "ryg_runtime_bool_overrides" in runtime_engine:
    fail("generic Runtime Browser overrides must remain process-local")

runtime_index = runtime_index_path.read_text(encoding="utf-8")
for marker in (
    "objc_copyClassNamesForImage",
    "class_copyMethodList",
    'strchr("BcC"',
    "RYGIndexIMPBelongsToHeader",
    "isStructuralNoiseSelectorName",
    "requestIndexForImagePath",
    "invalidate",
):
    if marker not in runtime_index:
        fail(f"live Runtime index marker is missing: {marker}")

runtime_view = runtime_view_path.read_text(encoding="utf-8")
for marker in (
    'initWithItems:@[@"Objective-C", @"C Symbols"]',
    "RYGRuntimeIndex",
    "requestIndexForImagePath",
    "runtimeImagePaths",
    "refreshTapped",
    "Force On",
    "Force Off",
    "Native",
    "machOSymbolsForImagePath",
    "self.view.layoutMarginsGuide",
):
    if marker not in runtime_view:
        fail(f"structural live Runtime Browser marker is missing: {marker}")
if "preloaded" in runtime_view.lower() or "bundled table" in runtime_view.lower():
    fail("Runtime Browser must not ship a preloaded class/method table")
if re.search(r"imageButton\.(?:leading|trailing)Anchor[^\n]*constant:", runtime_view):
    fail("Runtime Browser image menu must use adaptive system layout margins")

topic = topic_path.read_text(encoding="utf-8")
for marker in (
    "_TtC25IGOverlayStoriesTrayDebug39IGOverlayStoriesTrayDebugViewController",
    "_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs",
    "_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper",
    "_TtC21IGConsumerSubsService21IGConsumerSubsService",
    "_TtC17IGBugReporterMenu29IGBugReportMenuViewController",
    "showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:",
    "_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController",
    "_TtC20IGDogfoodingSettings20IGDogfoodingSettings",
    "_TtC35IGDogfoodingAssistantLauncherClient35IGDogfoodingAssistantLauncherClient",
):
    if marker not in topic:
        fail(f"validated Developer native owner/selector is missing: {marker}")
for forbidden in ("keywords:", "RYGDevContainsAny", "boolMethodsForSurface"):
    if forbidden in topic:
        fail(f"Developer topic preclassification returned: {forbidden}")
if 'initialQuery:@"settings ishidden|' in topic:
    fail("hidden Settings browser incorrectly requires every visibility gate to contain the word settings")
if 'initialQuery:@"ishidden|shouldhide|shouldshow|canshow|isvisible|isavailable|shoulddisplay"' not in topic:
    fail("hidden Settings browser live visibility query is missing")
for marker in (
    'initialQuery:@"prism"',
    'initialQuery:@"liquidglass|throwback|glass"',
    'initialQuery:@"storytray|storiestray|storygrid|storiesgrid"',
    'initialQuery:@"dogfood|employee|internal"',
):
    if marker not in topic:
        fail(f"Developer live cross-image surface query is missing: {marker}")

setting = setting_path.read_text(encoding="utf-8")
for marker in ("UIAction.class", "UICommand.class", "RYGLiquidGlassConfigureButton", "setDefaultContentInsets"):
    if marker not in setting:
        fail(f"settings menu Liquid Glass/state marker is missing: {marker}")

settings_entry = settings_entry_path.read_text(encoding="utf-8")
for marker in (
    "kRYGProfileSettingsLongPressKey",
    "kRYGTabSettingsLongPressKey",
    "objc_getAssociatedObject",
    "ryg_settingsShortcutLongPress:",
):
    if marker not in settings_entry:
        fail(f"idempotent settings long-press contract is missing: {marker}")
if "gestureRecognizers.count == 0" in settings_entry:
    fail("profile settings long-press must coexist with Instagram's native recognizers")
if "@selector(handleLongPress:)" in settings_entry:
    fail("settings shortcut reintroduced a collision-prone generic long-press selector")

liquid_glass = liquid_glass_path.read_text(encoding="utf-8")
if 'return ![RYGUtils getBoolPref:@"liquid_glass_force_off"]' not in liquid_glass:
    fail("Liquid Glass availability must preserve UIKit's automatic accessibility adaptations")
if "return !UIAccessibilityIsReduceTransparencyEnabled()" in liquid_glass:
    fail("Liquid Glass must not be disabled when Reduce Transparency is enabled")

build_surfaces = [ROOT / "Makefile", ROOT / "build.sh", ROOT / "build-fast.sh"]
build_surfaces.extend(sorted((ROOT / ".github/workflows").glob("*.yml")))
for path in build_surfaces:
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    if re.search(r"iPhoneOS(?:16\.2|26\.2)\.sdk|iphone:clang:(?:16\.2|26\.2)", text):
        fail(f"old SDK reference in {path.relative_to(ROOT)}")
    if re.search(r"ipapatch|--dylib\s+\S*(?:pluginsinject|noplugin|sideloadpatch)", text, re.I):
        fail(f"separate sideload-helper injection remains in {path.relative_to(ROOT)}")

active_sources: list[Path] = []
for suffix in ("*.m", "*.mm", "*.x", "*.xm", "*.h"):
    active_sources.extend((ROOT / "src").rglob(suffix))

legacy_symbol = re.compile(r"\bSCI[A-Z][A-Za-z0-9_]*|\bsci[A-Z][A-Za-z0-9_]*")
for path in active_sources:
    text = path.read_text(encoding="utf-8", errors="replace")
    code = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    code = re.sub(r'@?"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', code)
    match = legacy_symbol.search(code)
    if match:
        fail(f"unmigrated code symbol {match.group(0)!r} in {path.relative_to(ROOT)}")
    if path.suffix in {".x", ".xm"}:
        if re.search(r"%orig\s*\(\s*\)", code):
            fail(f"no-argument %orig() must use bare %orig in {path.relative_to(ROOT)}")
        for line_number, line in enumerate(code.splitlines(), 1):
            tail = logos_orig_tail(line)
            if tail is not None:
                fail(f"tokens follow %orig on the same source line in {path.relative_to(ROOT)}:{line_number}: {tail.strip()!r}")

theos_root = os.environ.get("THEOS")
logos = Path(theos_root) / "bin/logos.pl" if theos_root else None
if logos and logos.is_file():
    for path in sorted(p for p in active_sources if p.suffix in {".x", ".xm"}):
        result = subprocess.run(["perl", str(logos), str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
        if result.returncode:
            detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown Logos error"
            fail(f"Logos preprocessing failed for {path.relative_to(ROOT)}: {detail}")

required = (
    ROOT / "src/Compatibility/RYGSideloadCompatibility.xm",
    ROOT / "src/UI/RYGLiquidGlass.m",
    ROOT / "src/Settings/RYGSetting.m",
    ROOT / "src/Debug/RYGRuntimeBrowserEngine.m",
    ROOT / "src/Debug/RYGRuntimeIndex.h",
    ROOT / "src/Debug/RYGRuntimeIndex.m",
    ROOT / "src/Debug/RYGFastRuntimeBrowserViewController.h",
    ROOT / "src/Debug/RYGFastRuntimeBrowserViewController.m",
    ROOT / "src/Debug/RYGDeveloperTopicViewController.m",
    ROOT / "src/Debug/RYGWordmarkViewController.m",
    ROOT / "src/Debug/RYGEasyGatingRuntime.m",
    ROOT / "src/Features/ExpFlags/RYGMobileConfigNameMappingStore.m",
    ROOT / "src/Features/ExpFlags/RYGFastMobileConfigBrowserViewController.m",
    ROOT / "src/Features/ExpFlags/RYGMobileConfigJSONSync.m",
)
for path in required:
    if not path.is_file():
        fail(f"required implementation missing: {path.relative_to(ROOT)}")

print("source validation OK: one Liquid Glass renderer, structural live Runtime Browser, declared runtime-owner contracts, sideload-safe final-ID EasyGating, one MobileConfig sync owner, Replace/Merge mapping, integrated sideload compatibility")
