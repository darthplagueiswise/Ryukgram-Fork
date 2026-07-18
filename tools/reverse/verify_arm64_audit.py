#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import pathlib
import re
import subprocess
import sys
from typing import Dict, List, Tuple

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

Instruction = Tuple[int, str, str]

# Assertions are tied to the SHA-scoped slices in arm64-audit-fixtures.json.
# They cover the concrete facts used by the runtime implementation rather than
# trusting symbols, class names or offsets from a different Instagram build.
EXPECTED: Dict[Tuple[str, str], List[Instruction]] = {
    ("Instagram", "startup_mc_call"): [
        (0x102C56044, "add", "x3, sp, #8"),
        (0x102C5604C, "bl", "#0x109e5308c"),
    ],
    ("Instagram", "action_button_delegate"): [
        (0x1084C3AA8, "mov", "x20, x2"),
        (0x1084C3AB0, "mov", "x0, x2"),
    ],
    ("Instagram", "link_button_delegate"): [
        (0x1085154B0, "mov", "x20, x2"),
        (0x1085154B8, "mov", "x0, x2"),
    ],
    ("Instagram", "action_cell_setEnabled"): [
        (0x10970F818, "mov", "x19, x2"),
        (0x10970F840, "mov", "x2, x19"),
    ],
    ("Instagram", "link_cell_setEnabled"): [
        (0x10970F86C, "mov", "x19, x2"),
        (0x10970F894, "mov", "x2, x19"),
    ],
    ("Instagram", "loggedout_action_builder"): [
        (0x104AAF748, "adrp", "x3, #0x105824000"),
        (0x104AAF74C, "add", "x3, x3, #0x584"),
    ],
    ("Instagram", "loggedout_force_fetch_closure"): [
        (0x105824584, "mov", "x0, x30"),
    ],
    ("FBSharedFramework", "try_update_wrapper"): [
        (0x72DA74, "mov", "w4, #0"),
        (0x72DA78, "b", "#0x72fee4"),
    ],
    ("FBSharedFramework", "try_update_private"): [
        (0x72FEF8, "mov", "x19, x4"),
    ],
}


def normalized_mnemonic(text: str) -> str:
    return text.strip().lower()


def normalized_operands(text: str) -> str:
    # Capstone prints immediates with '#'; radare2 may omit it. Spacing around
    # commas also differs. Those are presentation differences, not opcode facts.
    value = text.strip().lower().replace("#", "")
    value = re.sub(r"\s+", "", value)
    value = re.sub(r"\b0x0\b", "0", value)
    return value


def instruction_matches(actual: Tuple[str, str],
                        mnemonic: str,
                        operands: str) -> bool:
    return (
        normalized_mnemonic(actual[0]) == normalized_mnemonic(mnemonic)
        and normalized_operands(actual[1]) == normalized_operands(operands)
    )


def split_opcode(opcode: str) -> Tuple[str, str]:
    fields = opcode.strip().split(None, 1)
    if not fields:
        return "", ""
    return fields[0], fields[1] if len(fields) == 2 else ""


def run_r2(path: pathlib.Path, va: int,
           instruction_count: int) -> Tuple[List[Instruction], str]:
    # JSON output avoids false failures caused by radare2's column layout and
    # allows comparison by exact address, mnemonic and normalized operands.
    command = [
        "r2", "-q", "-n", "-a", "arm", "-b", "64", "-m", hex(va),
        "-c", f"e asm.bytes=false; e asm.lines=false; pdj {instruction_count}; q",
        str(path),
    ]
    completed = subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stdout = completed.stdout.strip()
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"radare2 returned non-JSON output for {path}: {stdout[:500]}"
        ) from error

    rows: List[Instruction] = []
    for item in payload:
        if "offset" not in item:
            continue
        opcode = item.get("opcode") or item.get("disasm") or ""
        mnemonic, operands = split_opcode(opcode)
        rows.append((int(item["offset"]), mnemonic, operands))
    diagnostic = completed.stderr.strip()
    return rows, diagnostic


