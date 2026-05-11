#!/usr/bin/env python3
import argparse
import json
import logging
import re
from collections import defaultdict
from pathlib import Path

from androguard.core.dex import DEX


MOBILECONFIG_TOKENS = (
    "MobileConfigUnsafeContext;",
    "MobileConfig;",
    "mobileconfig",
)

GENERIC_STRINGS = {
    "true",
    "false",
    "null",
    "login",
    "logout",
    "share",
    "news",
    "menu",
    "direct",
    "reels",
    "explore",
    "waitlist",
    "reason",
    "request_id",
    "max_id",
    "pagination_source",
    "timezone_offset",
    "client_recorded_request_time_ms",
    "last_head_load_time_ms",
    "is_retry_request",
    "is_pull_to_refresh",
}

KEY_RE = re.compile(r"^[a-z][a-z0-9_]{3,96}$")
KEY_FIND_RE = re.compile(r"[a-z][a-z0-9_]{3,96}")
REG_RE = re.compile(r"\bv\d+\b")


def looks_like_mc_name(value):
    if not value or value in GENERIC_STRINGS:
        return False
    if not KEY_RE.match(value):
        return False
    return "_" in value


def candidate_names_from_string(value):
    if not value:
        return []
    out = []
    for match in KEY_FIND_RE.findall(value):
        if looks_like_mc_name(match) and match not in out:
            out.append(match)
    return out


def parse_const_string(output):
    if "," not in output:
        return None
    value = output.split(",", 1)[1].strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = value[1:-1]
    return value


def parse_const_wide(output):
    if "," not in output:
        return None
    raw = output.split(",", 1)[1].strip().split()[0]
    try:
        return int(raw, 0)
    except ValueError:
        return None


def register_number(register):
    try:
        return int(register[1:])
    except Exception:
        return -1


def invoke_registers(output):
    before_method = output.split(", L", 1)[0]
    return REG_RE.findall(before_method)


def wide_register_matches(invoke_regs, wide_reg):
    wide_index = register_number(wide_reg)
    if wide_index < 0:
        return False
    wanted = {f"v{wide_index}", f"v{wide_index + 1}"}
    return bool(wanted.intersection(invoke_regs))


