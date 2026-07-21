#!/usr/bin/env python3
"""Generate Meta MobileConfig overrides from an id-name mapping.

The mapping format is the JSON array consumed by Meta's MobileConfig tooling:

    ["<config_id>:<config_name>:<param_id>:<param_name>:..."]

The overrides format is the on-disk mc_overrides.json representation:

    {"<config_id>:": ["<param_id>: : <value>"]}

This tool intentionally does not guess arbitrary values. It only writes boolean
identity/internal controls selected by a named profile and skips values whose
names look numeric, textual, secret, URL, duration, rate, count, or versioned.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TRUTHY_PREFIXES = (
    "is_", "has_", "can_", "should_", "enable_", "enabled_", "show_",
    "check_", "allow_", "force_", "use_", "internal_", "dogfood_",
)
TRUTHY_EXACT = {"enabled", "enable", "is_enabled", "check_for_employee"}
NON_BOOLEAN_TOKENS = (
    "key", "url", "password", "duration", "expiration", "timeout", "rate",
    "count", "limit", "timestamp", "version", "days", "hours", "minutes",
    "seconds", "interval", "sample", "percentage", "variant", "mode",
)

# These are companion controls in the same identity-gated configs. They are not
# selected merely because the word employee appears; they are required for the
# corresponding native debug surface to become visible after identity succeeds.
LINKED_DEBUG_PARAMS = {
    (75335, 9),   # ig_shoppable_everything.enable_debug_menu
    (101583, 0),  # related_ads_pivots.enable_debug
    (90775, 1),   # ig_dogfooding_assistant.show_in_bug_report_menu
}


@dataclass(frozen=True)
class Param:
    config_id: int
    config_name: str
    param_id: int
    param_name: str


def load_json(source: str):
    if re.match(r"^https?://", source):
        with urllib.request.urlopen(source, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    return json.loads(Path(source).read_text(encoding="utf-8"))


def parse_mapping(rows: Iterable[str]) -> list[Param]:
    parsed: list[Param] = []
    for row_number, row in enumerate(rows, 1):
        if not isinstance(row, str):
            raise ValueError(f"mapping row {row_number} is not a string")
        parts = row.split(":")
        if len(parts) < 2:
            raise ValueError(f"mapping row {row_number} is malformed: {row!r}")
        try:
            config_id = int(parts[0])
        except ValueError as exc:
            raise ValueError(f"invalid config id in row {row_number}: {row!r}") from exc
        config_name = parts[1]
        tail = parts[2:]
        if len(tail) % 2:
            raise ValueError(f"unpaired param id/name in row {row_number}: {row!r}")
        for index in range(0, len(tail), 2):
            try:
                param_id = int(tail[index])
            except ValueError as exc:
                raise ValueError(f"invalid param id in row {row_number}: {row!r}") from exc
            parsed.append(Param(config_id, config_name, param_id, tail[index + 1]))
    return parsed


def looks_boolean(name: str) -> bool:
    lowered = name.lower()
    if lowered in TRUTHY_EXACT:
        return True
    if any(token in lowered for token in NON_BOOLEAN_TOKENS):
        return False
    return lowered.startswith(TRUTHY_PREFIXES) or lowered.endswith(("_enabled", "_only"))


def identity_match(param: Param) -> tuple[bool, str]:
    config = param.config_name.lower()
    name = param.param_name.lower()

    identity_tokens = (
        "employee", "is_internal_user", "is_test_user", "test_account",
        "dogfood_user", "dogfooder",
    )
    if any(token in name for token in identity_tokens) and looks_boolean(name):
        return True, "identity parameter"

    if "employee" in config and name in TRUTHY_EXACT:
        return True, "employee config master"

    if (param.config_id, param.param_id) in LINKED_DEBUG_PARAMS:
        return True, "linked native debug control"

    return False, ""


def extended_match(param: Param) -> tuple[bool, str]:
    selected, reason = identity_match(param)
    if selected:
        return selected, reason

    config = param.config_name.lower()
    name = param.param_name.lower()
    if any(token in config for token in ("dogfood", "dogfooding", "internal")) and looks_boolean(name):
        return True, "internal/dogfood config boolean"
    if any(token in name for token in ("dogfood", "dogfooding", "internal")) and looks_boolean(name):
        return True, "internal/dogfood parameter"
    return False, ""


def normalize_base(raw) -> OrderedDict[str, list[str]]:
    if not isinstance(raw, dict):
        raise ValueError("base overrides must be a JSON object")
    out: OrderedDict[str, list[str]] = OrderedDict()
    for key, value in raw.items():
        if not isinstance(key, str) or not isinstance(value, list):
            raise ValueError(f"invalid base override entry for {key!r}")
        out[key] = list(value)
    return out


def merge_override(overrides: OrderedDict[str, list[str]], param: Param) -> bool:
    key = f"{param.config_id}:"
    entry = f"{param.param_id}: : true"
    values = overrides.setdefault(key, [])

    # Replace a pre-existing value for this param instead of duplicating it.
    prefix = f"{param.param_id}: : "
    for index, current in enumerate(values):
        if isinstance(current, str) and current.startswith(prefix):
            changed = current != entry
            values[index] = entry
            return changed
    values.append(entry)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, help="base mc_overrides.json")
    parser.add_argument("--mapping", required=True, help="mapping file or HTTP(S) URL")
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument(
        "--profile",
        choices=("employee", "employee-internal-dogfood"),
        default="employee",
    )
    args = parser.parse_args()

    overrides = normalize_base(load_json(args.base))
    mapping = load_json(args.mapping)
    if not isinstance(mapping, list):
        raise ValueError("mapping root must be a JSON array")

    matcher = identity_match if args.profile == "employee" else extended_match
    selected = []
    for param in parse_mapping(mapping):
        matched, reason = matcher(param)
        if not matched:
            continue
        if not looks_boolean(param.param_name) and (param.config_id, param.param_id) not in LINKED_DEBUG_PARAMS:
            continue
        changed = merge_override(overrides, param)
        selected.append({
            "config_id": param.config_id,
            "config_name": param.config_name,
            "param_id": param.param_id,
            "param_name": param.param_name,
            "value": True,
            "reason": reason,
            "changed_base": changed,
        })

    # Meta's reader expects this synthetic bucket to remain present and last.
    qe = overrides.pop("_qe_overrides_", [])
    overrides["_qe_overrides_"] = qe

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(
        json.dumps(overrides, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    Path(args.report).write_text(
        json.dumps({
            "profile": args.profile,
            "selected_count": len(selected),
            "selected": selected,
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"selected {len(selected)} boolean overrides")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
