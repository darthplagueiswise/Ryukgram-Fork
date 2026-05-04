#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIDexKitImageInfo : NSObject
@property (nonatomic, copy) NSString *basename;
@property (nonatomic, copy) NSString *path;
@end

@interface SCIDexKitImagePolicy : NSObject
+ (NSArray<NSString *> *)allowedImageBasenames;
+ (BOOL)isAllowedImageBasename:(NSString *)basename;
+ (BOOL)isAllowedImagePath:(NSString *)path basename:(NSString *)basename;
+ (NSArray<SCIDexKitImageInfo *> *)loadedAllowedImages;
+ (void)addPendingOverrideKey:(NSString *)key forImage:(NSString *)image;
+ (NSArray<NSString *> *)drainPendingOverrideKeysForImage:(NSString *)image;
+ (NSArray<NSString *> *)allPendingOverrideKeys;
@end

NS_ASSUME_NONNULL_END
