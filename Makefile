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
RYUKGRAM_SRC_FILES := $(filter-out src/FLEXing/%,$(RYUKGRAM_SRC_FILES))

RyukGram_FILES = $(RYUKGRAM_SRC_FILES) $(GENERATED_SCHEMA_SRC) $(wildcard modules/JGProgressHUD/*.m) modules/fishhook/fishhook.c

ifdef SIDESTORE
RyukGram_FILES += modules/SideloadPatch/SideloadPatch.xm
endif

RyukGram_FRAMEWORKS = UIKit Foundation CoreGraphics Photos CoreServices SystemConfiguration SafariServices Security QuartzCore AVFoundation AVKit UniformTypeIdentifiers CoreLocation MapKit
RyukGram_PRIVATE_FRAMEWORKS = Preferences
RyukGram_CFLAGS = -fobjc-arc -Wno-unsupported-availability-guard -Wno-unused-value -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types -include src/SCIPrefix.h
RyukGram_LOGOSFLAGS = --c warnings=none

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk
