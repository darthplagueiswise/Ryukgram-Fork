#!/usr/bin/env python3
import sys, lief

PREFIXES = (b'RYG', b'ryg', b'_RYG', b'_ryg')

def base36(n):
    s = ""
    while True:
        n, r = divmod(n, 36)
        s = "0123456789abcdefghijklmnopqrstuvwxyz"[r] + s
        if n == 0:
            return s

def main(path):
    b = lief.parse(path)
    cn = next((s for seg in b.segments for s in seg.sections
               if s.name == "__objc_classname"), None)
    if cn is None:
        sys.exit("no __objc_classname")
    base, blob = cn.virtual_address, bytes(cn.content)
    data = bytearray(open(path, "rb").read())

    # names referenced as a literal anywhere outside __objc_classname -> leave readable
    def referenced_elsewhere(name):
        needle = name + b'\x00'
        i = data.find(needle)
        while i != -1:
            if (i < cn.offset or i >= cn.offset + len(blob)) and (i == 0 or data[i-1] == 0):
                return True
            i = data.find(needle, i + 1)
        return False

    n = renamed = skipped = 0
    off = 0
    while off < len(blob):
        end = blob.find(b'\x00', off)
        if end == -1:
            break
        name = blob[off:end]
        if name.startswith(PREFIXES):
            if referenced_elsewhere(name):
                skipped += 1
            else:
                new = b'_' + base36(n).encode()
                n += 1
                fpos = cn.offset + off
                data[fpos:fpos + len(name)] = new + b'\x00' * (len(name) - len(new))
                renamed += 1
        off = end + 1

    open(path, "wb").write(data)
    print(f"obfuscate-classes: renamed {renamed}, skipped {skipped} (string-referenced)")

if __name__ == "__main__":
    main(sys.argv[1])
