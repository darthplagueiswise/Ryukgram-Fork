#!/usr/bin/env python3
import hashlib
import json
import re
import sys
from pathlib import Path

CONFIG_TERMS = re.compile(
    r"employee|dogfood|dogfooding|internal|test[_-]?user|quick[_-]?experiment|"
    r"developer|devtools|sandbox|debug",
    re.I,
)

# Deliberately narrow Android 435 test set. These IDs and parameter names come
# from the exact 435 mapping, not from guesses based on adjacent builds.
INTERNAL_TEST_OVERRIDES = {
    28538: [(0, "is_enabled", True)],
    39521: [(0, "is_enabled", True)],
    52065: [(1, "fetch_build_info_from_server_enabled", True)],
    56474: [
        (0, "is_employee", True),
        (1, "is_employee_or_employee_test_account", True),
    ],
    57176: [(0, "is_enabled", True)],
    58792: [(0, "is_enabled", True)],
    67118: [(0, "enabled", True)],
    70070: [(2, "internal_only_hip_badge_enabled", True)],
    70221: [(0, "is_enabled", True)],
    75518: [(0, "is_enabled", True)],
    85906: [(0, "only_ondemand_sandbox", True)],
    87318: [(0, "enable_detailed_success_message", True)],
    90631: [
        (0, "is_internal_only_indicator_enabled", True),
        (2, "is_internal_only_share_sheet_target_enabled", True),
        (3, "is_internal_only_sharecut_button_enabled", True),
    ],
    90775: [(1, "show_in_bug_report_menu", True)],
}


def parse_mapping_entry(entry: str):
    parts = entry.split(":")
    if len(parts) < 4 or len(parts) % 2:
        return None
    try:
        config_id = int(parts[0])
    except ValueError:
        return None
    params = []
    for index in range(2, len(parts), 2):
        try:
            param_id = int(parts[index])
        except ValueError:
            return None
        params.append((param_id, parts[index + 1]))
    return config_id, parts[1], params


def override_value(param_id, name, value):
    if isinstance(value, bool):
        encoded = "true" if value else "false"
    else:
        encoded = str(value)
    return f"{param_id}: {name} : {encoded}"


mapping_path = Path(sys.argv[1])
overrides_path = Path(sys.argv[2])
out_dir = Path(sys.argv[3])
out_dir.mkdir(parents=True, exist_ok=True)

mapping_raw = mapping_path.read_bytes()
mapping = json.loads(mapping_raw)
overrides = json.loads(overrides_path.read_text(encoding="utf-8"))
if not isinstance(mapping, list) or not isinstance(overrides, dict):
    raise SystemExit("unexpected JSON shape")

parsed = {}
for entry in mapping:
    if not isinstance(entry, str):
        continue
    record = parse_mapping_entry(entry)
    if record:
        parsed[record[0]] = (entry, record[1], record[2])

for config_id, expected in INTERNAL_TEST_OVERRIDES.items():
    if config_id not in parsed:
        raise SystemExit(f"selected config {config_id} is absent from mapping")
    available = dict(parsed[config_id][2])
    for param_id, name, _ in expected:
        if available.get(param_id) != name:
            raise SystemExit(
                f"selected config {config_id} param {param_id} mismatch: "
                f"expected {name!r}, mapping has {available.get(param_id)!r}"
            )

override_ids = set()
for key in overrides:
    match = re.fullmatch(r"(\d+):", key)
    if match:
        override_ids.add(int(match.group(1)))

intersection_ids = sorted(override_ids & parsed.keys())
intersection = [parsed[config_id][0] for config_id in intersection_ids]
relevant = [
    record[0]
    for _, record in sorted(parsed.items())
    if CONFIG_TERMS.search(record[1])
]
selected_ids = sorted(INTERNAL_TEST_OVERRIDES)
internal_mapping_ids = sorted(set(intersection_ids) | set(selected_ids))
internal_mapping = [parsed[config_id][0] for config_id in internal_mapping_ids]

(out_dir / "id_name_mapping_base_intersection.json").write_text(
    json.dumps(intersection, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
(out_dir / "id_name_mapping_relevant_configs.json").write_text(
    json.dumps(relevant, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
(out_dir / "id_name_mapping_android_internal_test.json").write_text(
    json.dumps(internal_mapping, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)

internal_test = dict(overrides)
for config_id, params in INTERNAL_TEST_OVERRIDES.items():
    internal_test[f"{config_id}:"] = [
        override_value(param_id, name, value) for param_id, name, value in params
    ]
(out_dir / "mc_overrides_android_internal_test.json").write_text(
    json.dumps(internal_test, separators=(",", ":"), ensure_ascii=False) + "\n",
    encoding="utf-8",
)

report = [
    "# Android 435 mapping/override audit",
    "",
    f"- Mapping SHA-256: `{hashlib.sha256(mapping_raw).hexdigest()}`",
    f"- Mapping entries: {len(mapping)}",
    f"- Parsed entries: {len(parsed)}",
    f"- Base override config IDs: {len(override_ids)}",
    f"- Base IDs named by this mapping: {len(intersection)}",
    f"- Relevant config-name matches: {len(relevant)}",
    f"- Selected internal-test configs: {len(selected_ids)}",
    "",
    "## Selected internal-test configs",
    "",
]
for config_id in selected_ids:
    report.append(f"- `{parsed[config_id][0]}`")
report.extend(["", "## Relevant config names", ""])
for entry in relevant:
    report.append(f"- `{entry}`")
report.extend(["", "## Base override IDs with names", ""])
for entry in intersection:
    report.append(f"- `{entry}`")
(out_dir / "AUDIT.md").write_text("\n".join(report) + "\n", encoding="utf-8")

print(f"mapping_sha256={hashlib.sha256(mapping_raw).hexdigest()}")
print(f"mapping_entries={len(mapping)}")
print(f"parsed_entries={len(parsed)}")
print(f"base_override_ids={len(override_ids)}")
print(f"base_intersection={len(intersection)}")
print(f"relevant_config_names={len(relevant)}")
print(f"selected_internal_test_configs={len(selected_ids)}")
for config_id in selected_ids:
    print(parsed[config_id][0])
