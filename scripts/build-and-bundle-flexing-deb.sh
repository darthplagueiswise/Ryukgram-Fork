#!/usr/bin/env bash
set -euo pipefail

# Build and bundle a single unified AllFLEXing.dylib into RyukGram's .deb.
#
# Why this exists:
# - upstream FLEXing is split into FLEXing.dylib + libFLEX.dylib;
# - the known working AllFLEXing builds both parts into one Mach-O;
# - keeping it separate from RyukGram.dylib avoids linking FLEX into RyukGram.
#
# Args:
#   1: THEOS_STAGING_DIR
#   2: THEOS_PACKAGE_INSTALL_PREFIX, usually empty or /var/jb
#
# Env:
#   FLEXING_FILTER_MODE=instagram  default: Instagram + InstagramBeta + executable Instagram
#   FLEXING_FILTER_MODE=all        broad UIKit filter, similar to upstream FLEXing

STAGING="${1:?missing THEOS_STAGING_DIR}"
PREFIX="${2:-}"
FLEX_DIR="modules/FLEXing"
CACHE_DIR="packages/cache/flexing-deb"
BUILD_DIR="$CACHE_DIR/allflexing-build"
FILTER_MODE="${FLEXING_FILTER_MODE:-instagram}"

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

if [ ! -d "$FLEX_DIR/libflex/FLEX/Classes" ]; then
  warn "$FLEX_DIR/libflex/FLEX/Classes not found; deb will be built without bundled FLEX."
  exit 0
fi

ROOT_DIR="$(pwd)"
FLEX_ROOT="$ROOT_DIR/$FLEX_DIR/libflex/FLEX"
FLEXING_ROOT="$ROOT_DIR/$FLEX_DIR"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/Tweak_AllFLEXing.xm" <<'EOF'
#import "Interfaces.h"
#import "libFLEX.h"
#import "FLEXWindow.h"
#import "FLEXManager.h"

BOOL initialized = NO;
id manager = nil;
SEL show = nil;

static NSHashTable *windowsWithGestures = nil;

inline bool isLikelyUIProcess() {
    NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
    return [executablePath hasPrefix:@"/var/containers/Bundle/Application"] ||
        [executablePath hasPrefix:@"/Applications"] ||
        [executablePath hasSuffix:@"CoreServices/SpringBoard.app/SpringBoard"];
}

inline bool isSnapchatApp() {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.toyopagroup.picaboo"];
}

%ctor {
    if (!isLikelyUIProcess() || isSnapchatApp()) return;

    manager = FLXGetManager();
    show = FLXRevealSEL();

    if (manager && show && FLXWindowClass()) {
        windowsWithGestures = [NSHashTable weakObjectsHashTable];
        initialized = YES;
    }
}

%hook UIWindow
- (BOOL)_shouldCreateContextAsSecure {
    Class flexWindowClass = FLXWindowClass();
    return (initialized && flexWindowClass && [self isKindOfClass:flexWindowClass]) ? YES : %orig;
}

- (void)becomeKeyWindow {
    %orig;

    if (!initialized) return;

    Class flexWindowClass = FLXWindowClass();
    BOOL needsGesture = ![windowsWithGestures containsObject:self];
    BOOL isFLEXWindow = flexWindowClass && [self isKindOfClass:flexWindowClass];
    BOOL isStatusBar = [self isKindOfClass:%c(UIStatusBarWindow)];

    if (needsGesture && !isFLEXWindow && !isStatusBar) {
        [windowsWithGestures addObject:self];
        UILongPressGestureRecognizer *tap = [[UILongPressGestureRecognizer alloc] initWithTarget:manager action:show];
        tap.minimumPressDuration = .5;
        tap.numberOfTouchesRequired = 3;
        [self addGestureRecognizer:tap];
    }
}
%end

%hook UIStatusBarWindow
- (id)initWithFrame:(CGRect)frame {
    self = %orig;
    if (initialized) {
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:manager action:show]];
    }
    return self;
}
%end

%hook FLEXExplorerViewController
- (BOOL)_canShowWhileLocked {
    return YES;
}
%end

%hook _UISheetPresentationController
- (id)initWithPresentedViewController:(id)present presentingViewController:(id)presenter {
    self = %orig;
    if ([present isKindOfClass:%c(FLEXNavigationController)]) {
        self._presentsAtStandardHalfHeight = YES;
        self._indexOfCurrentDetent = 1;
        self._prefersScrollingExpandsToLargerDetentWhenScrolledToEdge = NO;
        self._indexOfLastUndimmedDetent = 1;
    }
    return self;
}
%end

