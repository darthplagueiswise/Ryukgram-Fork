#!/usr/bin/env python3
import json
import pathlib
import sys

try:
    from strongarm.macho import MachoParser, MachoAnalyzer
except Exception as exc:
    print(f"strongarm import failed: {exc}", file=sys.stderr)
    print("Install with: python3 -m pip install strongarm-ios", file=sys.stderr)
    sys.exit(1)

KEYWORDS = (
    "ig_",
    "quick_snap",
    "quicksnap",
    "instants",
    "dogfood",
    "employee",
    "internal",
    "mobileconfig",
    "experiment",
    "enabled",
    "eligib",
    "prism",
    "homecoming",
    "notes",
    "friend",
    "map",
)


def useful_string(value: str) -> bool:
    lowered = value.lower()
    return any(k in lowered for k in KEYWORDS)


def main() -> None:
    if len(sys.argv) < 3:
        print("usage: generate_mobileconfig_map_strongarm.py <Mach-O path> <out.json>", file=sys.stderr)
        sys.exit(2)

    macho_path = pathlib.Path(sys.argv[1])
    out_path = pathlib.Path(sys.argv[2])

    parser = MachoParser(macho_path)
    binary = parser.get_arm64_slice()
    analyzer = MachoAnalyzer.get_analyzer(binary)

    out = {
        "binary": str(macho_path),
        "strings": [],
        "symbols": [],
        "specifiers": {},
    }

    for item in analyzer.strings():
        text = str(item)
        if useful_string(text):
            out["strings"].append(text)

    exported = getattr(analyzer, "exported_symbol_names_to_pointers", {})
    for name, ptr in exported.items():
        clean = name[1:] if name.startswith("_") else name
        if not useful_string(clean):
            continue
        out["symbols"].append({
            "name": clean,
            "address": hex(ptr),
        })

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
