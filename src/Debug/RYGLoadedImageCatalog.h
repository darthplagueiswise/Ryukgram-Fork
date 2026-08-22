#import <Foundation/Foundation.h>
#import <mach-o/loader.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGLoadedImageRecord : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *stableIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) const struct mach_header *header;
@property (nonatomic, assign) intptr_t slide;
@property (nonatomic, assign, getter=isMainExecutable) BOOL mainExecutable;
@end

@interface RYGLoadedImageCatalog : NSObject
/// Returns only the main executable plus binaries physically bundled inside the
/// current app. The snapshot is built with one dyld pass and cached until dyld
/// reports an image change.
+ (NSArray<RYGLoadedImageRecord *> *)bundledImages;
+ (nullable RYGLoadedImageRecord *)recordForPath:(NSString *)path;
+ (nullable RYGLoadedImageRecord *)recordForStableIdentifier:(NSString *)identifier;
+ (nullable RYGLoadedImageRecord *)mainExecutableRecord;
+ (NSString *)stableIdentifierForPath:(NSString *)path;
+ (void)invalidate;
@end

NS_ASSUME_NONNULL_END
