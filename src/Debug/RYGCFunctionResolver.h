#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGCFunctionRow : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *imageUUID;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *fishhookName;
@property (nonatomic, assign) uint64_t stubAddress;
@property (nonatomic, assign) NSUInteger directCallSiteCount;
@property (nonatomic, assign) BOOL predicateHookable;
@property (nonatomic, copy) NSString *evidence;
@property (nonatomic, readonly) NSString *identity;
@property (nonatomic, readonly, nullable) NSNumber *overrideValue;
@end

/// On-demand Mach-O import resolver for the Runtime Browser C Functions page.
/// No work is performed until the user opens the page for one image.
@interface RYGCFunctionResolver : NSObject
+ (NSArray<RYGCFunctionRow *> *)functionsForImagePath:(NSString *)imagePath;
+ (nullable NSNumber *)overrideForFunction:(RYGCFunctionRow *)function;
+ (BOOL)setOverride:(nullable NSNumber *)value forFunction:(RYGCFunctionRow *)function error:(NSError * _Nullable * _Nullable)error;
+ (void)invalidateImagePath:(NSString *)imagePath;
@end

NS_ASSUME_NONNULL_END
