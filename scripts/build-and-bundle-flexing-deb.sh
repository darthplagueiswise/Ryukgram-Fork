#!/usr/bin/env bash
set -euo pipefail

# Build and bundle the existing FLEXing submodule into RyukGram's .deb.
# This keeps FLEXing/libFLEX as separate dylibs in the same package instead of
# linking FLEX into RyukGram.dylib.
#
# Args:
#   1: THEOS_STAGING_DIR
#   2: THEOS_PACKAGE_INSTALL_PREFIX, usually empty or /var/jb

STAGING="${1:?missing THEOS_STAGING_DIR}"
PREFIX="${2:-}"
FLEX_DIR="modules/FLEXing"
CACHE_DIR="packages/cache/flexing-deb"

log() { printf '[bundle-flexing] %s\n' "$*"; }
warn() { printf '[bundle-flexing] WARN: %s\n' "$*" >&2; }

if [ ! -d "$FLEX_DIR" ] || [ -z "$(ls -A "$FLEX_DIR" 2>/dev/null || true)" ]; then
  if command -v git >/dev/null 2>&1 && [ -f .gitmodules ]; then
    log "FLEXing submodule missing/empty; trying git submodule update --init --recursive $FLEX_DIR"
    git submodule update --init --recursive "$FLEX_DIR" || true
  fi
fi

if [ ! -d "$FLEX_DIR" ] || [ -z "$(ls -A "$FLEX_DIR" 2>/dev/null || true)" ]; then
  warn "FLEXing submodule not available; deb will be built without bundled FLEX."
  exit 0
fi

mkdir -p "$CACHE_DIR"

# Build libFLEX first, then FLEXing. This mirrors the working sideload/dev flow,
# but packages both dylibs inside the same RyukGram deb.
if [ -d "$FLEX_DIR/libflex" ]; then
  log "building libFLEX"
  ( cd "$FLEX_DIR/libflex" && make FINALPACKAGE=1 )
else
  warn "$FLEX_DIR/libflex not found; continuing with whatever dylibs already exist"
fi

log "building FLEXing"
( cd "$FLEX_DIR" && make FINALPACKAGE=1 )

# Collect dylibs from common Theos obj locations. Names vary by fork/case:
# FLEXing.dylib, libFLEX.dylib, libflex.dylib.
rm -f "$CACHE_DIR"/*.dylib 2>/dev/null || true

while IFS= read -r dylib; do
  [ -f "$dylib" ] || continue
  base="$(basename "$dylib")"
  case "$base" in
    FLEXing.dylib|libFLEX.dylib|libflex.dylib)
      log "caching $base from $dylib"
      cp -f "$dylib" "$CACHE_DIR/$base"
      ;;
  esac
done <<EOF
$(find "$FLEX_DIR" -path '*/.theos/obj*/*.dylib' -type f 2>/dev/null || true)
$(find .theos -path '*/obj*/*.dylib' -type f 2>/dev/null || true)
EOF

if [ ! -f "$CACHE_DIR/FLEXing.dylib" ]; then
  warn "FLEXing.dylib was not produced; deb will be built without bundled FLEX."
  exit 0
fi

if [ ! -f "$CACHE_DIR/libFLEX.dylib" ] && [ -f "$CACHE_DIR/libflex.dylib" ]; then
  cp -f "$CACHE_DIR/libflex.dylib" "$CACHE_DIR/libFLEX.dylib"
fi

DYLIB_DEST="$STAGING$PREFIX/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DYLIB_DEST"

cp -f "$CACHE_DIR/FLEXing.dylib" "$DYLIB_DEST/FLEXing.dylib"

if [ -f "$CACHE_DIR/libFLEX.dylib" ]; then
  cp -f "$CACHE_DIR/libFLEX.dylib" "$DYLIB_DEST/libFLEX.dylib"
fi

# FLEXing's upstream plist targets com.apple.UIKit; for RyukGram we filter only
# Instagram processes. Bundles are exact, Executables covers custom/beta bundle IDs.
cat > "$DYLIB_DEST/FLEXing.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Filter</key>
  <dict>
    <key>Bundles</key>
    <array>
      <string>com.burbn.instagram</string>
      <string>com.burbn.instagrambeta</string>
    </array>
    <key>Executables</key>
    <array>
      <string>Instagram</string>
    </array>
  </dict>
</dict>
</plist>
PLIST

log "bundled FLEXing.dylib, optional libFLEX.dylib, and FLEXing.plist into $DYLIB_DEST"
