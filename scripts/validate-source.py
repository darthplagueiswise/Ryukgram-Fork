#!/usr/bin/env python3
"""Structural source contract for the dogfood architecture."""

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


def read(path: str) -> str:
    file = ROOT / path
    if not file.is_file():
        fail(f"required implementation missing: {path}")
    return file.read_text(encoding="utf-8", errors="replace")


def logos_orig_tail(line: str) -> str | None:
    for match in re.finditer(r"%orig\b", line):
        cursor = match.end()
        while cursor < len(line) and line[cursor].isspace():
            cursor += 1
        if cursor < len(line) and line[cursor] == "(":
            depth = 0
            while cursor < len(line):
                if line[cursor] == "(":
                    depth += 1
                elif line[cursor] == ")":
                    depth -= 1
                    if depth == 0:
                        cursor += 1
                        break
                cursor += 1
        tail = line[cursor:]
        if not re.fullmatch(r"\s*;\s*", tail):
            return tail
    return None


makefile = read("Makefile")
if "TARGET := iphone:clang:26.5:15.0" not in makefile:
    fail("Makefile must use SDK 26.5 and the iOS 15 deployment target")
if "-include src/RYGPrefix.h" not in makefile:
    fail("RYGPrefix.h must remain the forced prefix header")
if "src/Compatibility" not in makefile:
    fail("integrated sideload compatibility contract is missing")

if (ROOT / "src/BundleAssets/ryg_mc_names.bin").exists():
    fail("preloaded MobileConfig name catalog must not ship")

# These files were the stacked bootstrap/restore architecture responsible for
# doing the same work from lifecycle, dyld callbacks and UI paths. Their return
# is a regression, not an alternative implementation.
for obsolete in (
    "src/Debug/RYGDeveloperBootstrapOwner.m",
    "src/Debug/RYGDeveloperPersistenceBootstrap.m",
    "src/Debug/RYGDeveloperSurfaceFastPath.m",
    "src/Debug/RYGRuntimeFastPath.m",
    "src/Debug/RYGRuntimeOverrideOwner.m",
    "src/Debug/RYGRuntimeIndex.h",
    "src/Debug/RYGRuntimeIndex.m",
    "src/Debug/RYGDeveloperFeatureViewController.m",
    "src/Debug/RYGDeveloperGateViewController.m",
    "src/Debug/RYGDeveloperRuntimeScanner.m",
):
    if (ROOT / obsolete).exists():
        fail(f"obsolete competing runtime/bootstrap implementation returned: {obsolete}")

manager = read("src/Debug/RYGRuntimeHookManager.m")
manager_h = read("src/Debug/RYGRuntimeHookManager.h")
for marker in (
    "ryg_runtime_bool_hook_specs_v6",
    "ryg_runtime_legacy_quarantine_v6",
    "kRYGRuntimeMigrationLimit = 256",
    "RYGHookDirectMethod",
    "class_copyMethodList",
    "RYGHookInstallExact",
    "UIApplicationDidFinishLaunchingNotification",
    "RYGRuntimeHookManagerBootstrap",
    "method_exchangeImplementations",
):
    if marker not in manager:
        fail(f"single runtime hook owner contract marker missing: {marker}")
if "_dyld_register_func_for_add_image" in manager:
    fail("runtime override restore must not register dyld add-image callbacks")
if "objc_getClassList" in manager or "objc_copyClassNamesForImage" in manager:
    fail("runtime hook manager must replay exact specs, never discover classes")
if "RYGRuntimeHookManager" not in manager_h:
    fail("runtime hook manager public contract is missing")

browser = read("src/Debug/RYGFastRuntimeBrowserViewController.m")
for marker in (
    "objc_copyClassNamesForImage",
    "membersForClassName",
    "machOSymbolsForImagePath",
    "selector scan is on-demand",
    "methods are not indexed until needed",
    'initWithItems:@[@"Objective-C", @"C Symbols"]',
    "Force On",
    "Force Off",
    "Use Native",
):
    if marker not in browser:
        fail(f"on-demand Runtime Browser marker missing: {marker}")