def format_rows(rows: List[Instruction], limit: int = 32) -> List[str]:
    return [
        f"{address:#x}: {mnemonic} {operands}".rstrip()
        for address, mnemonic, operands in rows[:limit]
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("arm64-audit-results.md"),
    )
    parser.add_argument(
        "--workdir",
        type=pathlib.Path,
        default=pathlib.Path(".arm64-audit"),
    )
    args = parser.parse_args()

    fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    args.workdir.mkdir(parents=True, exist_ok=True)
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    report = [
        "# ARM64 audit — independent radare2 and Capstone pass",
        "",
        "Fixture source hashes:",
    ]
    for image, image_data in fixture["inputs"].items():
        report.append(f"- `{image}`: `{image_data['sha256']}`")
    report += ["", "## Results", ""]

    failures: List[str] = []
    for image, image_data in fixture["inputs"].items():
        for region_name, region in image_data["regions"].items():
            va = int(region["va"], 16)
            blob = base64.b64decode(region["base64"], validate=True)
            digest = hashlib.sha256(blob).hexdigest()
            region_failures: List[str] = []
            if digest != region["sha256"]:
                region_failures.append("fixture SHA mismatch")

            raw_path = args.workdir / f"{image}-{region_name}.bin"
            raw_path.write_bytes(blob)
            capstone_rows: List[Instruction] = [
                (ins.address, ins.mnemonic, ins.op_str)
                for ins in md.disasm(blob, va)
            ]
            capstone_map = {
                address: (mnemonic, operands)
                for address, mnemonic, operands in capstone_rows
            }

            try:
                r2_rows, r2_diagnostic = run_r2(
                    raw_path, va, min(64, len(blob) // 4)
                )
            except (subprocess.CalledProcessError, RuntimeError) as error:
                r2_rows = []
                r2_diagnostic = str(error)
                region_failures.append(f"radare2 execution failed: {error}")
            r2_map = {
                address: (mnemonic, operands)
                for address, mnemonic, operands in r2_rows
            }

            if not capstone_rows:
                region_failures.append("Capstone produced no instructions")
            if not r2_rows:
                region_failures.append("radare2 produced no instructions")

            expected = EXPECTED.get((image, region_name), [])
            for address, mnemonic, operands in expected:
                capstone_actual = capstone_map.get(address)
                if capstone_actual is None or not instruction_matches(
                    capstone_actual, mnemonic, operands
                ):
                    region_failures.append(
                        f"Capstone {address:#x} expected {mnemonic} {operands}, "
                        f"got {capstone_actual}"
                    )

                r2_actual = r2_map.get(address)
                if r2_actual is None or not instruction_matches(
                    r2_actual, mnemonic, operands
                ):
                    region_failures.append(
                        f"radare2 {address:#x} expected {mnemonic} {operands}, "
                        f"got {r2_actual}"
                    )

            status = "FAIL" if region_failures else "PASS"
            failures.extend(
                f"{image}/{region_name}: {failure}"
                for failure in region_failures
            )
            report += [
                f"### {image} / {region_name} — {status}",
                "",
                f"- VA: `{va:#x}`",
                f"- Region SHA-256: `{digest}`",
                f"- Assertions: `{len(expected)}`",
                "",
                "Capstone:",
                "```asm",
                *format_rows(capstone_rows),
                "```",
                "",
                "radare2:",
                "```asm",
                *format_rows(r2_rows),
                "```",
                "",
            ]
            if r2_diagnostic:
                report += ["radare2 diagnostics:", "```text", r2_diagnostic, "```", ""]

    report += ["## Final status", ""]
    if failures:
        report.append("FAIL")
        report += [f"- {failure}" for failure in failures]
    else:
        report.append(
            "PASS — all hash-scoped instruction assertions matched in both decoders."
        )

    args.output.write_text("\n".join(report) + "\n", encoding="utf-8")
    print(args.output.read_text(encoding="utf-8"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
