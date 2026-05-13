#import <Foundation/Foundation.h>

int __isOSVersionAtLeast(int major, int minor, int subminor) {
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (version.majorVersion != major) return version.majorVersion > major;
    if (version.minorVersion != minor) return version.minorVersion > minor;
    return version.patchVersion >= subminor;
}
