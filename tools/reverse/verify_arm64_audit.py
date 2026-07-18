#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import pathlib
import re
import subprocess
import sys

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

EXPECTED = {
    ("Instagram", "startup_mc_call"): [
        (0x102C56044, "add", "x3, sp, #8"),
        (0x102C5604C, "bl", "#0x109e5308c"),
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
}


def normalized(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def run_r2(path: pathlib.Path, va: int, instruction_count: int) -> str:
    command = [
        "r2", "-q", "-n", "-a", "arm", "-b", "64", "-m", hex(va),
        "-c", f"e asm.bytes=false; e asm.lines=false; pd {instruction_count}; q",
        str(path),
    ]
    completed = subprocess.run(command, check=True, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return completed.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path,
                        default=pathlib.Path("arm64-audit-results.md"))
    parser.add_argument("--workdir", type=pathlib.Path,
                        default=pathlib.Path(".arm64-audit"))
    args = parser.parse_args()

    fixture = json.loads(args.fixture.read_text())
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

    failures = []
    for image, image_data in fixture["inputs"].items():
        for region_name, region in image_data["regions"].items():
            va = int(region["va"], 16)
            blob = base64.b64decode(region["base64"])
            digest = hashlib.sha256(blob).hexdigest()
            if digest != region["sha256"]:
                failures.append(f"{image}/{region_name}: fixture SHA mismatch")
                continue

            raw_path = args.workdir / f"{image}-{region_name}.bin"
            raw_path.write_bytes(blob)
            capstone_rows = [
                (ins.address, ins.mnemonic, ins.op_str)
                for ins in md.disasm(blob, va)
            ]
            capstone_map = {address: (mnemonic, operands)
                            for address, mnemonic, operands in capstone_rows}
            r2_output = run_r2(raw_path, va, min(64, len(blob) // 4))
            r2_norm = normalized(r2_output)

            expected = EXPECTED.get((image, region_name), [])
            status = "PASS"
            for address, mnemonic, operands in expected:
                actual = capstone_map.get(address)
                if actual is None or normalized(actual[0]) != normalized(mnemonic) or \
                        normalized(actual[1]) != normalized(operands):
                    failures.append(
                        f"{image}/{region_name}: Capstone {address:#x} expected "
                        f"{mnemonic} {operands}, got {actual}"
                    )
                    status = "FAIL"
                needle = normalized(f"{mnemonic} {operands}")
                if needle not in r2_norm:
                    failures.append(
                        f"{image}/{region_name}: radare2 output missing {needle}"
                    )
                    status = "FAIL"

            report += [
                f"### {image} / {region_name} — {status}",
                "",
                f"- VA: `{va:#x}`",
                f"- Region SHA-256: `{digest}`",
                "",
                "Capstone:",
                "```asm",
            ]
            for address, mnemonic, operands in capstone_rows[:32]:
                report.append(f"{address:#x}: {mnemonic} {operands}".rstrip())
            report += ["```", "", "radare2:", "```text", r2_output.rstrip(), "```", ""]

    report += ["## Final status", ""]
    if failures:
        report.append("FAIL")
        report += [f"- {failure}" for failure in failures]
    else:
        report.append("PASS — all hash-scoped instruction assertions matched in both decoders.")

    args.output.write_text("\n".join(report) + "\n")
    print(args.output.read_text())
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
