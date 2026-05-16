TARGET := iphone:clang:16.2
INSTALL_TARGET_PROCESSES = Instagram
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RyukGram

ifneq ($(wildcard modules/FLEXing/libflex/FLEX/Classes),)
TWEAK_NAME += AllFLEXing
endif

SCHEMA_JSON ?= resources/igios-instagram-schema_client-persist.json
GENERATED_SCHEMA_SRC := src/Generated/SCIEmbeddedMobileConfigSchema.m

before-all::
@if [ -f scripts/embed_mobileconfig_schema.py ]; then \
python3 scripts/embed_mobileconfig_schema.py "$(SCHEMA_JSON)" "$(GENERATED_SCHEMA_SRC)"; \
else \
echo "[RyukGram] scripts/embed_mobileconfig_schema.py not found; skipping embedded schema generation"; \
mkdir -p $$(dirname "$(GENERATED_SCHEMA_SRC)"); \
printf '%s\n' '#import <Foundation/Foundation.h>' 'NSDictionary *SCIEmbeddedMobileConfigSchema(void) { recat > AllFLEXing.plist <<'PLIST'

{

    Filter = {

        Bundles = (

            "com.apple.UIKit"

        );

    };

}

PLIST

cat > Makefile <<'MK'

TARGET := iphone:clang:16.2

INSTALL_TARGET_PROCESSES = Instagram

ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RyukGram

ifneq ($(wildcard modules/FLEXing/libflex/FLEX/Classes),)

TWEAK_NAME += AllFLEXing

endif

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

FLEX_ROOT := modules/FLEXing/libflex/FLEX

FLEXING_ROOT := modules/FLEXing

FLEX_SOURCES := $(shell find $(FLEX_ROOT)/Classes -name '*.c' -o -name '*.m' -o -name '*.mm' 2>/dev/null)

FLEX_IMPORT_DIRS := $(shell find $(FLEX_ROOT)/Classes -type d 2>/dev/null)

FLEX_IMPORTS := -I$(FLEXING_ROOT) -I$(FLEXING_ROOT)/libflex -I$(FLEX_ROOT)/Classes $(foreach d,$(FLEX_IMPORT_DIRS),-I$(d))

AllFLEXing_FILES = src/FLEXing/AllFLEXing.xm modules/FLEXing/libflex/libFLEX.x $(FLEX_SOURCES)

AllFLEXing_FRAMEWORKS = UIKit Foundation CoreGraphics ImageIO QuartzCore WebKit

AllFLEXing_LIBRARIES = sqlite3 z

AllFLEXing_CFLAGS = -fobjc-arc -w -Wno-unsupported-availability-guard $(FLEX_IMPORTS)

AllFLEXing_CCFLAGS = -std=gnu++11

AllFLEXing_LOGOSFLAGS = --c warnings=none

CCFLAGS += -std=c++11

include $(THEOS_MAKE_PATH)/tweak.mk

