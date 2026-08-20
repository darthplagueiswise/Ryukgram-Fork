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
                if char == "(": depth += 1
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

for obsolete in (
    "src/Debug/RYGDeveloperFeatureViewController.m",
    "src/Debug/RYGDeveloperGateViewController.m",
    "src/Debug/RYGDeveloperExactSurfaceViewController.m",
    "src/Debug/RYGDeveloperRuntimeBrowserViewController.m",
    "src/Debug/RYGDeveloperEasyGatingControls.m",
    "src/Debug/RYGCFunctionOverrideEngine.m",
    "src/Debug/RYGDeveloperRuntimeScanner.m",
    "src/Debug/RYGRuntimeClassBrowser.m",
    "src/Debug/RYGRuntimeClassBrowser.h",
    "src/UI/RYGSettingsMenuGlassFix.m",
    "src/Settings/RYGSettingsMenuLiquidGlass.m",
    "src/Features/ExpFlags/RYGMobileConfigExternalSeenTracker.m",
    "src/Features/ExpFlags/RYGMobileConfigParamTableCompatibility.m",
):
    if (ROOT / obsolete).exists():
        fail(f"obsolete competing implementation returned: {obsolete}")

mc_header_path = ROOT / "src/Features/ExpFlags/RYGMobileConfig.h"
mc_impl_path = ROOT / "src/Features/ExpFlags/RYGMobileConfig.xm"
mc_json_path = ROOT / "src/Features/ExpFlags/RYGMobileConfigJSONIO.m"
easy_path = ROOT / "src/Debug/RYGEasyGatingRuntime.m"
runtime_engine_path = ROOT / "src/Debug/RYGRuntimeBrowserEngine.m"
runtime_view_path = ROOT / "src/Debug/RYGRuntimeBrowserViewController.m"
topic_path = ROOT / "src/Debug/RYGDeveloperTopicViewController.m"
setting_path = ROOT / "src/Settings/RYGSetting.m"

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
if 'dlsym(RTLD_DEFAULT, "EasyGatingPlatformGetBoolean")' not in easy:
    fail("Easy Gating must hook the validated final platform entry point")
if re.search(r'dlsym\s*\([^\n]*"EasyGatingGetBoolean_Internal_DoNotUseOrMock"', easy):
    fail("pre-map Easy Gating public wrapper must not be hooked")
if "ryg_easy_gating_platform_bool_overrides_v2" not in easy:
    fail("Easy Gating final-ID persistence namespace is missing")

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

runtime_view = runtime_view_path.read_text(encoding="utf-8")
for marker in (
    "boolMethodsForImagePath",
    "Observe visible original values",
    "outputButtonForMethod",
    "original not observed",
    "Force On",
    "Force Off",
    "Use native value",
):
    if marker not in runtime_view:
        fail(f"direct live BOOL Runtime Browser marker is missing: {marker}")
for forbidden in (
    "RYGRuntimeClassBrowser",
    "RYGRuntimeClassDetailViewController",
    "RYGRuntimeTopModeMachO",
    'initWithItems:@[@"Classes", @"Mach-O"]',
):
    if forbidden in runtime_view:
        fail(f"obsolete class/Mach-O Runtime Browser layer returned: {forbidden}")

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

setting = setting_path.read_text(encoding="utf-8")
for marker in ("UIAction.class", "UICommand.class", "RYGLiquidGlassConfigureButton", "setDefaultContentInsets"):
    if marker not in setting:
        fail(f"settings menu Liquid Glass/state marker is missing: {marker}")

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
    ROOT / "src/Debug/RYGRuntimeBrowserViewController.m",
    ROOT / "src/Debug/RYGDeveloperTopicViewController.m",
    ROOT / "src/Debug/RYGWordmarkViewController.m",
    ROOT / "src/Debug/RYGEasyGatingRuntime.m",
    ROOT / "src/Features/ExpFlags/RYGMobileConfigNameMappingStore.m",
    ROOT / "src/Features/ExpFlags/RYGMobileConfigNativeBrowser.m",
)
for path in required:
    if not path.is_file():
        fail(f"required implementation missing: {path.relative_to(ROOT)}")

print("source validation OK: one Liquid Glass menu renderer, direct live BOOL Runtime Browser, exact Developer owners, final-ID EasyGating, current native MobileConfig StartupConfigs API, Replace/Merge mapping, integrated sideload compatibility")