for forbidden in ("RYGRuntimeIndex", "requestIndexForImagePath", "objc_getClassList", "_dyld_register_func_for_add_image"):
    if forbidden in browser:
        fail(f"Runtime Browser reintroduced eager/global discovery: {forbidden}")
if re.search(r"imageButton\.(?:leading|trailing)Anchor[^\n]*constant:", browser):
    fail("Runtime Browser image selector must use adaptive layout margins")

engine = read("src/Debug/RYGRuntimeBrowserEngine.m")
for marker in (
    "runtimeImagePaths",
    "membersForClassName",
    "method_getReturnType",
    "method_getArgumentType",
    "machOSymbolsForImagePath",
    "rebind_symbols_image",
):
    if marker not in engine:
        fail(f"Runtime Browser engine contract marker missing: {marker}")
if "__attribute__((constructor))" in engine or "_dyld_register_func_for_add_image" in engine:
    fail("Runtime Browser engine itself must stay presentation/discovery-only")

hub = read("src/Debug/RYGDeveloperHubViewController.m")
if "activatePersistedNativeFeatures" in hub:
    fail("opening Developer Hub must not trigger persisted restore")
if "Startup only replays exact persisted identities" not in hub:
    fail("Developer Hub must document the exact-replay/on-demand model")

topic = read("src/Debug/RYGDeveloperTopicViewController.m")
for marker in (
    "_TtC17IGBugReporterMenu29IGBugReportMenuViewController",
    "showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:",
    "_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController",
    "_TtC35IGDogfoodingAssistantLauncherClient35IGDogfoodingAssistantLauncherClient",
    "_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs",
    "_TtC18IGNavConfiguration25IGHomecomingConfiguration",
    "isDynamicTabStoryGridEnabled",
    "_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle",
    "_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper",
    "_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper",
    "RYGDeveloperStateBootstrap",
    "No MobileConfig prepare/reload/reapply occurs here",
):
    if marker not in topic:
        fail(f"Developer exact-owner/persistence marker missing: {marker}")
for forbidden in ("_dyld_register_func_for_add_image", "objc_getClassList", "RYGFindExactBoolSelector", "RYGRuntimeIndex"):
    if forbidden in topic:
        fail(f"Developer Topic reintroduced global/eager discovery: {forbidden}")
activation = re.search(r"\+ \(void\)activatePersistedNativeFeatures\s*\{(?P<body>.*?)\n\}\n\n- \(instancetype\)initWithSurface", topic, re.S)
if not activation:
    fail("could not validate activatePersistedNativeFeatures body")
for forbidden in (" prepare]", "reloadFromRuntime", "reapplyOverridesToNativeTable"):
    if forbidden in activation.group("body"):
        fail(f"startup native restore must not enumerate/reapply MobileConfig: {forbidden}")

mc_header = read("src/Features/ExpFlags/RYGMobileConfig.h")
for type_name, discriminator in (("RYGMCTypeBool", 1), ("RYGMCTypeInt", 2), ("RYGMCTypeString", 3), ("RYGMCTypeDouble", 4)):
    if not re.search(rf"\b{type_name}\s*=\s*{discriminator}\b", mc_header):
        fail(f"MobileConfig discriminator drifted: {type_name} must equal {discriminator}")

mc_impl = read("src/Features/ExpFlags/RYGMobileConfig.xm")
for marker in (
    "_ZN12mobileconfig17typeFromParameterEy",
    "_ZN12mobileconfig23kMobileConfigParamsListE",
    "_ZN12mobileconfig23kMobileConfigParamsSizeE",
    '@"setOverrideForParam:andValue:"',
    '@"removeOverrideForParam:"',
):
    if marker not in mc_impl:
        fail(f"validated MobileConfig runtime marker missing: {marker}")
if "dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC))" in mc_impl:
    fail("MobileConfig must not auto-reapply from an 8-second startup timer")

