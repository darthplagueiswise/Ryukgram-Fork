#!/usr/bin/env python3
"""Reconstruct the exact Mapping-V8 snapshot from the retained base + compact delta."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from typing import Dict, List


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def entry_id(entry: str) -> int:
    try:
        return int(entry.split(":", 1)[0])
    except (ValueError, IndexError) as exc:
        raise ValueError(f"invalid mapping entry: {entry!r}") from exc


def load_mapping(path: Path) -> List[str]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{path}: expected a JSON array of strings")
    ids = [entry_id(item) for item in value]
    if len(ids) != len(set(ids)):
        raise ValueError(f"{path}: duplicate config IDs")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--delta", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    base_bytes = args.base.read_bytes()
    delta = json.loads(args.delta.read_text(encoding="utf-8"))

    expected_base = delta.get("base_git_blob_sha1")
    actual_base = git_blob_sha1(base_bytes)
    if expected_base and actual_base != expected_base:
        raise ValueError(
            f"base mapping mismatch: expected git blob {expected_base}, got {actual_base}"
        )

    base = load_mapping(args.base)
    by_id: Dict[int, str] = {entry_id(item): item for item in base}

    for config_id in delta.get("removed_ids", []):
        by_id.pop(int(config_id), None)

    replacement_entries = dict(delta.get("entries", {}))
    for entry_file in delta.get("entry_files", []):
        part_path = args.delta.parent / entry_file
        part = json.loads(part_path.read_text(encoding="utf-8"))
        overlap = set(replacement_entries).intersection(part)
        if overlap:
            raise ValueError(f"duplicate delta entry IDs in {part_path}: {sorted(overlap)[:10]}")
        replacement_entries.update(part)

    for config_id, entry in replacement_entries.items():
        parsed_id = entry_id(entry)
        if parsed_id != int(config_id):
            raise ValueError(f"delta key {config_id} does not match entry ID {parsed_id}")
        by_id[parsed_id] = entry

    order = [int(value) for value in delta["order"]]
    if len(order) != len(set(order)):
        raise ValueError("delta order contains duplicate IDs")
    if set(order) != set(by_id):
        missing = sorted(set(by_id) - set(order))
        unexpected = sorted(set(order) - set(by_id))
        raise ValueError(
            f"delta order mismatch: missing={missing[:10]} unexpected={unexpected[:10]}"
        )

    output = json.dumps(
        [by_id[config_id] for config_id in order],
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")

    expected_count = int(delta["expected_entries"])
    if len(order) != expected_count:
        raise ValueError(f"expected {expected_count} entries, reconstructed {len(order)}")

    expected_sha256 = delta["expected_sha256"]
    actual_sha256 = hashlib.sha256(output).hexdigest()
    if actual_sha256 != expected_sha256:
        raise ValueError(
            f"reconstructed mapping hash mismatch: expected {expected_sha256}, got {actual_sha256}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=args.output.name + ".", dir=args.output.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(output)
        os.replace(temporary, args.output)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise

    print(
        f"wrote {args.output}: entries={expected_count} sha256={actual_sha256}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
