#!/usr/bin/env python3
"""Generate SCIMCBrowser with a build-safe detail-controller instantiation.

The detail controller is intentionally private and declared later in the same
Objective-C translation unit. ARC rejects sending class/instance messages while
only a forward declaration is visible, so the generated copy instantiates it
through the Objective-C runtime and keeps the receiver typed as UIViewController.
"""

from __future__ import annotations

import pathlib
import sys


OLD_BLOCK = '''    SCIMCConfigDetailController *detail = [SCIMCConfigDetailController new];
    [detail setValue:result.configID forKey:@"cid"];
    if (result.kind == SCIMCBrowserResultParam) {
        [detail setValue:result.paramID forKey:@"focusParam"];
    }
    [self.navigationController pushViewController:detail animated:YES];'''

NEW_BLOCK = '''    Class detailClass = NSClassFromString(@"SCIMCConfigDetailController");
    UIViewController *detail = detailClass ? [detailClass new] : nil;
    if (!detail) return;
    [detail setValue:result.configID forKey:@"cid"];
    if (result.kind == SCIMCBrowserResultParam) {
        [detail setValue:result.paramID forKey:@"focusParam"];
    }
    [self.navigationController pushViewController:detail animated:YES];'''


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} INPUT OUTPUT", file=sys.stderr)
        return 2

    source = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    text = source.read_text(encoding="utf-8")

    count = text.count(OLD_BLOCK)
    if count != 1:
        print(
            f"expected exactly one detail-controller block in {source}, found {count}",
            file=sys.stderr,
        )
        return 1

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text.replace(OLD_BLOCK, NEW_BLOCK, 1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
