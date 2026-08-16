#!/usr/bin/env python3
"""
ig_symbol_diff.py — find every IG class / selector / ivar our tweak depends on and
check it against two IG binary versions, so a version bump's renames/removals surface
before they crash at runtime.

What it does
------------
1. Reverse-engineers an ObjC symbol index for each IG version from `ipsw class-dump`
   headers (Instagram + FBSharedFramework). Modern IG binaries use relative method
   lists, so `otool -ov` / `nm` can't recover method or ivar *names* — ipsw can.
2. Scrapes ./src for everything we reach into IG with: %hook targets, hooked method
   signatures, @interface decls (class + methods + property getters), NSClassFromString
   / objc_getClass / %c class refs, class_getInstanceVariable / MSHookIvar ivar names,
   MSHookMessageEx selectors, NSSelectorFromString / raw @selector(...) selectors,
   valueForKey: KVC keys, and swift _TtC mangled names.
3. Diffs each reference against the OLD and NEW index. The OLD version defines the
   "relevant universe": anything not present in OLD is Apple/UIKit/our-own and is
   dropped from the broken report automatically. Anything present in OLD and gone in
   NEW is what needs logging / fixing — printed with a best-guess rename suggestion.
4. Advisory pass for BEHAVIORAL breaks the symbol diff can't see — where IG keeps
   the class/method/selector we hook but routes through a NEW sibling type (e.g.
   v432 added IGProfileNavigation.IGBadgedNavigationButton and the profile header
   stopped rendering our injected old-style button, with zero symbols removed).
   Lists new IG classes that share >=2 CamelCase name-tokens with a specific class
   our source reaches into. Advisory only — does not affect the exit code.
5. Runtime-lookup lint: %hook / %c / NSClassFromString / objc_getClass resolve their
   EXACT literal at runtime — a bare name returns nil when the class is registered
   only under its Swift-mangled name (objc_getClass demangles mangled and dotted
   forms, never bare). Flagged against the NEW index alone, so it also catches
   breaks that predate the old version. A file that reaches the same class via a
   working spelling too (mangled-then-bare fallback, dual %hook) is not flagged.
   Run with just --new (no --old) to lint the current version standalone.
   CAVEAT — this lint is ADVISORY, not actionable: ipsw names a Swift class by its
   mangled `_TtC…` symbol, but an @objc-named Swift class registers under its BARE
   name at runtime, so a bare %hook resolves fine despite the mangled header. The
   static index can't distinguish the two, so this false-positives on every such
   class. ALWAYS verify with a boot-time NSClassFromString probe on device before
   changing a hook; NEVER switch a working bare %hook to the mangled name on the
   strength of this lint alone (doing so silently kills the hook).

Swift names: source reaches IG Swift classes via dotted "Module.Class" or bare
"Class"; ipsw emits mangled "_TtC<len>Module<len>Class". All three spellings are
bridged to one class so a Swift-class rename is neither missed nor false-flagged.
The bridge applies to declaration-style refs only — runtime lookups go through the
exact-literal lint above.

Coverage notes — an ObjC selector encodes its argument labels/count, so an
arg add/remove/rename changes the selector string and IS caught:
  * when the hooked class resolves under the same spelling in both versions ->
    the per-class method bucket flags it;
  * when the %hook keeps a bare name but the class is really reached via %init
    substitution / a mangled sibling (so the owner doesn't resolve in `old`) ->
    the method ref falls back to the binary-wide selector set: flagged iff the
    full selector existed in `old` and is gone from `new`. Category /
    protocol-extension methods (never in a class's own method list) still exist
    somewhere in the set, so they are NOT false-flagged.

What a diff structurally CANNOT catch: a hook that was already wrong BEFORE the
old baseline — the bad selector is absent from old AND new, so there is no delta
(e.g. our IGDirectThreadViewMetaAISummaryFeatureController init was hooked with
mutableStateProvider:, but the real selector has been stateProvider:/presenting:
since at least 431). Those surface only by inspecting the NEW class's method list
directly. A standing per-class "method missing" lint was tried and dropped: ipsw
AND otool both under-report (category, Swift protocol-extension, and some @objc
selectors live in no class method list — setNumLikes:/setStyledString: have no
real entry yet resolve at runtime), so "missing from class" is too false-positive
heavy to be actionable.

Also NOT caught: same-selector argument/return TYPE changes, selectors built from
variables (sel_registerName(var), macro names), and MSHookMessageEx selectors
checked binary-wide not per-hooked-class (the class literal beside them is covered
by the runtime-lookup lint).

--old/--new accept any of: an .ipa file, a folder of extracted IPA contents
(binaries found anywhere inside, symlinked — no copy), a dir already holding
Instagram + FBSharedFramework, or a bare version like 432 (auto-located in
wrapper/<v>.0.0.ipa or packages/<v>.0.0.ipa). Everything is staged under
/tmp/igdiff/<label> and cached. An empty/unresolvable input is a hard error,
never a silent 0-class index.

After each run the bulky staged binaries + header trees are pruned automatically
(only the tiny index.json is kept, so later runs of the same version are
instant); pass --keep-staged to retain them, --rebuild to force a fresh dump, or
--clean to wipe /tmp/igdiff entirely.

Usage
-----
    python3 scripts/ig_symbol_diff.py \
        --old /tmp/igdiff/431 --new /tmp/igdiff/432 --src ./src

Each --old/--new dir must contain the two binaries named `Instagram` and
`FBSharedFramework` (or pre-dumped `ig-hdr/` and `fb-hdr/` header trees). Missing
header trees are produced on demand via `ipsw class-dump` and cached as index.json.
"""

import argparse
import difflib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile

# ---------------------------------------------------------------------------
# binary -> header tree -> parsed index
# ---------------------------------------------------------------------------

