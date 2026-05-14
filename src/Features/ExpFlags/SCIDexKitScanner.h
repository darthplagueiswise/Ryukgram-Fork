#import <Foundation/Foundation.h>
#import "SCIDexKitDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDexKitScannerMode) {
    SCIDexKitScannerModeCurated = 0,
    SCIDexKitScannerModeRaw = 1,
};

@interface SCIDexKitScanner : NSObject
+ (void)invalidateCache;
+ (NSArray<SCIDexKitDescriptor *> *)scanDescriptorsWithMode:(SCIDexKitScannerMode)mode query:(nullable NSString *)query;
@end

NS_ASSUME_NONNULL_END