%hook FLEXManager
%new
+ (NSString *)dlopen:(NSString *)path {
    if (!dlopen(path.UTF8String, RTLD_NOW)) return @(dlerror());
    return @"OK";
}
%end
EOF

cat > "$BUILD_DIR/Makefile" <<EOF
export ARCHS = arm64
export TARGET = iphone:clang:16.2
include \$(THEOS)/makefiles/common.mk

FLEX_ROOT = $FLEX_ROOT
FLEXING_ROOT = $FLEXING_ROOT
BUILD_ROOT = $ROOT_DIR/$BUILD_DIR

dtoim = \$(foreach d,\$(1),-I\$(d))
SOURCES  = \$(shell find \$(FLEX_ROOT)/Classes -name '*.c')
SOURCES += \$(shell find \$(FLEX_ROOT)/Classes -name '*.m')
SOURCES += \$(shell find \$(FLEX_ROOT)/Classes -name '*.mm')
_IMPORTS  = \$(shell /bin/ls -d \$(FLEX_ROOT)/Classes/*/ 2>/dev/null)
_IMPORTS += \$(shell /bin/ls -d \$(FLEX_ROOT)/Classes/*/*/ 2>/dev/null)
_IMPORTS += \$(shell /bin/ls -d \$(FLEX_ROOT)/Classes/*/*/*/ 2>/dev/null)
_IMPORTS += \$(shell /bin/ls -d \$(FLEX_ROOT)/Classes/*/*/*/*/ 2>/dev/null)
IMPORTS = -I\$(FLEXING_ROOT) -I\$(FLEXING_ROOT)/libflex -I\$(FLEX_ROOT)/Classes/ \$(call dtoim, \$(_IMPORTS))

TWEAK_NAME = AllFLEXing
AllFLEXing_FILES = \$(BUILD_ROOT)/Tweak_AllFLEXing.xm \$(FLEXING_ROOT)/libflex/libFLEX.x \$(SOURCES)
AllFLEXing_FRAMEWORKS = CoreGraphics UIKit ImageIO QuartzCore Foundation Security WebKit SceneKit
AllFLEXing_LIBRARIES = sqlite3 z
AllFLEXing_CFLAGS += -fobjc-arc -w -Wno-unsupported-availability-guard \$(IMPORTS)
AllFLEXing_CCFLAGS += -std=gnu++11
AllFLEXing_LOGOSFLAGS = --c warnings=none

include \$(THEOS_MAKE_PATH)/tweak.mk
EOF

log "building unified AllFLEXing.dylib"
( cd "$BUILD_DIR" && make FINALPACKAGE=1 )

ALLFLEX="$(find "$BUILD_DIR/.theos" -name 'AllFLEXing.dylib' -type f | head -n 1 || true)"
if [ -z "$ALLFLEX" ] || [ ! -f "$ALLFLEX" ]; then
  warn "AllFLEXing.dylib was not produced; deb will be built without bundled FLEX."
  exit 0
fi

# The sample AllFLEXing identifies itself as /usr/lib/libFLEX.dylib. This is not
# required for Substrate loading, but keeping the id helps old FLEXing codepaths
# and IPA injectors that expect libFLEX naming.
if command -v install_name_tool >/dev/null 2>&1; then
  install_name_tool -id /usr/lib/libFLEX.dylib "$ALLFLEX" 2>/dev/null || true
fi

DYLIB_DEST="$STAGING$PREFIX/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DYLIB_DEST"
cp -f "$ALLFLEX" "$DYLIB_DEST/AllFLEXing.dylib"

if [ "$FILTER_MODE" = "all" ]; then
  log "writing broad UIKit filter plist"
  cat > "$DYLIB_DEST/AllFLEXing.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Filter</key>
  <dict>
    <key>Bundles</key>
    <array>
      <string>com.apple.UIKit</string>
    </array>
  </dict>
</dict>
</plist>
PLIST
else
  log "writing Instagram-focused plist; set FLEXING_FILTER_MODE=all for broad UIKit filter"
  cat > "$DYLIB_DEST/AllFLEXing.plist" <<'PLIST'
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
fi

log "bundled unified AllFLEXing.dylib and AllFLEXing.plist into $DYLIB_DEST"
