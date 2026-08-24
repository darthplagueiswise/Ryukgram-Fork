#!/usr/bin/env python3
"""Fail fast on RyukGram dogfood architecture/performance regressions before Theos."""

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


def require(text: str, markers: tuple[str, ...], owner: str) -> None:
    for marker in markers:
        if marker not in text:
            fail(f"{owner} contract marker missing: {marker}")


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
require(makefile, ("TARGET := iphone:clang:26.5:15.0", "-include src/RYGPrefix.h", "src/Compatibility"), "build")
if (ROOT / "src/BundleAssets/ryg_mc_names.bin").exists():
    fail("preloaded MobileConfig name catalog must not ship")
for legacy_module in (ROOT / "modules/zxPluginsInject", ROOT / "modules/SideloadPatch"):
    if legacy_module.exists() and any(legacy_module.iterdir()):
        fail(f"separate sideload helper returned: {legacy_module.relative_to(ROOT)}")

# Developer catalogue: the dyld callback may only invalidate generations. No
# process/image/class walk is allowed during cold start. Known owners prewarm
# only after the Developer hub is explicitly opened; broad discovery is scoped
# to the selected domain and image list.
dev_catalog_h = read("src/Debug/RYGDeveloperFeatureCatalog.h")
dev_catalog = read("src/Debug/RYGDeveloperFeatureCatalog.m")
dev_registry = read("src/Debug/RYGDeveloperHookRegistry.m")
dev_hub = read("src/Debug/RYGDeveloperHubViewController.m")
require(dev_catalog_h, ("prewarmKnownOwners", "discoverAdditionalClasses"), "Developer catalogue header")
require(dev_catalog, (
    "_dyld_register_func_for_add_image",
    "objc_copyClassNamesForImage",
    "RYGKnownOwners",
    "RYGStructuralNoise",
    "RYGDeveloperRuntimeSurfaceConsumerSubs",
), "Developer live catalogue")
start_body = re.search(r"- \(void\)startIfNeeded\s*\{(?P<body>.*?)\n\}", dev_catalog, re.S)
if not start_body:
    fail("could not inspect Developer catalogue bootstrap")
for forbidden in ("objc_getClassList", "objc_copyClassNamesForImage", "class_copyMethodList", "requestRefreshForSurface"):
    if forbidden in start_body.group("body"):
        fail(f"Developer catalogue cold-start bootstrap performs discovery: {forbidden}")
if "objc_getClassList" in dev_catalog:
    fail("Developer catalogue must use image-scoped class enumeration, not process-global objc_getClassList")

require(dev_registry, (
    "LC_UUID",
    "method_getTypeEncoding",
    "RYGDirectMethod",
    "RYGMethodForPersistedIdentity",
    "imp_implementationWithBlock",
    "restorePersistedOverridesForLoadedImages",
    "ryg_developer_bool_overrides_v2",
), "Developer hook registry")
if "RYGRuntimeBrowserEngine setOverride" in dev_registry:
    fail("Developer hook registry must be independent from Runtime Browser override state")
if "objc_getClassList" in dev_registry or "objc_copyClassNamesForImage" in dev_registry:
    fail("Developer persisted replay must resolve only exact persisted identities")
for obsolete in ("src/Debug/RYGDeveloperSetterOwner.m", "src/Debug/RYGDeveloperVerifiedApply.m"):
    if (ROOT / obsolete).exists():
        fail(f"competing Developer hook owner returned: {obsolete}")
require(dev_hub, (
    "prewarmKnownOwners",
    "Aura / IGPlus",
    "Runtime Browser · ObjC",
    "Runtime Browser · C Functions",
), "Developer hub")

# Objective-C Runtime Browser remains on-demand. Persistent identity replay lives
# in the hook manager; discovery UI must never become a launch dependency.
manager_h = read("src/Debug/RYGRuntimeHookManager.h")
manager = read("src/Debug/RYGRuntimeHookManager.m")
browser = read("src/Debug/RYGFastRuntimeBrowserViewController.m")
engine = read("src/Debug/RYGRuntimeBrowserEngine.m")
require(manager_h, ("RYGRuntimeHookManager", "setSessionOverride"), "runtime hook manager header")
require(manager, ("RYGRuntimeHotState", "forcedSet", "forcedValue", "nativeValue", "RYGHookDirectMethod", "RYGHookInstallExact"), "runtime hook manager")
if "objc_getClassList" in manager or "objc_copyClassNamesForImage" in manager:
    fail("runtime persistence owner must replay exact identities, never discover classes")
