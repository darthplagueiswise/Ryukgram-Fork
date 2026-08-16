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
    original call.  Keeping the semicolon as the only token after %orig makes
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
    # Legacy product names remain intentionally in migration string values,
    # comments and attribution URLs. Validate executable identifiers only.
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
)
for path in required:
    if not path.is_file():
        fail(f"required implementation missing: {path.relative_to(ROOT)}")

print("source validation OK: SDK 26.5, integrated sideload compatibility, RYG namespace, no preloaded MobileConfig table")
