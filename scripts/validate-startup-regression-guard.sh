#!/bin/sh
set -eu
ROOT="${1:-$(pwd)}"
fail=0
say(){ printf '%s\n' "$*"; }

say '[RyukGram] validating startup regression guard...'

if find "$ROOT/src" -path '*/SCILiquidGlassForce.x' -o -path '*/SCIStoryTrayForce.x' -o -path '*/SCIStatusBarOldSchoolForce.x' -o -path '*/SCIWordmarkForce.x' -o -path '*/SCIXPluginsLookupHook.x' | grep -q .; then
  say 'FAIL: compiled launch/XPlugins force hook file still present'
  find "$ROOT/src" -path '*/SCILiquidGlassForce.x' -o -path '*/SCIStoryTrayForce.x' -o -path '*/SCIStatusBarOldSchoolForce.x' -o -path '*/SCIWordmarkForce.x' -o -path '*/SCIXPluginsLookupHook.x'
  fail=1
fi

if grep -R '#import <mach/mach_vm.h>' "$ROOT/src" >/dev/null 2>&1; then
  say 'FAIL: mach/mach_vm.h import found'
  grep -RIn '#import <mach/mach_vm.h>' "$ROOT/src" || true
  fail=1
fi

if grep -RIn 'IGMobileConfigSessionlessBooleanValueForInternalUse\|sci_force_mc_sessionless' "$ROOT/src" >/dev/null 2>&1; then
  say 'FAIL: unavailable sessionless MobileConfig symbol/key found'
  grep -RIn 'IGMobileConfigSessionlessBooleanValueForInternalUse\|sci_force_mc_sessionless' "$ROOT/src" || true
  fail=1
fi

python3 - <<'PY' "$ROOT" || fail=1
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
fail=[]
def strip_comments(s):
    s=re.sub(r'/\*.*?\*/','',s,flags=re.S)
    s=re.sub(r'//.*','',s)
    return s
for p in root.glob('src/**/*.x'):
    clean=strip_comments(p.read_text(errors='ignore'))
    if 'extern "C"' in clean:
        fail.append((str(p.relative_to(root)), 'extern "C" in Logos .x'))
for rel in ['src/Features/EasyGating/SCIEasyGatingHook.x',
            'src/Features/EasyGating/SCISessionedMCGateHook.x',
            'src/Features/MobileConfig/SCIInternalUseGateHook.x',
            'src/Features/Gating/SCIIGDSLauncherConfigHook.x']:
    p=root/rel
    if not p.exists():
        fail.append((rel, 'missing'))
        continue
    clean=strip_comments(p.read_text(errors='ignore'))
    for m in re.finditer(r'%ctor\s*\{', clean):
        start=m.start(); depth=0; end=len(clean)
        for i,ch in enumerate(clean[start:], start=start):
            if ch=='{': depth+=1
            elif ch=='}':
                depth-=1
                if depth==0:
                    end=i+1; break
        body=clean[start:end]
        for bad in ['rebind_symbols','MSHookFunction','MSHookMessageEx','SCIInstallEasyGatingHooksIfNeeded','SCIInstallSessionedMCGateHooksIfNeeded','SCIInstallMobileConfigInternalUseGateIfNeeded','IGDSInstall']:
            if bad in body:
                fail.append((rel, 'sensitive %ctor uses '+bad))
if fail:
    for f in fail: print('FAIL:', f[0], '-', f[1])
    sys.exit(1)
print('python startup guard: OK')
PY

if [ -d "$ROOT/.git" ]; then
  (cd "$ROOT" && git diff --check)
fi

if [ "$fail" -ne 0 ]; then
  say '[RyukGram] startup regression guard FAILED'
  exit 1
fi
say '[RyukGram] startup regression guard OK'
