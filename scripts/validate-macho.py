#!/usr/bin/env python3
"""Validate and inspect a built RyukGram Mach-O using LIEF + Capstone."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import capstone
import lief


FORBIDDEN = (
    b"zxPluginsInject.dylib",
    b"pluginsinject.dylib",
    b"NoPluginsPatch.dylib",
    b"SideloadPatch.dylib",
)
REQUIRED = (
    b"RyukGramSideloadCompatibility",
    b"containerURLForSecurityApplicationGroupIdentifier:",
    b"UIGlassEffect",
    # Runtime Browser v2 is image-scoped and class-first. Validate the actual
    # runtime API and live-observation UI contract instead of the deleted
    # RYGRuntimeBrowserLiveScan accessibility marker from the old flat browser.
    b"objc_copyClassNamesForImage",
    b"Class Properties",
    b"Observe Original Value",
)


def die(message: str) -> None:
    print(f"Mach-O validation error: {message}", file=sys.stderr)
    raise SystemExit(1)


def choose_binary(parsed: object):
    if parsed is None:
        return None
    if isinstance(parsed, lief.MachO.Binary):
        return parsed
    try:
        candidates = list(parsed)
    except TypeError:
        return None
    for candidate in candidates:
        cpu = str(candidate.header.cpu_type).upper()
        if "ARM64" in cpu:
            return candidate
    return candidates[0] if candidates else None


def library_names(binary) -> list[str]:
    names: list[str] = []
    for library in getattr(binary, "libraries", []):
        names.append(str(getattr(library, "name", library)))
    return names


def disassemble_text(binary) -> tuple[int, list[str]]:
    section = binary.get_section("__text")
    if section is None:
        return 0, []
    content = bytes(section.content[:128])
    if not content:
        return 0, []
    address = int(getattr(section, "virtual_address", 0))
    engine = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)
    instructions = []
    for insn in engine.disasm(content, address):
        instructions.append(f"0x{insn.address:x}: {insn.mnemonic} {insn.op_str}".rstrip())
        if len(instructions) >= 8:
            break
    return len(content), instructions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("macho", type=Path)
    args = parser.parse_args()
    path = args.macho.resolve()
    if not path.is_file():
        die(f"file not found: {path}")

    raw = path.read_bytes()
    for marker in FORBIDDEN:
        if marker.lower() in raw.lower():
            die(f"external helper marker remains: {marker.decode(errors='replace')}")
    missing = [marker.decode(errors="replace") for marker in REQUIRED if marker not in raw]
    if missing:
        die("required integrated marker(s) missing: " + ", ".join(missing))

    try:
        parsed = lief.MachO.parse(str(path))
    except Exception as exc:  # pragma: no cover - diagnostic path on CI
        die(f"LIEF could not parse {path.name}: {exc}")
    binary = choose_binary(parsed)
    if binary is None:
        die("LIEF returned no Mach-O slice")

    cpu = str(binary.header.cpu_type)
    if "ARM64" not in cpu.upper():
        die(f"unexpected CPU type: {cpu}")
    file_type = str(binary.header.file_type)
    if "DYLIB" not in file_type.upper():
        die(f"expected a dylib, got {file_type}")

    libraries = library_names(binary)
    forbidden_dependencies = [
        name for name in libraries
        if any(token.decode().lower() in name.lower() for token in FORBIDDEN)
    ]
    if forbidden_dependencies:
        die("forbidden dependency: " + ", ".join(forbidden_dependencies))

    byte_count, instructions = disassemble_text(binary)
    if byte_count and not instructions:
        die("Capstone could not decode the arm64 __text section")

    print(f"LIEF: {path.name} · {cpu} · {file_type} · {len(libraries)} dylib dependencies")
    print("Dependencies:")
    for name in libraries:
        print(f"  {name}")
    print(f"Capstone: decoded {len(instructions)} instruction(s) from {byte_count} __text bytes")
    for line in instructions:
        print(f"  {line}")
    print("Integrated markers: sideload compatibility, App Group hook, UIGlassEffect, image-scoped Runtime Browser, live observation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
