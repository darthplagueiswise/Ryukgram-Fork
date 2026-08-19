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
    """Return the invalid tail after %orig, or None when the line is safe.

    Logos 777925d consumes the rest of a source line after forwarding the
    original call. Keeping the semicolon as the only token after %orig makes
    the generated Objective-C retain surrounding returns and closing braces.
    """
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

# These files previously layered alternate UI dispatchers / swizzles / C hooks
# over the same Developer and Runtime Browser responsibilities. Their presence
# makes behavior depend on constructor/link order, so the rebuilt architecture
# treats reintroduction as a source-validation failure.
for obsolete in (
    "src/Debug/RYGDeveloperFeatureViewController.m",
    "src/Debug/RYGDeveloperGateViewController.m",
    "src/Debug/RYGDeveloperExactSurfaceViewController.m",
    "src/Debug/RYGDeveloperRuntimeBrowserViewController.m",
    "src/Debug/RYGDeveloperEasyGatingControls.m",
    "src/Debug/RYGCFunctionOverrideEngine.m",
    "src/UI/RYGSettingsMenuGlassFix.m",
):
    if (ROOT / obsolete).exists():
        fail(f"obsolete competing runtime/UI implementation returned: {obsolete}")

# Binary-derived ABI invariants. These values are not arbitrary source style:
# they were revalidated against the supplied current arm64 Instagram / FBShared
# binaries and canonical MobileConfig files.
mc_header_path = ROOT / "src/Features/ExpFlags/RYGMobileConfig.h"
mc_impl_path = ROOT / "src/Features/ExpFlags/RYGMobileConfig.xm"
mc_json_path = ROOT / "src/Features/ExpFlags/RYGMobileConfigJSONIO.m"
easy_path = ROOT / "src/Debug/RYGEasyGatingRuntime.m"

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
    "_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb",
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb",
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb",
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb",
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb",
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb",
    'class_getInstanceVariable([manager class], "_configManager")',
):
    if marker not in mc_impl:
        fail(f"validated MobileConfig native ABI marker is missing: {marker}")
if re.search(r"RYGMCTypeBool\s*&&\s*type\s*<=\s*RYGMCTypeString", mc_impl):
    fail("ordinal MobileConfig type range check returned; string/double are not ordered as the old enum assumed")

mc_json = mc_json_path.read_text(encoding="utf-8")
for marker in ('@"_qe_overrides_"', '@": : "', "RYGMCParseCanonicalJSONValue"):
    if marker not in mc_json:
        fail(f"canonical MobileConfig JSON contract marker is missing: {marker}")

# The public EasyGating wrapper maps its selector/index before branching to the
# platform function. Hooking the wrapper would persist pre-map IDs and can force
# an unrelated gate. Only the final platform entry point is allowed here.
easy = easy_path.read_text(encoding="utf-8")
if 'dlsym(RTLD_DEFAULT, "EasyGatingPlatformGetBoolean")' not in easy:
    fail("Easy Gating must hook the validated final platform entry point")
if re.search(r'dlsym\s*\([^\n]*"EasyGatingGetBoolean_Internal_DoNotUseOrMock"', easy):
    fail("pre-map Easy Gating public wrapper must not be hooked")
if "ryg_easy_gating_platform_bool_overrides_v2" not in easy:
    fail("Easy Gating final-ID persistence namespace is missing")

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

active_sources = []
for suffix in ("*.m", "*.mm", "*.x", "*.xm", "*.h"):
    active_sources.extend((ROOT / "src").rglob(suffix))

legacy_symbol = re.compile(r"\bSCI[A-Z][A-Za-z0-9_]*|\bsci[A-Z][A-Za-z0-9_]*")
for path in active_sources:
    text = path.read_text(encoding="utf-8", errors="replace")
    code = re.sub(
        r"/\*.*?\*/|//[^\n]*",
        lambda match: "\n" * match.group(0).count("\n"),
        text,
        flags=re.S,
    )
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
                fail(
                    "tokens follow %orig on the same source line in "
                    f"{path.relative_to(ROOT)}:{line_number}: {tail.strip()!r}"
                )

theos_root = os.environ.get("THEOS")
logos = Path(theos_root) / "bin/logos.pl" if theos_root else None
if logos and logos.is_file():
    for path in sorted(p for p in active_sources if p.suffix in {".x", ".xm"}):
        result = subprocess.run(
            ["perl", str(logos), str(path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode:
            detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown Logos error"
            fail(f"Logos preprocessing failed for {path.relative_to(ROOT)}: {detail}")

required = (
    ROOT / "src/Compatibility/RYGSideloadCompatibility.xm",
    ROOT / "src/UI/RYGLiquidGlass.m",
    ROOT / "src/Debug/RYGRuntimeBrowserEngine.m",
    ROOT / "src/Debug/RYGRuntimeBrowserViewController.m",
    ROOT / "src/Debug/RYGDeveloperRuntimeScanner.m",
    ROOT / "src/Debug/RYGDeveloperTopicViewController.m",
    ROOT / "src/Debug/RYGWordmarkViewController.m",
    ROOT / "src/Debug/RYGEasyGatingRuntime.m",
    ROOT / "src/Features/ExpFlags/RYGMobileConfigNameMappingStore.m",
    ROOT / "src/Features/ExpFlags/RYGMobileConfigNativeBrowser.m",
)
for path in required:
    if not path.is_file():
        fail(f"required implementation missing: {path.relative_to(ROOT)}")

print("source validation OK: SDK 26.5, validated Easy Gating platform ABI, native MobileConfig 1/2/3/4 types, canonical JSON, direct BOOL Runtime Browser, integrated sideload compatibility")
