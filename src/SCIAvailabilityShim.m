// SCIAvailabilityShim.m
// Provides a Foundation-backed __isOSVersionAtLeast so Theos tweaks using
// @available(iOS X, *) don't fail with an undefined symbol at link time
// (compiler-rt is not auto-linked for tweak dylibs). Marked weak so any
// real compiler-rt definition wins if present.
#import <Foundation/Foundation.h>
#import <stdint.h>

__attribute__((visibility("default"), weak))
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor) {
	NSOperatingSystemVersion v;
	v.majorVersion = (NSInteger)major;
	v.minorVersion = (NSInteger)minor;
	v.patchVersion = (NSInteger)subminor;
	return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:v] ? 1 : 0;
}
