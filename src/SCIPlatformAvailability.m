#import <Foundation/Foundation.h>
#include <stdint.h>

int __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t patch) {
	(void)platform;
	NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
	if (version.majorVersion != (NSInteger)major) return version.majorVersion > (NSInteger)major;
	if (version.minorVersion != (NSInteger)minor) return version.minorVersion > (NSInteger)minor;
	return version.patchVersion >= (NSInteger)patch;
}