require(browser, ("objc_copyClassNamesForImage", "membersForClassName", "Force On", "Force Off", "Use Native"), "Runtime Browser")
if "objc_getClassList" in browser or "_dyld_register_func_for_add_image" in browser:
    fail("Runtime Browser UI reintroduced process-global/startup discovery")
if "__attribute__((constructor))" in engine or "_dyld_register_func_for_add_image" in engine:
    fail("Runtime Browser engine must remain discovery/presentation-only")

# C Functions: only imported symbols in the selected image are candidates.
# Force 0/1 is allowed only when every resolved direct BL call site consumes
# w0/x0 as a predicate; unproven symbols remain inspect-only.
c_resolver = read("src/Debug/RYGCFunctionResolver.m")
c_ui = read("src/Debug/RYGCFunctionsViewController.m")
require(c_resolver, (
    "S_SYMBOL_STUBS",
    "LC_UUID",
    "directCallSiteCount",
    "predicateHookable",
    "RYGCCallConsumesPredicate",
    "rebind_symbols_image",
    "Inspect only",
), "C Function resolver")
require(c_ui, ("C Functions", "Force On", "Force Off", "ABI-verified predicate hooks"), "C Function UI")
if "MSHookFunction" in c_resolver:
    fail("C Function browser must not inline-patch signed __TEXT")

# MobileConfig semantic authority comes from the active session. No App Group
# UUID, user id, unit mirror or getter observation may be used as the semantic
# prerequisite for a configId:paramId imported from id_name_mapping.json.
mc_header = read("src/Features/ExpFlags/RYGMobileConfig.h")
for type_name, discriminator in (("RYGMCTypeBool",1),("RYGMCTypeInt",2),("RYGMCTypeString",3),("RYGMCTypeDouble",4)):
    if not re.search(rf"\b{type_name}\s*=\s*{discriminator}\b", mc_header):
        fail(f"MobileConfig discriminator drifted: {type_name} must equal {discriminator}")
mc = read("src/Features/ExpFlags/RYGMobileConfig.xm")
require(mc, ("_ZN12mobileconfig17typeFromParameterEy", "_ZN12mobileconfig23kMobileConfigParamsListE", "setOverrideForParam:andValue:", "removeOverrideForParam:"), "MobileConfig descriptor core")

mc_authority = read("src/Features/ExpFlags/RYGMobileConfigNativeAuthority.m")
require(mc_authority, (
    "FBMobileConfigFBTGlobalSessionManager",
    "currentSessionContextManagerHolder",
    "getOverridesTablePath",
    "getUnitType",
    "getStableIdFromParamSpecifier:",
    "RYGMCResolveExactPID",
    "id_name_mapping.json",
    "ryg_authorityLoadNameCatalog",
    "ryg_authorityWriteNativeForPid",
), "MobileConfig active-session authority")
for forbidden in ("containerURLForSecurityApplicationGroupIdentifier", "RYGMCForceCanonicalPID", "RYGMirrorPID"):
    if forbidden in mc_authority:
        fail(f"MobileConfig semantic authority contains guessed/mirrored path or PID logic: {forbidden}")
if "getBool:" in mc_authority:
    fail("MobileConfig semantic authority must never own a hot getter")
if (ROOT / "src/Features/ExpFlags/RYGMobileConfigUnitCompat.m").exists():
    fail("synthetic MobileConfig unit mirror owner returned")

mc_semantic = read("src/Features/ExpFlags/RYGMobileConfigSemanticResolver.m")
require(mc_semantic, (
    "configNumber",
    "paramIndex",
    "reloadFromRuntime",
    "setOverride:for:",
    "clearOverrideFor:",
    "canonical mc_overrides.json",
), "MobileConfig semantic resolver")
for forbidden in ("gRealPid", "gCallSites", "callSiteFor:", "getBool:", "0x40", "0x80"):
    if forbidden in mc_semantic:
        fail(f"MobileConfig semantic resolver depends on observation/mirrored PID state: {forbidden}")

