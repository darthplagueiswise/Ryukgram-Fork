#!/usr/bin/env python3
"""Merge employee/internal/dogfood MobileConfig flags into a real named backup.

Input formats accepted:
  "<cid>:"             -> ["<idx>: : <value>"]
  "<cid>:<config_name>" -> ["<idx>: <param_name>: <value>"]

The two outputs are always normalized to the named internal format when the
mapping supplies names.  Existing values are preserved except for selected
identity gates, which are deliberately replaced with true.  In both profiles
57176/0 (ig_android_dogfooding_icon.is_enabled) is forced true.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable


TRUTHY_PREFIXES = (
    "is_", "has_", "can_", "should_", "enable_", "enabled_", "show_",
    "check_", "allow_", "force_", "use_", "internal_", "dogfood_",
)
TRUTHY_EXACT = {"enabled", "enable", "is_enabled", "check_for_employee"}
NON_BOOLEAN_TOKENS = {
    "key", "url", "password", "duration", "expiration", "timeout", "rate",
    "count", "limit", "timestamp", "version", "days", "hours", "minutes",
    "seconds", "interval", "sample", "percentage", "variant", "mode",
}

# Companion controls required by the native debug surfaces.
LINKED_DEBUG_PARAMS = {
    (75335, 9),    # enable_debug_menu
    (101583, 0),   # enable_debug
    (90775, 1),    # show_in_bug_report_menu
}

# Explicit user requirement: true in BOTH generated versions.
FORCED_BOTH = {
    (57176, 0): ("ig_android_dogfooding_icon", "is_enabled"),
}


@dataclass(frozen=True)
class Param:
    config_id: int
    config_name: str
    param_id: int
    param_name: str


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def parse_mapping(rows: Iterable[str]) -> list[Param]:
    result: list[Param] = []
    for row_number, row in enumerate(rows, 1):
        if not isinstance(row, str):
            raise ValueError(f"mapping row {row_number} is not a string")
        parts = row.split(":")
        if len(parts) < 2:
            raise ValueError(f"mapping row {row_number} is malformed")
        config_id = int(parts[0])
        config_name = parts[1]
        tail = parts[2:]
        if len(tail) % 2:
            raise ValueError(f"mapping row {row_number} has an unpaired param")
        for index in range(0, len(tail), 2):
            result.append(Param(config_id, config_name, int(tail[index]), tail[index + 1]))
    return result


def parse_key(key: str) -> tuple[int | None, str]:
    match = re.match(r"^\s*(\d+)\s*:(.*)$", key)
    if not match:
        return None, ""
    return int(match.group(1)), match.group(2).strip()


def parse_line(line: str) -> tuple[int, str, str]:
    parts = line.split(":", 2)
    if len(parts) != 3:
        raise ValueError(f"invalid override line: {line!r}")
    return int(parts[0].strip()), parts[1].strip(), parts[2].strip()


def looks_boolean(name: str) -> bool:
    lowered = name.lower()
    if lowered in TRUTHY_EXACT:
        return True
    # Token matching is deliberate: "count" must not reject "account".
    if NON_BOOLEAN_TOKENS.intersection(lowered.split("_")):
        return False
    return lowered.startswith(TRUTHY_PREFIXES) or lowered.endswith(("_enabled", "_only"))


def identity_match(param: Param) -> bool:
    name = param.param_name.lower()
    config = param.config_name.lower()
    identity_tokens = (
        "employee", "is_internal_user", "is_test_user", "test_account",
        "dogfood_user", "dogfooder",
    )
    if any(token in name for token in identity_tokens) and looks_boolean(name):
        return True
    if "employee" in config and name in TRUTHY_EXACT:
        return True
    return (param.config_id, param.param_id) in LINKED_DEBUG_PARAMS


def extended_match(param: Param) -> bool:
    if identity_match(param):
        return True
    config = param.config_name.lower()
    name = param.param_name.lower()
    if any(token in config for token in ("dogfood", "dogfooding", "internal")) and looks_boolean(name):
        return True
    return any(token in name for token in ("dogfood", "dogfooding", "internal")) and looks_boolean(name)


def normalize_base(
    raw: Any,
    config_names: dict[int, str],
    param_names: dict[tuple[int, int], str],
) -> tuple[OrderedDict[int, OrderedDict[int, tuple[str, str]]], OrderedDict[str, Any], list[Any]]:
    if not isinstance(raw, dict):
        raise ValueError("base overrides root must be an object")

    configs: OrderedDict[int, OrderedDict[int, tuple[str, str]]] = OrderedDict()
    passthrough: OrderedDict[str, Any] = OrderedDict()
    qe: list[Any] = []

    # Preserve source order. If raw and named keys refer to the same config/param,
    # the later occurrence wins, matching ordinary JSON merge semantics.
    for key, value in raw.items():
        if key == "_qe_overrides_":
            if isinstance(value, list):
                qe = list(value)
            continue
        config_id, existing_config_name = parse_key(key)
        if config_id is None or not isinstance(value, list):
            passthrough[key] = value
            continue

        if existing_config_name and config_id not in config_names:
            config_names[config_id] = existing_config_name
        params = configs.setdefault(config_id, OrderedDict())
        for raw_line in value:
            if not isinstance(raw_line, str):
                continue
            param_id, existing_param_name, param_value = parse_line(raw_line)
            if existing_param_name and (config_id, param_id) not in param_names:
                param_names[(config_id, param_id)] = existing_param_name
            params[param_id] = (existing_param_name, param_value)

    return configs, passthrough, qe


def merge_true(
    configs: OrderedDict[int, OrderedDict[int, tuple[str, str]]],
    param: Param,
) -> None:
    params = configs.setdefault(param.config_id, OrderedDict())
    params[param.param_id] = (param.param_name, "true")


def render(
    base_raw: Any,
    all_params: list[Param],
    matcher: Callable[[Param], bool],
) -> OrderedDict[str, Any]:
    config_names = {param.config_id: param.config_name for param in all_params}
    param_names = {(param.config_id, param.param_id): param.param_name for param in all_params}
    configs, passthrough, qe = normalize_base(base_raw, config_names, param_names)

    for param in all_params:
        if matcher(param):
            merge_true(configs, param)

    for (config_id, param_id), (config_name, param_name) in FORCED_BOTH.items():
        config_names.setdefault(config_id, config_name)
        param_names.setdefault((config_id, param_id), param_name)
        merge_true(configs, Param(config_id, config_names[config_id], param_id,
                                  param_names[(config_id, param_id)]))

    output: OrderedDict[str, Any] = OrderedDict()
    output.update(passthrough)
    for config_id, params in configs.items():
        config_name = config_names.get(config_id, "")
        key = f"{config_id}:{config_name}" if config_name else f"{config_id}:"
        lines: list[str] = []
        # Keep the backup's common descending-param style.
        for param_id in sorted(params, reverse=True):
            existing_name, value = params[param_id]
            param_name = param_names.get((config_id, param_id), existing_name)
            lines.append(f"{param_id}: {param_name}: {value}")
        output[key] = lines
    output["_qe_overrides_"] = qe
    return output


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    base_raw = load_json(args.base)
    mapping_raw = load_json(args.mapping)
    if not isinstance(mapping_raw, list):
        raise ValueError("mapping root must be an array")
    all_params = parse_mapping(mapping_raw)

    employee = render(base_raw, all_params, identity_match)
    extended = render(base_raw, all_params, extended_match)

    write_json(args.output_dir / "mc_overrides_employee.json", employee)
    write_json(args.output_dir / "mc_overrides_employee_internal_dogfood.json", extended)

    for filename, data in (
        ("mc_overrides_employee.json", employee),
        ("mc_overrides_employee_internal_dogfood.json", extended),
    ):
        dogfood = data.get("57176:ig_android_dogfooding_icon")
        employee_gate = data.get("56474:ig_is_employee")
        if dogfood != ["0: is_enabled: true"]:
            raise RuntimeError(f"{filename}: dogfooding icon was not forced true")
        if not employee_gate or not any(line.startswith("0: is_employee: true") for line in employee_gate):
            raise RuntimeError(f"{filename}: is_employee is not true")

    print(args.output_dir / "mc_overrides_employee.json")
    print(args.output_dir / "mc_overrides_employee_internal_dogfood.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
