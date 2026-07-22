#!/usr/bin/env python3
"""Build named Meta MobileConfig override profiles from a real backup.

Input mapping rows use:
    <config_id>:<config_name>:<param_id>:<param_name>:...

The base may mix raw and rich entries. Output is normalized to the rich format
where the mapping supplies names, while unknown entries and values are retained.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

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

# Native surfaces that accompany identity. The icon is explicitly required in
# both profiles even though its config name is Android-specific.
COMMON_REQUIRED = {
    (56474, 0): "is_employee",
    (56474, 1): "is_employee_or_employee_test_account",
    (57176, 0): "is_enabled",
    (75335, 9): "enable_debug_menu",
    (101583, 0): "enable_debug",
}
EXTENDED_REQUIRED = {
    (90775, 1): "show_in_bug_report_menu",
}


@dataclass(frozen=True)
class Param:
    config_id: int
    config_name: str
    param_id: int
    param_name: str


@dataclass
class ConfigEntry:
    config_id: int
    original_name: str = ""
    values: OrderedDict[int, tuple[str, str]] = field(default_factory=OrderedDict)
    malformed: list[str] = field(default_factory=list)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=OrderedDict)


def parse_mapping(rows: Iterable[str]) -> tuple[dict[int, str], dict[tuple[int, int], str], list[Param]]:
    config_names: dict[int, str] = {}
    param_names: dict[tuple[int, int], str] = {}
    params: list[Param] = []
    for row_number, row in enumerate(rows, 1):
        if not isinstance(row, str):
            raise ValueError(f"mapping row {row_number} is not a string")
        parts = row.split(":")
        if len(parts) < 2:
            raise ValueError(f"mapping row {row_number} is malformed")
        try:
            config_id = int(parts[0].strip())
        except ValueError as exc:
            raise ValueError(f"invalid config id in mapping row {row_number}") from exc
        config_name = parts[1].strip()
        tail = parts[2:]
        if len(tail) % 2:
            raise ValueError(f"unpaired param id/name in mapping row {row_number}")
        previous = config_names.get(config_id)
        if previous and previous != config_name:
            raise ValueError(f"config {config_id} has conflicting names: {previous!r} / {config_name!r}")
        config_names[config_id] = config_name
        for offset in range(0, len(tail), 2):
            try:
                param_id = int(tail[offset].strip())
            except ValueError as exc:
                raise ValueError(f"invalid param id in mapping row {row_number}") from exc
            param_name = tail[offset + 1].strip()
            key = (config_id, param_id)
            previous_param = param_names.get(key)
            if previous_param and previous_param != param_name:
                raise ValueError(f"param {config_id}/{param_id} has conflicting names")
            param_names[key] = param_name
            params.append(Param(config_id, config_name, param_id, param_name))
    return config_names, param_names, params


def parse_config_key(key: str) -> tuple[int, str]:
    first, sep, remainder = key.partition(":")
    if not sep:
        raise ValueError(f"invalid override key: {key!r}")
    return int(first.strip()), remainder.strip()


def parse_override_line(line: str) -> tuple[int, str, str] | None:
    if not isinstance(line, str):
        return None
    parts = line.split(":", 2)
    if len(parts) != 3:
        return None
    try:
        index = int(parts[0].strip())
    except ValueError:
        return None
    return index, parts[1].strip(), parts[2].strip()


def normalize_base(raw: Any) -> tuple[OrderedDict[int, ConfigEntry], list[Any]]:
    if not isinstance(raw, dict):
        raise ValueError("base overrides must be a JSON object")
    configs: OrderedDict[int, ConfigEntry] = OrderedDict()
    qe: list[Any] = []
    for key, raw_values in raw.items():
        if key == "_qe_overrides_":
            if not isinstance(raw_values, list):
                raise ValueError("_qe_overrides_ must be an array")
            qe = list(raw_values)
            continue
        if not isinstance(key, str) or not isinstance(raw_values, list):
            raise ValueError(f"invalid base override entry: {key!r}")
        config_id, original_name = parse_config_key(key)
        entry = configs.setdefault(config_id, ConfigEntry(config_id=config_id, original_name=original_name))
        if original_name:
            entry.original_name = original_name
        for raw_line in raw_values:
            parsed = parse_override_line(raw_line)
            if parsed is None:
                entry.malformed.append(raw_line)
                continue
            param_id, original_param_name, value = parsed
            # Later duplicate entries win, matching dictionary/override semantics.
            entry.values[param_id] = (original_param_name, value)
    return configs, qe


def contains_non_boolean_token(name: str) -> bool:
    # Token matching deliberately avoids rejecting "account" because it contains
    # the substring "count".
    return bool(set(name.lower().split("_")) & NON_BOOLEAN_TOKENS)


def looks_boolean(name: str) -> bool:
    lowered = name.lower()
    if lowered in TRUTHY_EXACT:
        return True
    if contains_non_boolean_token(lowered):
        return False
    return lowered.startswith(TRUTHY_PREFIXES) or lowered.endswith(("_enabled", "_only", "_user"))


def employee_match(param: Param) -> tuple[bool, str]:
    config = param.config_name.lower()
    name = param.param_name.lower()
    identity_tokens = (
        "employee", "is_internal_user", "internal_user", "is_test_user",
        "test_user", "test_account", "employee_test", "oem_tester",
    )
    if any(token in name for token in identity_tokens) and looks_boolean(name):
        return True, "employee/internal/test identity"
    if "employee" in config and looks_boolean(name):
        return True, "boolean in employee config"
    if (param.config_id, param.param_id) in COMMON_REQUIRED:
        return True, "required native identity/debug companion"
    return False, ""


def extended_match(param: Param) -> tuple[bool, str]:
    selected, reason = employee_match(param)
    if selected:
        return selected, reason
    config = param.config_name.lower()
    name = param.param_name.lower()
    if any(token in name for token in ("dogfood", "dogfooding", "dogfooder")) and looks_boolean(name):
        return True, "dogfood identity/control"
    if any(token in config for token in ("dogfood", "dogfooding")) and looks_boolean(name):
        return True, "boolean in dogfood config"
    if "internal" in name and looks_boolean(name):
        return True, "internal control"
    if "internal" in config and looks_boolean(name):
        return True, "boolean in internal config"
    if (param.config_id, param.param_id) in EXTENDED_REQUIRED:
        return True, "required dogfooding assistant companion"
    return False, ""


def set_override(
    configs: OrderedDict[int, ConfigEntry],
    config_names: dict[int, str],
    param_names: dict[tuple[int, int], str],
    config_id: int,
    param_id: int,
    fallback_name: str,
) -> None:
    entry = configs.setdefault(config_id, ConfigEntry(config_id=config_id, original_name=config_names.get(config_id, "")))
    name = param_names.get((config_id, param_id), fallback_name)
    entry.values[param_id] = (name, "true")


def render(
    configs: OrderedDict[int, ConfigEntry],
    qe: list[Any],
    config_names: dict[int, str],
    param_names: dict[tuple[int, int], str],
) -> OrderedDict[str, list[str]]:
    output: OrderedDict[str, list[str]] = OrderedDict()
    for config_id, entry in configs.items():
        config_name = config_names.get(config_id) or entry.original_name
        key = f"{config_id}:{config_name}" if config_name else f"{config_id}:"
        rendered: list[str] = []
        for param_id, (original_param_name, value) in entry.values.items():
            param_name = param_names.get((config_id, param_id)) or original_param_name
            if param_name:
                rendered.append(f"{param_id}: {param_name}: {value}")
            else:
                rendered.append(f"{param_id}: : {value}")
        rendered.extend(entry.malformed)
        output[key] = rendered
    output["_qe_overrides_"] = qe
    return output


def clone_configs(source: OrderedDict[int, ConfigEntry]) -> OrderedDict[int, ConfigEntry]:
    result: OrderedDict[int, ConfigEntry] = OrderedDict()
    for config_id, entry in source.items():
        result[config_id] = ConfigEntry(
            config_id=config_id,
            original_name=entry.original_name,
            values=OrderedDict(entry.values),
            malformed=list(entry.malformed),
        )
    return result


def build_profile(
    profile: str,
    base_configs: OrderedDict[int, ConfigEntry],
    qe: list[Any],
    config_names: dict[int, str],
    param_names: dict[tuple[int, int], str],
    params: list[Param],
) -> tuple[OrderedDict[str, list[str]], list[dict[str, Any]]]:
    configs = clone_configs(base_configs)
    matcher = employee_match if profile == "employee" else extended_match
    selected: OrderedDict[tuple[int, int], dict[str, Any]] = OrderedDict()
    for param in params:
        matched, reason = matcher(param)
        if not matched:
            continue
        set_override(configs, config_names, param_names, param.config_id, param.param_id, param.param_name)
        selected[(param.config_id, param.param_id)] = {
            "config_id": param.config_id,
            "config_name": param.config_name,
            "param_id": param.param_id,
            "param_name": param.param_name,
            "value": True,
            "reason": reason,
        }

    required = dict(COMMON_REQUIRED)
    if profile != "employee":
        required.update(EXTENDED_REQUIRED)
    for (config_id, param_id), fallback_name in required.items():
        set_override(configs, config_names, param_names, config_id, param_id, fallback_name)
        selected.setdefault((config_id, param_id), {
            "config_id": config_id,
            "config_name": config_names.get(config_id, ""),
            "param_id": param_id,
            "param_name": param_names.get((config_id, param_id), fallback_name),
            "value": True,
            "reason": "mandatory profile control",
        })

    output = render(configs, qe, config_names, param_names)
    return output, list(selected.values())


def assert_true(output: dict[str, list[str]], config_id: int, param_id: int) -> None:
    matching_keys = [key for key in output if key != "_qe_overrides_" and key.split(":", 1)[0] == str(config_id)]
    if len(matching_keys) != 1:
        raise AssertionError(f"expected one output key for config {config_id}, got {matching_keys}")
    for line in output[matching_keys[0]]:
        parsed = parse_override_line(line)
        if parsed and parsed[0] == param_id and parsed[2].lower() == "true":
            return
    raise AssertionError(f"required true override missing: {config_id}/{param_id}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--mapping", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    args = parser.parse_args()

    mapping_raw = load_json(args.mapping)
    if not isinstance(mapping_raw, list):
        raise ValueError("mapping root must be a JSON array")
    config_names, param_names, params = parse_mapping(mapping_raw)
    base_configs, qe = normalize_base(load_json(args.base))

    args.outdir.mkdir(parents=True, exist_ok=True)
    profile_names = ("employee", "employee_internal_dogfood")
    reports: dict[str, Any] = {
        "mapping_rows": len(mapping_raw),
        "mapping_configs": len(config_names),
        "mapping_params": len(param_names),
        "base_configs": len(base_configs),
        "profiles": {},
    }

    for profile in profile_names:
        output, selected = build_profile(profile, base_configs, qe, config_names, param_names, params)
        assert_true(output, 56474, 0)
        assert_true(output, 56474, 1)
        assert_true(output, 57176, 0)
        destination = args.outdir / f"mc_overrides_{profile}.json"
        destination.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        # Parse the emitted file again so malformed serialization cannot pass CI.
        json.loads(destination.read_text(encoding="utf-8"))
        reports["profiles"][profile] = {
            "selected_count": len(selected),
            "output_configs": len(output) - 1,
            "selected": selected,
        }
        print(f"{profile}: selected={len(selected)} output_configs={len(output) - 1} path={destination}")

    (args.outdir / "mc_overrides_profiles_report.json").write_text(
        json.dumps(reports, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
