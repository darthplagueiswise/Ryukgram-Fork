TARGET := iphone:clang:26.5:15.0
INSTALL_TARGET_PROCESSES = Instagram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RyukGram

$(TWEAK_NAME)_FILES = $(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m \)) modules/fishhook/fishhook.c

# The no-plugins sideload compat patch (keychain / app groups / CloudKit) is no
# longer baked in here — it ships as a standalone NoPluginsPatch.dylib
# (modules/SideloadPatch) injected by cyan for no-plugins builds.

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics Photos CoreServices SystemConfiguration SafariServices Security QuartzCore AVFoundation AVKit UniformTypeIdentifiers CoreLocation MapKit LocalAuthentication Vision CoreImage CoreVideo CoreMedia VideoToolbox CoreData
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences

# File logger master switch. OFF for production — the logger, its NSLog tee, and
# the Settings row compile out to nothing. Build RYG_FILELOG=1 to get it back.
RYG_FILELOG ?= 0

# Dynamic-coverage probe master switch. OFF for production — every RYGProbe*
# macro and the whole RYGDynamicProbe.xm compile out to nothing (zero overhead).
# Build RYG_PROBE=1 to audit hook coverage on the next IG bump.
RYG_PROBE ?= 0

# iOS 26-only UIKit classes are referenced by Logos groups whose installation is
# already guarded at runtime with @available(iOS 26.0, *) + objc_getClass().
# Keep deployment at iOS 15 while allowing those guarded declarations to compile.
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unsupported-availability-guard -Wno-unguarded-availability-new -Wno-unused-value -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types -DRYG_FILELOG=$(RYG_FILELOG) -DRYG_PROBE=$(RYG_PROBE) -include src/RYGPrefix.h
$(TWEAK_NAME)_LOGOSFLAGS = --c warnings=none
$(TWEAK_NAME)_LDFLAGS += -lcompression -lsqlite3

ifeq ($(FINALPACKAGE),1)
	$(TWEAK_NAME)_LDFLAGS += -Wl,-x
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_RYG*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_ryg*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_kRYG*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,_dm*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,__Z*
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,'_OBJC_CLASS_$$_*RYG*'
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,'_OBJC_METACLASS_$$_*RYG*'
	$(TWEAK_NAME)_LDFLAGS += -Wl,-unexported_symbol,'_OBJC_IVAR_$$_*RYG*'
endif

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(FINALPACKAGE),1)
after-all::
	@python3 tools/obfuscate-classes.py "$(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib"
	@ldid -S "$(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib"
endif

# # Build FLEXing once for sideload builds, then reuse the compiled dylib.
# ifdef SIDELOAD

# FLEXING_DYLIB := modules/flexing/.theos/obj/arm64/FLEXing.dylib

# $(FLEXING_DYLIB):
# 	$(MAKE) -C modules/flexing FINALPACKAGE=1

# before-package:: $(FLEXING_DYLIB)

# clean-flexing::
# 	$(MAKE) -C modules/flexing clean

# endif
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
