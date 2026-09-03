TARGET := iphone:clang:16.2:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := RYGViewOnceCapture

RYG_FILELOG ?= 0

$(TWEAK_NAME)_FILES := RYGViewOnceCapture.m ../../src/RYGFileLog.m ../../src/RYGOSLog.m
$(TWEAK_NAME)_CFLAGS := -fobjc-arc -Os -DRYG_FILELOG=$(RYG_FILELOG)
$(TWEAK_NAME)_FRAMEWORKS := Foundation Security

include $(THEOS_MAKE_PATH)/tweak.mk
