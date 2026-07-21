#!/usr/bin/env python3
import hashlib
import json
import re
import sys
from pathlib import Path

TERMS = re.compile(
    r"employee|dogfood|internal|test[_ -]?user|quick[_ -]?experiment|"
    r"developer[_ -]?option|dev[_ -]?option|sandbox|debug",
    re.I,
)

path = Path(sys.argv[1])
raw = path.read_bytes()
data = json.loads(raw)
if not isinstance(data, list):
    raise SystemExit("mapping top-level is not a list")

matches = [entry for entry in data if isinstance(entry, str) and TERMS.search(entry)]
print(f"mapping_sha256={hashlib.sha256(raw).hexdigest()}")
print(f"mapping_entries={len(data)}")
print(f"relevant_entries={len(matches)}")
for entry in matches:
    print(entry)