BIN_NAMES = ("Instagram", "FBSharedFramework")
HDR_DIRS = {"Instagram": "ig-hdr", "FBSharedFramework": "fb-hdr"}
IPA_MEMBERS = {
    "Instagram": "Payload/Instagram.app/Instagram",
    "FBSharedFramework":
        "Payload/Instagram.app/Frameworks/FBSharedFramework.framework/FBSharedFramework",
}
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE_ROOT = "/tmp/igdiff"


# ---------------------------------------------------------------------------
# Swift class-name forms
# ---------------------------------------------------------------------------
# IG's Swift classes appear three ways and we must treat them as ONE class:
#   mangled  _TtC24IGProfileNavigationSwift29IGProfileNavigationHeaderView
#   dotted   IGProfileNavigationSwift.IGProfileNavigationHeaderView   (runtime / objc_getClass)
#   bare     IGProfileNavigationHeaderView                            (some @interface decls)
# ipsw class-dump emits the mangled form; our source reaches in via dotted/bare.
# Without bridging, every Swift-class ref falls outside the "old universe" and
# can be neither flagged-when-removed (false negative) nor cleared-when-present
# (false positive, e.g. IGBadgedNavigationButton).

def _demangle_ttc(name):
    """_TtC<len><id><len><id>… -> [components] (>=2), else None."""
    if not name.startswith("_TtC"):
        return None
    rest = name[4:]
    parts, i = [], 0
    while i < len(rest):
        j = i
        while j < len(rest) and rest[j].isdigit():
            j += 1
        if j == i:
            break
        ln = int(rest[i:j])
        comp = rest[j:j + ln]
        if len(comp) != ln:
            return None
        parts.append(comp)
        i = j + ln
    return parts if len(parts) >= 2 else None


def class_forms(name):
    """All equivalent spellings of a class name (mangled / dotted / bare)."""
    forms = {name}
    if name.startswith("_TtC"):
        parts = _demangle_ttc(name)
        if parts:
            module, cls = parts[0], parts[-1]
            forms.add("%s.%s" % (module, cls))
            forms.add(cls)
    elif "." in name:
        module, cls = name.split(".", 1)
        forms.add(cls.split(".")[-1])
        if "." not in cls:                      # only re-mangle simple Module.Class
            forms.add("_TtC%d%s%d%s" % (len(module), module, len(cls), cls))
    return forms


def dotted_name(name):
    """Mangled _TtC… -> 'Module.Class'; dotted/bare pass through."""
    if name.startswith("_TtC"):
        parts = _demangle_ttc(name)
        if parts:
            return ".".join(parts)
    return name


# Added-class scan: most version bumps add 500+ classes, almost all GraphQL/
# codegen noise. We surface only NEW IG classes whose CamelCase tokens overlap a
# class our source already reaches into — that's where a behavioral break hides
# (IG keeps the old class/selector but routes through a new sibling type, like
# IGBadgedNavigationButton replacing the profile-nav button in v432).
_ADDED_NOISE = re.compile(
    r'(Fragment|AnyModel|__Shadow_DO_NOT_USE|Builder|Response$|Mutation|'
    r'Subscription|QueryResponse|PandoModel|GraphQL|DataClass|TreeModel|InputData)')
_TOKEN_STOP = {"View", "Type", "Controller", "ViewController", "Manager", "Cell",
               "Model", "Swift", "Button", "Helper", "Section", "SectionController",
               "Data", "Source", "Config", "Item", "Handler", "Delegate", "Protocol"}


def class_tokens(name):
    flat = dotted_name(name).replace(".", "")
    parts = re.findall(r'[A-Z][a-z0-9]+|[A-Z]+(?![a-z])', flat)
    return {p for p in parts if len(p) >= 5 and p not in _TOKEN_STOP}

RE_IFACE = re.compile(r'@interface\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_]\w*))?')
RE_CATEGORY = re.compile(r'@interface\s+[A-Za-z_]\w*\s*\(')
RE_PROTOCOL = re.compile(r'@protocol\s+([A-Za-z_]\w*)')
RE_METHOD = re.compile(r'^\s*[-+]\s*\([^)]*\)\s*(.+?)\s*[;{]\s*$')
RE_PROPERTY = re.compile(r'@property\b(?:\s*\([^)]*\))?\s+.*?\b([A-Za-z_]\w*)\s*;')
RE_IVAR_LINE = re.compile(r'^\s*[A-Za-z_][\w<>\s\*,]*?\b(_?[A-Za-z_]\w*)\s*;\s*$')


def selector_from_decl(decl):
    """'foo:(id)a bar:(id)b' -> 'foo:bar:'  ;  'authHeader' -> 'authHeader'."""
    decl = decl.strip()
    labels = re.findall(r'([A-Za-z_]\w*)\s*:', decl)
    if labels:
        return "".join(l + ":" for l in labels)
    m = re.match(r'([A-Za-z_]\w*)', decl)
    return m.group(1) if m else None


