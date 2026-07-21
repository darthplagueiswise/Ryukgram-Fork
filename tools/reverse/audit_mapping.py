#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

TERMS = re.compile(r"employee|dogfood|internal|test[_ -]?user|quick[_ -]?experiment|developer[_ -]?option|dev[_ -]?option|sandbox|debug", re.I)

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(data, list):
    raise SystemExit("mapping top-level is not a list")

matches = [entry for entry in data if isinstance(entry, str) and TERMS.search(entry)]
print(f"mapping_entries={len(data)}")
print(f"relevant_entries={len(matches)}")
for entry in matches:
    print(entry)