mc_owner = read("src/Features/ExpFlags/RYGMobileConfigHookOwner.m")
require(mc_owner, (
    "RYG_MC_HOT_CAPACITY",
    "gRYGMCHotSlots",
    "RYGMCHotFindSlot",
    "RYGMCOwnedOverride",
    "atomic_load_explicit",
    "gRYGMCHooksInstalled",
), "MobileConfig hot-path owner")
match = re.search(r"static id RYGMCOwnedOverride\([^)]*\)\s*\{(?P<body>.*?)\n\}", mc_owner, re.S)
if not match:
    fail("could not inspect MobileConfig hot getter lookup")
for forbidden in ("NSDictionary", "NSMutableDictionary", "os_unfair_lock", "RYGMobileConfig.shared", "NSUserDefaults", "backtrace", "dladdr", "reapplyOverridesToNativeTable"):
    if forbidden in match.group("body"):
        fail(f"MobileConfig getter hot path performs expensive work: {forbidden}")

mc_json = read("src/Features/ExpFlags/RYGMobileConfigJSONIO.m")
require(mc_json, ('@"_qe_overrides_"', '@": : "', "RYGMCParseCanonicalJSONValue"), "canonical MobileConfig JSON")

# EasyGating remains import-rebinding only: no signed __TEXT inline patch.
easy = read("src/Debug/RYGEasyGatingRuntime.m")
require(easy, ('name = "EasyGatingGetBoolean_Internal_DoNotUseOrMock"', "rebind_symbols_image", "RYGResolveFinalGateID", "RYGEasyGatingImageRangeHasProtection", "ryg_easy_gating_platform_bool_overrides_v2"), "EasyGating")
if re.search(r'dlsym\s*\([^\n]*"EasyGatingPlatformGetBoolean"', easy):
    fail("EasyGating must not patch the signed FBShared platform function")

liquid = read("src/UI/RYGLiquidGlass.m")
if 'return ![RYGUtils getBoolPref:@"liquid_glass_force_off"]' not in liquid:
    fail("Liquid Glass availability/accessibility contract changed")
if "return !UIAccessibilityIsReduceTransparencyEnabled()" in liquid:
    fail("Liquid Glass must let UIKit adapt Reduce Transparency")

# Build surfaces may not drift back to older SDKs or separate helper injection.
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

# Generic source/Logos sanity.
active_sources: list[Path] = []
for suffix in ("*.m","*.mm","*.x","*.xm","*.h"):
    active_sources.extend((ROOT / "src").rglob(suffix))
legacy_symbol = re.compile(r"\bSCI[A-Z][A-Za-z0-9_]*|\bsci[A-Z][A-Za-z0-9_]*")
for path in active_sources:
    text = path.read_text(encoding="utf-8", errors="replace")
    code = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    code = re.sub(r'@?"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', code)
    bad = legacy_symbol.search(code)
    if bad:
        fail(f"unmigrated legacy symbol {bad.group(0)!r} in {path.relative_to(ROOT)}")
    if path.suffix in {".x", ".xm"}:
        if re.search(r"%orig\s*\(\s*\)", code):
            fail(f"no-argument %orig() in {path.relative_to(ROOT)}")
        for line_number, line in enumerate(code.splitlines(), 1):
            tail = logos_orig_tail(line)
            if tail is not None:
                fail(f"tokens follow %orig in {path.relative_to(ROOT)}:{line_number}: {tail.strip()!r}")

logos = Path(os.environ.get("THEOS", "")) / "bin/logos.pl" if os.environ.get("THEOS") else None
if logos and logos.is_file():
    for path in sorted(p for p in active_sources if p.suffix in {".x", ".xm"}):
        result = subprocess.run(["perl", str(logos), str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
        if result.returncode:
            detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown Logos error"
            fail(f"Logos preprocessing failed for {path.relative_to(ROOT)}: {detail}")

print("source validation OK: SDK 26.5, lazy Developer catalogue, single typed Developer owner, semantic MobileConfig apply without observation dependency, ABI-gated C imports, on-demand Runtime Browser, integrated sideload compatibility")
