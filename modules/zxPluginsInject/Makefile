TARGET := iphone:clang:16.2:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := zxPluginsInject

RYG_FILELOG ?= 0

$(TWEAK_NAME)_FILES := SideloadFix.xm ../../src/RYGFileLog.m ../fishhook/fishhook.c
$(TWEAK_NAME)_CFLAGS := -fobjc-arc -Os -DRYG_FILELOG=$(RYG_FILELOG)
$(TWEAK_NAME)_FRAMEWORKS := Foundation
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS_MAKE_PATH)/tweak.mk