def scan_dex_file(path):
    dex = DEX(path.read_bytes())
    candidates = []

    for cls in dex.get_classes():
        for method in cls.get_methods():
            code = method.get_code()
            if not code:
                continue

            instructions = []
            last_strings = {}
            last_wides = {}

            for index, ins in enumerate(code.get_bc().get_instructions()):
                name = ins.get_name()
                output = ins.get_output()
                string_value = None
                wide_value = None

                if name.startswith("const-string"):
                    regs = REG_RE.findall(output)
                    string_value = parse_const_string(output)
                    names = candidate_names_from_string(string_value)
                    if regs and names:
                        last_strings[regs[0]] = (index, names)

                if name.startswith("const-wide"):
                    regs = REG_RE.findall(output)
                    wide_value = parse_const_wide(output)
                    if regs and wide_value:
                        last_wides[regs[0]] = (index, wide_value)

                instructions.append((index, name, output, string_value, wide_value, dict(last_strings), dict(last_wides)))

            for index, name, output, _string_value, _wide_value, strings_before, wides_before in instructions:
                if not name.startswith("invoke-"):
                    continue
                if not any(token in output for token in MOBILECONFIG_TOKENS):
                    continue

                regs = invoke_registers(output)
                if not regs:
                    continue

                matched_wides = []
                for wide_reg, (wide_index, wide_value) in wides_before.items():
                    if wide_register_matches(regs, wide_reg):
                        matched_wides.append((index - wide_index, wide_reg, wide_index, wide_value))
                if not matched_wides:
                    continue
                matched_wides.sort()
                wide_distance, wide_reg, wide_index, mobileconfig_id = matched_wides[0]

                names = []
                for string_reg, (string_index, string_values) in strings_before.items():
                    if string_reg in regs:
                        for string_value in string_values:
                            names.append((0, 120, string_reg, string_index, string_value, "invoke-arg"))

                start = max(0, wide_index - 12)
                end = min(len(instructions), index + 8)
                for item_index, _n, _o, string_value, _w, _sb, _wb in instructions[start:end]:
                    for string_value in candidate_names_from_string(string_value):
                        distance = abs(item_index - wide_index)
                        names.append((distance, max(20, 80 - distance), "", item_index, string_value, "nearby"))

                if not names:
                    method_names = []
                    for item_index, _n, _o, string_value, _w, _sb, _wb in instructions:
                        for candidate in candidate_names_from_string(string_value):
                            distance = abs(item_index - wide_index)
                            if distance <= 160:
                                method_names.append((distance, max(8, 35 - distance // 8), "", item_index, candidate, "method-scope"))
                    names.extend(method_names)

                if not names:
                    continue
                names.sort(key=lambda item: (-item[1], item[0], item[4]))
                distance, score, string_reg, string_index, best_name, source = names[0]

                candidates.append({
                    "id": mobileconfig_id,
                    "hex": hex(mobileconfig_id),
                    "name": best_name,
                    "score": score,
                    "distance": distance,
                    "nameSource": source,
                    "wideRegister": wide_reg,
                    "stringRegister": string_reg,
                    "dex": path.name,
                    "class": cls.get_name(),
                    "method": method.get_name(),
                    "descriptor": method.get_descriptor(),
                    "invoke": output,
                })

    return candidates


def merge_candidates(candidates):
    grouped = defaultdict(list)
    for item in candidates:
        grouped[(item["id"], item["name"])].append(item)

    merged = []
    for (mobileconfig_id, name), items in grouped.items():
        best = sorted(items, key=lambda item: (-item["score"], item["distance"], item["dex"]))[0].copy()
        best["evidenceCount"] = len(items)
        best["source"] = "android-dex-candidate"
        merged.append(best)

    by_id = {}
    for item in merged:
        old = by_id.get(item["id"])
        if old is None or (item["score"], item["evidenceCount"], -item["distance"]) > (old["score"], old["evidenceCount"], -old["distance"]):
            by_id[item["id"]] = item

    return sorted(by_id.values(), key=lambda item: (item["name"], item["id"]))


def main():
    parser = argparse.ArgumentParser(description="Extract Android DEX MobileConfig name/id candidates.")
    parser.add_argument("apk_dir", help="Extracted APK directory containing classes*.dex")
    parser.add_argument("--out-dir", default="CODEX/reports/android_mobileconfig")
    parser.add_argument("--mapping-out", default="resources/mobileconfig_res/id_name_mapping.android_dex_candidates.json")
    args = parser.parse_args()

    logging.getLogger("androguard").setLevel(logging.ERROR)
    try:
        from loguru import logger
        logger.disable("androguard")
    except Exception:
        pass

    apk_dir = Path(args.apk_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    all_candidates = []
    for dex_path in sorted(apk_dir.glob("classes*.dex")):
        all_candidates.extend(scan_dex_file(dex_path))

    merged = merge_candidates(all_candidates)
    mapping = [f"{item['id']}:{item['name']}" for item in merged]

    details_path = out_dir / "android_mc_candidates.json"
    mapping_report_path = out_dir / "id_name_mapping.android_dex_candidates.json"
    mapping_out_path = Path(args.mapping_out)
    mapping_out_path.parent.mkdir(parents=True, exist_ok=True)

    details_path.write_text(json.dumps(merged, indent=2, sort_keys=True), encoding="utf-8")
    mapping_report_path.write_text(json.dumps(mapping, indent=2), encoding="utf-8")
    mapping_out_path.write_text(json.dumps(mapping, indent=2), encoding="utf-8")

    print(f"rawCandidates={len(all_candidates)} mergedCandidates={len(merged)}")
    print(f"details={details_path}")
    print(f"mapping={mapping_out_path}")
    for needle in ("homecoming", "is_feed_eager_refresh", "fail_open", "liquid_glass"):
        hits = [item for item in merged if needle.lower() in item["name"].lower()]
        if hits:
            print(f"-- {needle}")
            for item in hits[:20]:
                print(f"{item['hex']} {item['name']} {item['dex']} {item['class']} {item['method']} score={item['score']}")


if __name__ == "__main__":
    main()
