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

override_ids = set()
for key in overrides:
    match = re.fullmatch(r"(\d+):", key)
    if match:
        override_ids.add(int(match.group(1)))

intersection = [parsed[config_id][0] for config_id in sorted(override_ids & parsed.keys())]
relevant = [
    record[0]
    for _, record in sorted(parsed.items())
    if CONFIG_TERMS.search(record[1])
]

(out_dir / "id_name_mapping_base_intersection.json").write_text(
    json.dumps(intersection, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
(out_dir / "id_name_mapping_relevant_configs.json").write_text(
    json.dumps(relevant, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)

employee_test = dict(overrides)
employee_test["28538:"] = ["0: is_enabled : true"]
(out_dir / "mc_overrides_android_employee_test.json").write_text(
    json.dumps(employee_test, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8"
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
    "",
    "## Relevant config names",
    "",
]
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
for entry in relevant:
    print(entry)
