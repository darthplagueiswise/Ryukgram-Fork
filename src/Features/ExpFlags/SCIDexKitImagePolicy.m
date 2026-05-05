#import "SCIDexKitImagePolicy.h"

@implementation SCIDexKitImageInfo
@end

static NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *gSCIDexKitPendingByImage;

@implementation SCIDexKitImagePolicy

+ (NSString *)configPath {
    return @"/Library/Application Support/RyukGram/SCIDexKitAllowedImages.plist";
}

+ (NSArray<NSString *> *)allowedImageBasenames {
    NSArray *fromDisk = [NSArray arrayWithContentsOfFile:[self configPath]];
    if ([fromDisk isKindOfClass:NSArray.class] && fromDisk.count) return fromDisk;
    NSString *mainName = NSBundle.mainBundle.executablePath.lastPathComponent ?: @"Instagram";
    return @[mainName, @"Instagram", @"FBSharedFramework"];
}

+ (BOOL)isAllowedImageBasename:(NSString *)basename {
    if (!basename.length) return NO;
    return [[self allowedImageBasenames] containsObject:basename];
}

+ (BOOL)isAllowedImagePath:(NSString *)path basename:(NSString *)basename {
    if (![self isAllowedImageBasename:basename]) return NO;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if (!bundlePath.length || !path.length) return NO;
    if ([path hasPrefix:bundlePath]) return YES;
    if ([basename isEqualToString:NSBundle.mainBundle.executablePath.lastPathComponent]) return YES;
    return NO;
}

+ (NSArray<SCIDexKitImageInfo *> *)loadedAllowedImages {
    NSMutableArray *out = [NSMutableArray array];
    unsigned int count = 0;
    const char **names = objc_copyImageNames(&count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *path = names[i] ? @(names[i]) : @"";
        NSString *base = path.lastPathComponent;
        if (![self isAllowedImagePath:path basename:base]) continue;
        SCIDexKitImageInfo *info = [SCIDexKitImageInfo new];
        info.path = path;
        info.basename = base;
        [out addObject:info];
    }
    if (names) free(names);
    return out;
}

+ (void)addPendingOverrideKey:(NSString *)key forImage:(NSString *)image {
    if (!key.length || !image.length) return;
    @synchronized(self) {
        if (!gSCIDexKitPendingByImage) gSCIDexKitPendingByImage = [NSMutableDictionary dictionary];
        if (!gSCIDexKitPendingByImage[image]) gSCIDexKitPendingByImage[image] = [NSMutableArray array];
        if (![gSCIDexKitPendingByImage[image] containsObject:key]) [gSCIDexKitPendingByImage[image] addObject:key];
    }
}

+ (NSArray<NSString *> *)drainPendingOverrideKeysForImage:(NSString *)image {
    if (!image.length) return @[];
    @synchronized(self) {
        NSArray *arr = [gSCIDexKitPendingByImage[image] copy] ?: @[];
        [gSCIDexKitPendingByImage removeObjectForKey:image];
        return arr;
    }
}

+ (NSArray<NSString *> *)allPendingOverrideKeys {
    @synchronized(self) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSArray *arr in gSCIDexKitPendingByImage.allValues) [out addObjectsFromArray:arr];
        return out;
    }
}

@end
