TARGET := iphone:clang:16.2
INSTALL_TARGET_PROCESSES = Instagram
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RyukGram

SCHEMA_JSON ?= resources/igios-instagram-schema_client-persist.json
GENERATED_SCHEMA_SRC := src/Generated/SCIEmbeddedMobileConfigSchema.m

before-all::
	@if [ -f scripts/embed_mobileconfig_schema.py ]; then \
		python3 scripts/embed_mobileconfig_schema.py "$(SCHEMA_JSON)" "$(GENERATED_SCHEMA_SRC)"; \
	else \
		echo "[RyukGram] scripts/embed_mobileconfig_schema.py not found; skipping embedded schema generation"; \
		mkdir -p $$(dirname "$(GENERATED_SCHEMA_SRC)"); \
		printf '%s\n' '#import <Foundation/Foundation.h>' 'NSDictionary *SCIEmbeddedMobileConfigSchema(void) { return @{}; }' > "$(GENERATED_SCHEMA_SRC)"; \
	fi

RYUKGRAM_SRC_FILES := $(shell find src -type f \( -iname \*.x -o -iname \*.xm -o -iname \*.m \))
RYUKGRAM_SRC_FILES := $(filter-out src/Generated/%,$(RYUKGRAM_SRC_FILES))

$(TWEAK_NAME)_FILES = $(RYUKGRAM_SRC_FILES) $(GENERATED_SCHEMA_SRC) $(wildcard modules/JGProgressHUD/*.m) modules/fishhook/fishhook.c

# SideStore-only: legacy sideload compat patch (keychain, app groups, CloudKit).
ifdef SIDESTORE
	$(TWEAK_NAME)_FILES += modules/SideloadPatch/SideloadPatch.xm
endif
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics Photos CoreServices SystemConfiguration SafariServices Security QuartzCore AVFoundation AVKit UniformTypeIdentifiers CoreLocation MapKit
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unsupported-availability-guard -Wno-unused-value -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types -include src/SCIPrefix.h
$(TWEAK_NAME)_LOGOSFLAGS = --c warnings=none

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk

# Bundle FLEXing/libFLEX into the same .deb as RyukGram.
# This does not link FLEX into RyukGram.dylib; it stages separate dylibs and a
# FLEXing.plist filtered to Instagram/beta/custom bundle IDs via executable.
BUNDLE_FLEXING ?= 1
ifeq ($(BUNDLE_FLEXING),1)
before-package::
	@bash scripts/build-and-bundle-flexing-deb.sh "$(THEOS_STAGING_DIR)" "$(THEOS_PACKAGE_INSTALL_PREFIX)"
endif

# Build FLEXing for sideloading/dev IPA flows.
ifdef SIDELOAD
	$(TWEAK_NAME)_SUBPROJECTS += modules/FLEXing
endif
