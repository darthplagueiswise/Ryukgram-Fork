#import "SCIDexKitStore.h"
#import "SCIDexKitBoolRouter.h"
#import "SCIDexKitImagePolicy.h"
#import "../../Core/SCIBoolOverrideResolver.h"
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

static NSString *SCIDexKitBasenameFromDyldHeader(const struct mach_header *mh) {
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr((const void *)mh, &info) == 0 || !info.dli_fname) return @"";
    return @(info.dli_fname).lastPathComponent;
}

static void SCIDexKitImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    NSString *base = SCIDexKitBasenameFromDyldHeader(mh);
    if (![SCIDexKitImagePolicy isAllowedImageBasename:base]) return;
    SCIDexKitRetryPendingOverridesForImage(base);
}

%ctor {
    @autoreleasepool {
        [SCIDexKitStore registerDefaults];
        [SCIDexKitStore migrateIfNeeded];
        [SCIDexKitStore invalidateObservedCacheIfBuildChanged];
        [SCIBoolOverrideResolver reloadSnapshotFromDefaults];
        [SCIDexKitStore beginBootGuard];
        _dyld_register_func_for_add_image(SCIDexKitImageAdded);
        SCIDexKitReapplySavedOverrides();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SCIDexKitStore markLaunchStable];
        });
    }
}
