#!/usr/bin/env python3
import base64
import pathlib
import sys

HEADER = '''#import <Foundation/Foundation.h>\n\n'''

STUB = HEADER + '''NSData *SCIEmbeddedMobileConfigSchemaData(void) {\n    return nil;\n}\n\nNSString *SCIEmbeddedMobileConfigSchemaName(void) {\n    return nil;\n}\n'''


def write_stub(out_path: pathlib.Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(STUB, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: embed_mobileconfig_schema.py <schema.json> <out.m>", file=sys.stderr)
        return 2

    src = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)

    if not src.is_file():
        write_stub(out)
        print(f"[RyukGram][MCMapping] schema not embedded; missing {src}")
        return 0

    data = src.read_bytes()
    encoded = base64.b64encode(data).decode("ascii")
    chunks = [encoded[i:i + 4096] for i in range(0, len(encoded), 4096)]

    lines = [HEADER]
    lines.append("NSData *SCIEmbeddedMobileConfigSchemaData(void) {\n")
    lines.append("    static NSData *data = nil;\n")
    lines.append("    static dispatch_once_t onceToken;\n")
    lines.append("    dispatch_once(&onceToken, ^{\n")
    lines.append(f"        NSMutableString *b64 = [NSMutableString stringWithCapacity:{len(encoded)}];\n")
    for chunk in chunks:
        lines.append(f"        [b64 appendString:@\"{chunk}\"];\n")
    lines.append("        data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];\n")
    lines.append("    });\n")
    lines.append("    return data;\n")
    lines.append("}\n\n")
    lines.append("NSString *SCIEmbeddedMobileConfigSchemaName(void) {\n")
    lines.append(f"    return @\"{src.name} embedded ({len(data)} bytes)\";\n")
    lines.append("}\n")

    new_content = "".join(lines)
    if out.exists() and out.read_text(encoding="utf-8", errors="ignore") == new_content:
        print(f"[RyukGram][MCMapping] embedded schema already up to date: {src}")
        return 0
    out.write_text(new_content, encoding="utf-8")
    print(f"[RyukGram][MCMapping] embedded full schema: {src} -> {out} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