def run_ipsw_dump(binary, out_dir):
    if not os.path.exists(binary):
        return False
    subprocess.run(
        ["ipsw", "class-dump", "--headers", "-o", out_dir, binary],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    return os.path.isdir(out_dir)


def parse_header_file(path, classes):
    """classes: {name: {'super':str, 'methods':set, 'ivars':set, 'kind':'class'|'protocol'}}"""
    try:
        with open(path, "r", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return

    cur = None          # current class/protocol name
    in_ivars = False
    for line in lines:
        s = line.rstrip("\n")

        mi = RE_IFACE.match(s.strip())
        if mi and not RE_CATEGORY.match(s.strip()):
            cur = mi.group(1)
            entry = classes.setdefault(cur, {"super": mi.group(2) or "",
                                             "methods": set(), "ivars": set(),
                                             "kind": "class"})
            if mi.group(2):
                entry["super"] = mi.group(2)
            entry["kind"] = "class"
            in_ivars = "{" in s
            continue

        mp = RE_PROTOCOL.match(s.strip())
        if mp:
            cur = mp.group(1)
            classes.setdefault(cur, {"super": "", "methods": set(),
                                     "ivars": set(), "kind": "protocol"})
            in_ivars = False
            continue

        if cur is None:
            continue
        entry = classes[cur]

        if in_ivars:
            if "}" in s:
                in_ivars = False
                continue
            if "/* instance variables */" in s:
                continue
            mv = RE_IVAR_LINE.match(s)
            if mv:
                entry["ivars"].add(mv.group(1))
            continue
        if "{" in s and entry["kind"] == "class" and "@interface" not in s:
            # ivar brace can open on its own line after the @interface
            in_ivars = True
            continue

        mprop = RE_PROPERTY.search(s)
        if mprop:
            entry["methods"].add(mprop.group(1))           # getter selector
            continue

        mm = RE_METHOD.match(s)
        if mm:
            sel = selector_from_decl(mm.group(1))
            if sel:
                entry["methods"].add(sel)


def build_index(version_dir, force=False):
    """Returns dict: {classes, all_classes:set, all_selectors:set, all_ivars:set}."""
    cache = os.path.join(version_dir, "index.json")
    if os.path.exists(cache) and not force:
        with open(cache) as fh:
            raw = json.load(fh)
        return _inflate(raw)

    classes = {}
    for bname in BIN_NAMES:
        hdr = os.path.join(version_dir, HDR_DIRS[bname])
        if not os.path.isdir(hdr):
            binary = os.path.join(version_dir, bname)
            print(f"[*] dumping {bname} headers (ipsw class-dump, slow on main bin)…",
                  file=sys.stderr)
            if not run_ipsw_dump(binary, hdr):
                print(f"[!] no headers and no binary for {bname} in {version_dir}",
                      file=sys.stderr)
                continue
        for root, _dirs, files in os.walk(hdr):
            for f in files:
                if f.endswith(".h"):
                    parse_header_file(os.path.join(root, f), classes)

    if not classes:
        sys.exit("[FATAL] indexed 0 classes from %s — no binaries/headers there. "
                 "Pass a version number (e.g. 432) to auto-stage, or a dir holding "
                 "Instagram + FBSharedFramework." % version_dir)

    idx = _finalize(classes)
    with open(cache, "w") as fh:
        json.dump(_deflate(idx), fh)
    return idx


def _finalize(classes):
    all_sel, all_iv = set(), set()
    form_to_key = {}
    for name, c in classes.items():
        all_sel |= c["methods"]
        all_iv |= c["ivars"]
        for f in class_forms(name):
            form_to_key.setdefault(f, name)
    return {
        "classes": classes,
        "all_classes": set(classes.keys()),
        "form_to_key": form_to_key,        # any spelling -> canonical header key
        "all_selectors": all_sel,
        "all_ivars": all_iv,
    }


def _deflate(idx):
    return {
        "classes": {k: {"super": v["super"], "kind": v["kind"],
                        "methods": sorted(v["methods"]), "ivars": sorted(v["ivars"])}
                    for k, v in idx["classes"].items()},
    }


def _inflate(raw):
    classes = {k: {"super": v["super"], "kind": v["kind"],
                   "methods": set(v["methods"]), "ivars": set(v["ivars"])}
               for k, v in raw["classes"].items()}
    return _finalize(classes)


# ---------------------------------------------------------------------------
# source scraping
# ---------------------------------------------------------------------------

SRC_EXT = (".x", ".xm", ".m", ".h", ".mm")

RE_SRC_HOOK = re.compile(r'%hook\s+([A-Za-z_][\w.]*\w)')
RE_SRC_END = re.compile(r'%end\b')
RE_SRC_NEW = re.compile(r'%new\b')
RE_SRC_NSCLASS = re.compile(r'NSClassFromString\(@"([^"]+)"\)')
RE_SRC_GETCLASS = re.compile(r'objc_getClass\("([^"]+)"\)')
RE_SRC_PCT_C = re.compile(r'%c\(([A-Za-z_]\w*)\)')
RE_SRC_IVAR = re.compile(r'(?:class_getInstanceVariable|object_getInstanceVariable|class_getInstanceMethod)\([^,]+,\s*"([^"]+)"')
RE_SRC_IVAR2 = re.compile(r'ivar\w*\s*=\s*class_getInstanceVariable\([^,]+,\s*"([^"]+)"')
RE_SRC_MSHOOK = re.compile(r'MSHookMessageEx\(')
RE_SRC_SELECTOR = re.compile(r'@selector\(([^)]+)\)')
RE_SRC_SELSTR = re.compile(r'NSSelectorFromString\(@"([^"]+)"\)')
RE_SRC_MSHOOKIVAR = re.compile(r'MSHookIvar<[^>]*>\([^,]+,\s*"([^"]+)"')
# ivar names passed through helper wrappers, e.g. rygObjIvar(obj, "_x")
RE_SRC_IVARHELPER = re.compile(r'\b\w*Ivar\w*\(\s*[^,()]+,\s*"(_[A-Za-z0-9_]+)"\s*[,)]')
RE_SRC_KVC = re.compile(r'alueForKey:@"([^"]+)"')
RE_SRC_SWIFT = re.compile(r'(_TtC\d+[A-Za-z0-9_]+)')
RE_SRC_IFACE = re.compile(r'@interface\s+([A-Za-z_]\w*)')
RE_SRC_METHOD = re.compile(r'^\s*[-+]\s*\([^)]*\)\s*(.+?)\s*[;{]')


class Ref:
    __slots__ = ("kind", "name", "owner", "file", "line", "runtime")

    def __init__(self, kind, name, owner, file, line, runtime=False):
        self.kind = kind        # class | method | ivar | selector | kvc
        self.name = name
        self.owner = owner      # owning class for method refs, else None
        self.file = file
        self.line = line
        self.runtime = runtime  # class ref resolved by exact literal at runtime


def scrape_source(srcdir):
    refs = []
    for root, _dirs, files in os.walk(srcdir):
        for f in files:
            if not f.endswith(SRC_EXT):
                continue
            path = os.path.join(root, f)
            _scrape_file(path, refs)
    return refs


def _scrape_file(path, refs):
    rel = path
    try:
        with open(path, "r", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return

    hook_class = None       # current %hook context
    iface_class = None      # current @interface context (headers)
    prev_new = False        # previous line was %new -> skip next method (it's ours)

    for n, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")

        # class references — %hook/%c/NSClassFromString/objc_getClass resolve the
        # exact literal at runtime (bare Swift names return nil there)
        m = RE_SRC_HOOK.search(line)
        if m:
            hook_class = m.group(1)
            iface_class = None
            refs.append(Ref("class", hook_class, None, rel, n, runtime=True))
            continue
        if RE_SRC_END.search(line):
            hook_class = None
        for m in RE_SRC_NSCLASS.finditer(line):
            refs.append(Ref("class", m.group(1), None, rel, n, runtime=True))
        for m in RE_SRC_GETCLASS.finditer(line):
            refs.append(Ref("class", m.group(1), None, rel, n, runtime=True))
        for m in RE_SRC_PCT_C.finditer(line):
            refs.append(Ref("class", m.group(1), None, rel, n, runtime=True))
        for m in RE_SRC_SWIFT.finditer(line):
            refs.append(Ref("class", m.group(1), None, rel, n))

        # @interface context (declared IG classes + their methods)
        mi = RE_SRC_IFACE.search(line)
        if mi and "(" not in line.split("@interface", 1)[1].split(":")[0]:
            iface_class = mi.group(1)
            hook_class = None
            refs.append(Ref("class", iface_class, None, rel, n))

        # ivar name strings
        for rx in (RE_SRC_IVAR, RE_SRC_IVAR2, RE_SRC_MSHOOKIVAR, RE_SRC_IVARHELPER):
            for m in rx.finditer(line):
                refs.append(Ref("ivar", m.group(1), None, rel, n))

        # selector strings + KVC keys
        for m in RE_SRC_SELSTR.finditer(line):
            refs.append(Ref("selector", m.group(1).strip(), None, rel, n))
        for m in RE_SRC_KVC.finditer(line):
            refs.append(Ref("kvc", m.group(1), None, rel, n))

        # MSHookMessageEx selector + inline class
        if RE_SRC_MSHOOK.search(line):
            ms = RE_SRC_SELECTOR.search(line)
            if ms:
                refs.append(Ref("selector", ms.group(1).strip(), None, rel, n))

        # method decls inside %hook / @interface
        owner = hook_class or iface_class
        if owner:
            mm = RE_SRC_METHOD.match(line)
            if mm and not prev_new:
                sel = selector_from_decl(mm.group(1))
                if sel and sel not in ("init", "dealloc"):
                    refs.append(Ref("method", sel, owner, rel, n))

        # raw selectors (low-priority global check) — skip MSHook (already added)
        elif not RE_SRC_MSHOOK.search(line):
            for m in RE_SRC_SELECTOR.finditer(line):
                refs.append(Ref("selector", m.group(1).strip(), None, rel, n))

        prev_new = bool(RE_SRC_NEW.search(line))


# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

def suggest(name, pool, n=3, cutoff=0.7):
    return difflib.get_close_matches(name, pool, n=n, cutoff=cutoff)


def resolve_class_key(idx, name):
    """Canonical header key for any spelling of `name` (mangled/dotted/bare), else None."""
    if not name:
        return None
    if name in idx["classes"]:
        return name
    f2k = idx["form_to_key"]
    for f in class_forms(name):
        k = f2k.get(f)
        if k:
            return k
    return None


def class_present(idx, name):
    return resolve_class_key(idx, name) is not None


def method_in_chain(idx, cls, sel):
    """True if `sel` is implemented on `cls` or any superclass in this version."""
    seen = set()
    cur = resolve_class_key(idx, cls)
    while cur and cur not in seen:
        seen.add(cur)
        c = idx["classes"][cur]
        if sel in c["methods"]:
            return True
        cur = resolve_class_key(idx, c["super"]) if c["super"] else None
    return False


def ivar_in_chain(idx, cls, name):
    """True if ivar `name` is declared on `cls` or any superclass in this version."""
    seen = set()
    cur = resolve_class_key(idx, cls)
    while cur and cur not in seen:
        seen.add(cur)
        c = idx["classes"][cur]
        if name in c["ivars"]:
            return True
        cur = resolve_class_key(idx, c["super"]) if c["super"] else None
    return False


def classes_with_ivar(idx, name):
    """Classes in this version that declare ivar `name` (where it may have moved)."""
    return sorted(k for k, c in idx["classes"].items() if name in c["ivars"])


def kvc_resolvable(idx, key):
    """valueForKey: hits a getter or a `key`/`_key` ivar."""
    return (key in idx["all_selectors"] or key in idx["all_ivars"]
            or ("_" + key) in idx["all_ivars"])


def lookup_ok(idx, name):
    """Would objc_getClass(name) / %c(name) find the class at runtime?

    The runtime demangles mangled and dotted spellings; a bare spelling resolves
    only when it IS the registered name (plain ObjC class, or @objc(name) alias —
    either way the header key equals the bare name).
    """
    if name.startswith("_TtC") or "." in name:
        return class_present(idx, name)
    return resolve_class_key(idx, name) == name


def runtime_check(refs, idx):
    """Runtime class lookups whose literal returns nil although the class exists.

    Grouped per (file, class): a file that also reaches the class through a
    working spelling (mangled-then-bare fallback chain, dual %hook for old/new IG)
    is intentionally covered and not flagged. Suggestion = the registered name.
    """
    groups = {}
    for r in refs:
        if r.kind != "class" or not r.runtime:
            continue
        key = resolve_class_key(idx, r.name)
        if key is None:
            continue        # not in this IG version at all — diff buckets own that
        groups.setdefault((r.file, key), []).append(r)

    broken = []
    for (_f, key), grp in sorted(groups.items()):
        if any(lookup_ok(idx, g.name) for g in grp):
            continue
        names = set()
        for g in grp:
            if g.name not in names:
                names.add(g.name)
                broken.append((g, [key]))
    return broken


def diff(refs, old, new):
    broken_class, broken_method, broken_ivar, broken_selector, broken_kvc = [], [], [], [], []
    seen = set()

    for r in refs:
        key = (r.kind, r.name, r.owner)
        if key in seen:
            continue
        seen.add(key)

        if r.kind == "class":
            if class_present(old, r.name) and not class_present(new, r.name):
                broken_class.append((r, suggest(r.name, new["all_classes"])))

        elif r.kind == "method":
            ok = resolve_class_key(old, r.owner)
            if ok and method_in_chain(old, ok, r.name):
                # owner resolves in old under this spelling — precise per-class check
                nk = resolve_class_key(new, r.owner)
                if nk is None:
                    continue        # class itself gone -> reported at class level
                if not method_in_chain(new, nk, r.name):
                    sug = suggest(r.name, new["classes"][nk]["methods"]) or \
                        suggest(r.name, new["all_selectors"])
                    broken_method.append((r, sug))
            else:
                # Owner doesn't resolve in old under the %hook spelling — the class
                # is reached via %init substitution / a mangled sibling, so the
                # per-class check can't see it. Fall back to the binary-wide
                # selector set: a real rename makes the full selector vanish
                # everywhere, while category / protocol-extension methods (which
                # never appear in a class's own method list) still exist somewhere
                # and so are NOT false-flagged.
                if r.name in old["all_selectors"] and r.name not in new["all_selectors"]:
                    broken_method.append((r, suggest(r.name, new["all_selectors"])))

        elif r.kind == "ivar":
            if r.name in old["all_ivars"] and r.name not in new["all_ivars"]:
                broken_ivar.append((r, suggest(r.name, new["all_ivars"])))

        elif r.kind == "selector":
            if r.name in old["all_selectors"] and r.name not in new["all_selectors"]:
                broken_selector.append((r, suggest(r.name, new["all_selectors"])))

        elif r.kind == "kvc":
            if kvc_resolvable(old, r.name) and not kvc_resolvable(new, r.name):
                broken_kvc.append((r, suggest(r.name, new["all_selectors"])))

    return broken_class, broken_method, broken_ivar, broken_selector, broken_kvc


def perclass_ivar_loss(refs, old, new):
    """Ivars we read that vanished from THEIR class even though the name survives
    elsewhere in the binary — the blind spot of the global `all_ivars` check.

    An ivar read (`rygIvar(obj, "_x")`, MSHookIvar, class_getInstanceVariable) has
    no class literal at the call site, so it's tied to a class by co-location:
    a file that names class C (via %hook/%c/NSClassFromString/@interface) and reads
    ivar `_x` is treated as reading `_x` off C. We flag only when `_x` was on C's
    chain in old and is gone from C's chain in new — so unrelated ivars in the same
    file self-filter, and a name still present on C (just moved up a super) doesn't
    false-fire. Suggestion points at the 434 class that now owns the ivar.
    """
    class_files = {}                       # class name -> {files that name it}
    for r in refs:
        if r.kind == "class":
            class_files.setdefault(r.name, set()).add(r.file)

    file_ivars = {}                        # file -> {ivar name -> representative ref}
    for r in refs:
        if r.kind == "ivar":
            file_ivars.setdefault(r.file, {}).setdefault(r.name, r)

    out, seen = [], set()
    for cname, files in class_files.items():
        ok = resolve_class_key(old, cname)
        if not ok:
            continue                       # not an IG class in old — our own / Apple
        nk = resolve_class_key(new, cname)
        if not nk:
            continue                       # class fully gone — runtime-dead/broken-class own it
        for f in files:
            for ivname, ref in file_ivars.get(f, {}).items():
                if (ok, ivname) in seen:   # canonical key collapses bare + mangled spellings
                    continue
                if not ivar_in_chain(old, ok, ivname):
                    continue               # ivar wasn't on this class in old — not ours to claim
                if ivar_in_chain(new, nk, ivname):
                    continue               # still there in new — fine
                seen.add((ok, ivname))
                sug = suggest(ivname, new["classes"][nk]["ivars"])
                holders = classes_with_ivar(new, ivname)
                if holders:
                    sug = sug + ["now on %s" % dotted_name(holders[0])]
                out.append((Ref("ivar", ivname, cname, ref.file, ref.line), sug))
    return out


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

def hl(s):  # bold
    return f"\033[1m{s}\033[0m" if sys.stdout.isatty() else s


def red(s):
    return f"\033[31m{s}\033[0m" if sys.stdout.isatty() else s


def grn(s):
    return f"\033[32m{s}\033[0m" if sys.stdout.isatty() else s


def yel(s):
    return f"\033[33m{s}\033[0m" if sys.stdout.isatty() else s


def print_overview(old, new, old_label, new_label):
    removed = sorted(old["all_classes"] - new["all_classes"])
    added = sorted(new["all_classes"] - old["all_classes"])
    ig_removed = [c for c in removed if c.startswith(("IG", "_Tt"))]
    ig_added = [c for c in added if c.startswith(("IG", "_Tt"))]
    print(hl(f"\n══ overview  {old_label} → {new_label} ══"))
    print(f"  classes: {len(old['all_classes'])} → {len(new['all_classes'])}  "
          f"({grn('+%d' % len(added))} / {red('-%d' % len(removed))})")
    print(f"  IG-prefixed removed: {len(ig_removed)}   added: {len(ig_added)}")
    print(f"  selectors: {len(old['all_selectors'])} → {len(new['all_selectors'])}")
    print(f"  ivars:     {len(old['all_ivars'])} → {len(new['all_ivars'])}")


def print_bucket(title, items, old, new):
    if not items:
        print(grn(f"\n✔ {title}: none"))
        return
    print(red(hl(f"\n>> {title}: {len(items)}")))
    for r, sug in sorted(items, key=lambda x: (x[0].owner or "", x[0].name)):
        loc = f"{r.file}:{r.line}"
        owner = f"{r.owner} " if r.owner else ""
        s = f"  {red('✗')} {hl(owner + r.name)}"
        if sug:
            s += yel(f"   →? {', '.join(sug)}")
        print(s)
        print(f"      {loc}")


def _has_index(d):
    return os.path.exists(os.path.join(d, "index.json"))


def _can_build(d):
    """True if `d` holds what build_index needs from scratch: headers or binaries."""
    if any(os.path.isdir(os.path.join(d, h)) for h in HDR_DIRS.values()):
        return True
    return any(os.path.exists(os.path.join(d, b)) for b in BIN_NAMES)


def _dir_has_inputs(d):
    return os.path.isdir(d) and (_has_index(d) or _can_build(d))


def _under_stage(d):
    return os.path.abspath(d).startswith(os.path.abspath(STAGE_ROOT) + os.sep)


def prune_stage(version_dir):
    """Drop the bulky staged binaries + header trees, keep the tiny index.json.

    Only touches dirs we own under /tmp/igdiff — never a user-supplied tree.
    index.json is all the diff needs on later runs, so this is loss-free for
    everything except --rebuild (which re-stages on demand).
    """
    if not _under_stage(version_dir):
        return 0
    freed = 0
    for b in BIN_NAMES:                       # symlink (extracted-folder) or copy (.ipa)
        p = os.path.join(version_dir, b)
        if os.path.lexists(p):
            try:
                freed += 0 if os.path.islink(p) else os.path.getsize(p)
                os.remove(p)
            except OSError:
                pass
    for h in HDR_DIRS.values():
        d = os.path.join(version_dir, h)
        if os.path.isdir(d):
            shutil.rmtree(d, ignore_errors=True)
    for f in os.listdir(version_dir) if os.path.isdir(version_dir) else []:
        if f.endswith(".a2s"):                # ipsw disassembly cache
            try:
                os.remove(os.path.join(version_dir, f))
            except OSError:
                pass
    return freed


# suffix match so we tolerate any *.app / framework folder naming inside the IPA
_MEMBER_SUFFIX = {
    "Instagram": ".app/Instagram",
    "FBSharedFramework": "FBSharedFramework.framework/FBSharedFramework",
}
_GENERIC_DIRS = {"Payload", "Frameworks", "build", "build-dist", ""}


def _major_version(vstr):
    m = re.match(r'(\d+)', vstr or "")
    return m.group(1) if m else None


def _label_from_ipa(ipa):
    """True IG version (major) from the app Info.plist inside an .ipa, else None."""
    try:
        with zipfile.ZipFile(ipa) as z:
            member = next((n for n in z.namelist()
                           if n.endswith(".app/Info.plist") and n.count("/") == 2), None)
            if member:
                d = plistlib.loads(z.read(member))
                return _major_version(d.get("CFBundleShortVersionString"))
    except Exception:
        pass
    return None


def _label_from_tree(root):
    """True IG version (major) from an extracted-IPA tree's app Info.plist, else None."""
    for dirpath, _dirs, files in os.walk(root):
        if dirpath.endswith(".app") and "Info.plist" in files:
            try:
                with open(os.path.join(dirpath, "Info.plist"), "rb") as fh:
                    return _major_version(plistlib.load(fh).get("CFBundleShortVersionString"))
            except Exception:
                return None
    return None


def _derive_label(path):
    """Fallback stage-dir name when no Info.plist version is available."""
    p = os.path.abspath(path.rstrip("/"))
    base = re.sub(r'\.ipa$', '', os.path.basename(p), flags=re.I)
    while base in _GENERIC_DIRS or base.endswith(".app") or base.endswith(".framework"):
        p = os.path.dirname(p)
        base = re.sub(r'\.ipa$', '', os.path.basename(p), flags=re.I)
        if p in ("/", ""):
            break
    m = re.match(r'(\d+)', base)
    return m.group(1) if m else (base or "input")


def _find_ipa(ver):
    for sub in ("wrapper", "packages"):
        p = os.path.join(REPO_ROOT, sub, "%s.0.0.ipa" % ver)
        if os.path.exists(p):
            return p
    return None


def _find_binaries_in_tree(root):
    """Locate Instagram + FBSharedFramework machos anywhere under an extracted IPA."""
    found = {}
    for dirpath, _dirs, files in os.walk(root):
        for b in BIN_NAMES:
            if b in found:
                continue
            p = os.path.join(dirpath, b)
            if b in files and os.path.isfile(p) and p.endswith(_MEMBER_SUFFIX[b]):
                found[b] = p
        if len(found) == len(BIN_NAMES):
            break
    return found


def _stage_from_ipa(ipa, dest):
    os.makedirs(dest, exist_ok=True)
    got = []
    with zipfile.ZipFile(ipa) as z:
        names = z.namelist()
        for out, suffix in _MEMBER_SUFFIX.items():
            member = next((n for n in names if n.endswith(suffix) and not n.endswith("/")), None)
            if member:
                with z.open(member) as src, open(os.path.join(dest, out), "wb") as fh:
                    shutil.copyfileobj(src, fh)
                got.append(out)
    return got


def _link_binaries(found, dest):
    """Symlink located binaries into a stage dir — no 290MB copy; ipsw reads links."""
    os.makedirs(dest, exist_ok=True)
    got = []
    for b, src in found.items():
        link = os.path.join(dest, b)
        if os.path.lexists(link):
            try:
                os.remove(link)
            except OSError:
                pass
        try:
            os.symlink(os.path.abspath(src), link)
        except OSError:
            shutil.copy2(src, link)
        got.append(b)
    return got


def resolve_version_dir(spec, rebuild=False):
    """Resolve --old/--new to a dir holding Instagram + FBSharedFramework.

    Accepts, in order: an .ipa file, an extracted-IPA folder (binaries found
    anywhere inside), a pre-staged dir (binaries/headers/index.json at top), or a
    bare version like 432 (auto-located in wrapper/ or packages/). Always errors
    loudly rather than producing an empty index.

    A cached index.json alone is enough unless rebuild — then we re-stage the
    binaries so headers can be dumped fresh (prune_stage may have removed them).
    """
    def need_stage(dest):
        # skip staging only when the cached index is usable as-is
        return rebuild or (not _has_index(dest) and not _can_build(dest))

    # 1. .ipa file
    if os.path.isfile(spec) and spec.lower().endswith(".ipa"):
        label = _label_from_ipa(spec) or _derive_label(spec)
        dest = os.path.join(STAGE_ROOT, label)
        if need_stage(dest) and not _can_build(dest):
            print("[*] staging %s from %s …" % (label, spec), file=sys.stderr)
            if not _stage_from_ipa(spec, dest):
                sys.exit("[FATAL] %s has no Instagram/FBSharedFramework members." % spec)
        return dest

    # 2. directory
    if os.path.isdir(spec):
        if _dir_has_inputs(spec):
            return spec
        found = _find_binaries_in_tree(spec)
        if found:
            label = _label_from_tree(spec) or _derive_label(spec)
            dest = os.path.join(STAGE_ROOT, label)
            if need_stage(dest) and not _can_build(dest):
                missing = [b for b in BIN_NAMES if b not in found]
                if missing:
                    print("[!] %s: found %s but not %s — index may miss data-layer "
                          "classes" % (spec, ",".join(found), ",".join(missing)),
                          file=sys.stderr)
                print("[*] staging %s from extracted tree %s …" % (label, spec),
                      file=sys.stderr)
                _link_binaries(found, dest)
            return dest

    # 3. bare version -> repo IPA
    ver = os.path.basename(spec.rstrip("/"))
    staged = os.path.join(STAGE_ROOT, ver)
    if not need_stage(staged):
        return staged
    if not _can_build(staged):
        ipa = _find_ipa(ver)
        if ipa:
            print("[*] staging %s from %s …" % (ver, os.path.relpath(ipa, REPO_ROOT)),
                  file=sys.stderr)
            if not _stage_from_ipa(ipa, staged):
                sys.exit("[FATAL] %s has no Instagram/FBSharedFramework members." % ipa)
            return staged
        if not _has_index(staged):
            sys.exit("[FATAL] can't resolve '%s'. Pass an .ipa file, a folder of "
                     "extracted IPA contents, a dir with Instagram+FBSharedFramework, "
                     "or a version (needs wrapper/%s.0.0.ipa or packages/%s.0.0.ipa)."
                     % (spec, ver, ver))
    return staged


def resolve_src(spec):
    if os.path.isdir(spec):
        return spec
    alt = os.path.join(REPO_ROOT, "src")
    if os.path.isdir(alt):
        print("[*] '%s' not found from cwd — using %s" % (spec, alt), file=sys.stderr)
        return alt
    sys.exit("[FATAL] source tree '%s' not found (and no %s)." % (spec, alt))


def added_class_report(refs, old, new, limit, show_all, min_score=2):
    """Advisory: new IG classes that closely resemble a SPECIFIC class we hook.

    Scored per-surface, not against a pooled token set — a global pool makes
    generic tokens (Direct/Message/Overlay) match everything. We keep a new
    class only if it shares >=min_score tokens with one individual surface class,
    i.e. it looks like a sibling/replacement of something we already reach into.
    """
    added = new["all_classes"] - old["all_classes"]
    surfaces = {}                       # canonical surface name -> its token set
    for r in refs:
        nm = r.name if r.kind == "class" else (r.owner if r.kind == "method" else None)
        if not nm or not (nm.startswith(("IG", "_TtC")) or "." in nm):
            continue
        toks = class_tokens(nm)
        if len(toks) >= 2:              # 1-token anchors can't reach min_score
            surfaces.setdefault(dotted_name(nm), toks)

    hits, rest = [], 0
    for c in added:
        if not c.startswith(("IG", "_TtC")):
            continue
        d = dotted_name(c)
        if _ADDED_NOISE.search(d):
            continue
        ctoks = class_tokens(c)
        best_n, best_surf, best_shared = 0, None, set()
        for sname, stoks in surfaces.items():
            shared = ctoks & stoks
            if len(shared) > best_n:
                best_n, best_surf, best_shared = len(shared), sname, shared
        if best_n >= min_score:
            hits.append((best_n, d, best_surf, sorted(best_shared)))
        else:
            rest += 1
    hits.sort(key=lambda x: (-x[0], x[1]))

    print(hl("\n══ NEW IG classes near your hook surfaces (possible behavioral break) ══"))
    if not hits:
        print(grn("  none"))
    else:
        for score, d, surf_name, sh in hits[:limit]:
            print(f"  {yel('+')} {hl(d)}")
            print(f"      ↔ {surf_name}  ({', '.join(sh)})")
        if len(hits) > limit:
            print(f"  … {len(hits) - limit} more (raise --added-limit)")
    note = "; --added-all to dump" if not show_all else ""
    print(f"  ({rest} other new IG classes share no token with your surfaces{note})")
    if show_all:
        for c in sorted({dotted_name(x) for x in added
                         if x.startswith(("IG", "_TtC")) and not _ADDED_NOISE.search(dotted_name(x))}):
            print("    " + c)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--old",
                    help="old version — any of: an .ipa file, a folder of extracted "
                         "IPA contents, a dir with Instagram+FBSharedFramework, or a "
                         "bare version like 431 (found in wrapper/ or packages/). "
                         "Omit to lint runtime lookups against --new alone")
    ap.add_argument("--new",
                    help="new version — same forms as --old (e.g. 432, or path/to.ipa)")
    ap.add_argument("--src", default="./src", help="tweak source tree (default ./src)")
    ap.add_argument("--old-label", default=None)
    ap.add_argument("--new-label", default=None)
    ap.add_argument("--rebuild", action="store_true", help="ignore cached index.json")
    ap.add_argument("--json", metavar="FILE", help="also write machine-readable report")
    ap.add_argument("--added-limit", type=int, default=40,
                    help="max rows in the NEW-classes-near-surfaces report (default 40)")
    ap.add_argument("--added-all", action="store_true",
                    help="also dump every noise-filtered new IG class")
    ap.add_argument("--keep-staged", action="store_true",
                    help="keep staged binaries + header trees (default: prune them, "
                         "keeping only the tiny index.json for fast re-runs)")
    ap.add_argument("--clean", action="store_true",
                    help="wipe %s entirely and exit" % STAGE_ROOT)
    args = ap.parse_args()

    if args.clean:
        if os.path.isdir(STAGE_ROOT):
            shutil.rmtree(STAGE_ROOT, ignore_errors=True)
            print("[*] removed %s" % STAGE_ROOT, file=sys.stderr)
        else:
            print("[*] nothing to clean (%s absent)" % STAGE_ROOT, file=sys.stderr)
        return 0

    if not args.new:
        ap.error("--new is required (unless --clean); --old too for a version diff, "
                 "omit it to lint runtime lookups against --new alone")

    new_label = args.new_label or os.path.basename(args.new.rstrip("/"))
    args.new = resolve_version_dir(args.new, rebuild=args.rebuild)
    args.src = resolve_src(args.src)

    old_label, old = None, None
    if args.old:
        old_label = args.old_label or os.path.basename(args.old.rstrip("/"))
        args.old = resolve_version_dir(args.old, rebuild=args.rebuild)
        print(f"[*] indexing {old_label} …", file=sys.stderr)
        old = build_index(args.old, force=args.rebuild)

    print(f"[*] indexing {new_label} …", file=sys.stderr)
    new = build_index(args.new, force=args.rebuild)
    print(f"[*] scraping {args.src} …", file=sys.stderr)
    refs = scrape_source(args.src)

    rc = runtime_check(refs, new)
    # ADVISORY, not actionable: ipsw names a Swift class by its mangled `_TtC…` symbol,
    # but an @objc-named Swift class registers under its BARE name at runtime — so a
    # bare %hook resolves fine even though the header is mangled. The static index
    # can't tell the two apart, so this lint false-positives on every @objc Swift
    # class. VERIFY each at runtime before touching it (boot ClassProbe below);
    # NEVER switch a bare %hook to the mangled name on this lint alone.
    rc_title = ("ADVISORY — possible runtime-dead class lookups (VERIFY at runtime; "
                "often false-positive for @objc-named Swift classes that resolve bare)")

    def print_classprobe_hint():
        if not rc:
            return
        names = ", ".join('@"%s"' % g.name for g, _ in rc[:8])
        print(yel("\n  ⚠ VERIFY before changing any of these — add a boot probe and read the device log:"))
        print("    __attribute__((constructor)) static void _p(void){")
        print("      for (NSString *n in @[%s])" % names)
        print('        NSLog(@"[ClassProbe] %@ = %@", n, NSClassFromString(n));')
        print("    }")
        print("    bare lookup non-null → keep the bare %hook; only mangle when bare is null AND mangled resolves.")

    if not old:
        print(hl(f"\n══ runtime-lookup lint against {new_label} ══"))
        print(hl(f"\n══ references scraped: {len(refs)} ══"))
        print_bucket(rc_title, rc, None, new)
        print_classprobe_hint()
        total = 0
        print(hl(f"\n══ total actionable: {total}  (advisory above is not counted) ══"))
        bc = bm = bi = bs = bk = pci = []
    else:
        bc, bm, bi, bs, bk = diff(refs, old, new)
        pci = perclass_ivar_loss(refs, old, new)

        print_overview(old, new, old_label, new_label)
        print(hl(f"\n══ references scraped: {len(refs)} ══"))
        print_bucket("BROKEN classes (in %s, gone in %s)" % (old_label, new_label), bc, old, new)
        print_bucket("BROKEN methods on surviving class (silent hook failure)", bm, old, new)
        print_bucket("BROKEN ivars (gone from entire binary)", bi, old, new)
        print_bucket("BROKEN ivars on surviving class (moved/renamed, name survives elsewhere)", pci, old, new)
        print_bucket("BROKEN selectors (gone from entire binary)", bs, old, new)
        print_bucket("BROKEN KVC keys (no getter/ivar left)", bk, old, new)
        print_bucket(rc_title, rc, old, new)
        print_classprobe_hint()

        total = len(bc) + len(bm) + len(bi) + len(pci) + len(bs) + len(bk)
        print(hl(f"\n══ total actionable: {total}  (advisory class lookups not counted) ══"))

        added_class_report(refs, old, new, args.added_limit, args.added_all)

    if args.json:
        def dump(items):
            return [{"kind": r.kind, "name": r.name, "owner": r.owner,
                     "file": r.file, "line": r.line, "suggest": sug}
                    for r, sug in items]
        with open(args.json, "w") as fh:
            json.dump({"old": old_label, "new": new_label,
                       "classes": dump(bc), "methods": dump(bm),
                       "ivars": dump(bi), "ivars_perclass": dump(pci),
                       "selectors": dump(bs),
                       "kvc": dump(bk), "runtime_dead": dump(rc)}, fh, indent=2)
        print(f"[*] wrote {args.json}", file=sys.stderr)

    if not args.keep_staged:
        sys.stdout.flush()                      # keep the report above the prune note
        freed = (prune_stage(args.old) if args.old else 0) + prune_stage(args.new)
        if freed:
            print("[*] pruned staged binaries/headers (~%d MB freed, kept index.json); "
                  "--keep-staged to retain" % (freed // (1024 * 1024)), file=sys.stderr)

    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
