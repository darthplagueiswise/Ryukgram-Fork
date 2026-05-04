#import <Foundation/Foundation.h>
#import "SCIDexKitDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDexKitInstallReason) {
    SCIDexKitInstallReasonStartupOverride = 0,
    SCIDexKitInstallReasonUserOverride = 1,
    SCIDexKitInstallReasonSessionObserve = 2,
};

FOUNDATION_EXPORT BOOL SCIDexKitInstallHookForDescriptor(SCIDexKitDescriptor *descriptor, SCIDexKitInstallReason reason, NSError **error);
FOUNDATION_EXPORT BOOL SCIDexKitIsHookInstalled(NSString *overrideKey);
FOUNDATION_EXPORT NSUInteger SCIDexKitInstalledHookCount(void);
FOUNDATION_EXPORT void SCIDexKitReapplySavedOverrides(void);
FOUNDATION_EXPORT void SCIDexKitEnableSessionObservationForDescriptors(NSArray<SCIDexKitDescriptor *> *descriptors);
FOUNDATION_EXPORT void SCIDexKitRetryPendingOverridesForImage(NSString *imageBasename);

NS_ASSUME_NONNULL_END