mc_bridge = read("src/Features/ExpFlags/RYGMobileConfigBridge.m")
for forbidden in ("RYGBridgeDataDirectoryScore", "containerURLForSecurityApplicationGroupIdentifier"):
    if forbidden in mc_bridge:
        fail(f"guessed MobileConfig container fallback returned: {forbidden}")
if 'hasSuffix:@".data"' not in mc_bridge:
    fail("native MobileConfig data-file contract is missing")

mc_json = read("src/Features/ExpFlags/RYGMobileConfigJSONIO.m")
for marker in ('@"_qe_overrides_"', '@": : "', "RYGMCParseCanonicalJSONValue"):
    if marker not in mc_json:
        fail(f"canonical mc_overrides JSON marker missing: {marker}")

easy = read("src/Debug/RYGEasyGatingRuntime.m")
for marker in (
    'name = "EasyGatingGetBoolean_Internal_DoNotUseOrMock"',
    "rebind_symbols_image",
    "RYGResolveFinalGateID",
    "RYGEasyGatingImageRangeHasProtection",
    "ryg_easy_gating_platform_bool_overrides_v2",
):
    if marker not in easy:
        fail(f"sideload-safe EasyGating marker missing: {marker}")
if re.search(r'dlsym\s*\([^\n]*"EasyGatingPlatformGetBoolean"', easy):
    fail("EasyGating must not patch signed FBShared __TEXT")

liquid = read("src/UI/RYGLiquidGlass.m")
if 'return ![RYGUtils getBoolPref:@"liquid_glass_force_off"]' not in liquid:
    fail("Liquid Glass availability/accessibility contract changed")
if "return !UIAccessibilityIsReduceTransparencyEnabled()" in liquid:
    fail("Liquid Glass must let UIKit adapt Reduce Transparency")

for legacy_module in (ROOT / "modules/zxPluginsInject", ROOT / "modules/SideloadPatch"):
    if legacy_module.exists() and any(legacy_module.iterdir()):
        fail(f"separate sideload helper returned: {legacy_module.relative_to(ROOT)}")

build_surfaces = [ROOT / "Makefile", ROOT / "build.sh", ROOT / "build-fast.sh"]
build_surfaces.extend(sorted((ROOT / ".github/workflows").glob("*.yml")))
for path in build_surfaces:
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if re.search(r"iPhoneOS(?:16\.2|26\.2)\.sdk|iphone:clang:(?:16\.2|26\.2)", text):
        fail(f"old SDK reference in {path.relative_to(ROOT)}")
    if re.search(r"ipapatch|--dylib\s+\S*(?:pluginsinject|noplugin|sideloadpatch)", text, re.I):
        fail(f"separate helper injection remains in {path.relative_to(ROOT)}")

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
        fail(f"unmigrated legacy symbol {match.group(0)!r} in {path.relative_to(ROOT)}")
    if path.suffix in {".x", ".xm"}:
        if re.search(r"%orig\s*\(\s*\)", code):
            fail(f"no-argument %orig() must use bare %orig in {path.relative_to(ROOT)}")
        for line_number, line in enumerate(code.splitlines(), 1):
            tail = logos_orig_tail(line)
            if tail is not None:
                fail(f"tokens follow %orig on the same source line in {path.relative_to(ROOT)}:{line_number}: {tail.strip()!r}")

logos = Path(os.environ.get("THEOS", "")) / "bin/logos.pl" if os.environ.get("THEOS") else None
if logos and logos.is_file():
    for path in sorted(p for p in active_sources if p.suffix in {".x", ".xm"}):
        result = subprocess.run(["perl", str(logos), str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
        if result.returncode:
            detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown Logos error"
            fail(f"Logos preprocessing failed for {path.relative_to(ROOT)}: {detail}")

print("source validation OK: single exact runtime owner, on-demand browser, bounded migration, no dyld restore loops, explicit MobileConfig work, SDK 26.5")
