#import "../../Utils.h"
#import "SCIPersistedQueryCatalog.h"
#import <Foundation/Foundation.h>

static BOOL RGPQShouldPrewarm(void) {
    return [SCIUtils getBoolPref:@"igt_quicksnap"] ||
           [SCIUtils getBoolPref:@"igt_employee_master"] ||
           [SCIUtils getBoolPref:@"igt_employee"] ||
           [SCIUtils getBoolPref:@"igt_internal"] ||
           [SCIUtils getBoolPref:@"sci_exp_flags_enabled"] ||
           [SCIUtils getBoolPref:@"igt_internaluse_observer"];
}

static void RGPQLogPriorityEntries(void) {
    if (![SCIUtils getBoolPref:@"igt_internaluse_observer"]) return;

    SCIPersistedQueryCatalog *catalog = [SCIPersistedQueryCatalog sharedCatalog];
    NSArray<SCIPersistedQueryEntry *> *quickSnap = [catalog priorityQuickSnapEntries];
    NSArray<SCIPersistedQueryEntry *> *dogfood = [catalog priorityDogfoodEntries];

    NSLog(@"[RyukGram][PersistedQueries] source=%@", [catalog sourceDescription]);

    for (SCIPersistedQueryEntry *entry in dogfood) {
        NSLog(@"[RyukGram][PersistedQueries][Dogfood] %@", [entry summaryLine]);
    }

    for (SCIPersistedQueryEntry *entry in quickSnap) {
        NSLog(@"[RyukGram][PersistedQueries][QuickSnap] %@", [entry summaryLine]);
    }
}

%ctor {
    if (!RGPQShouldPrewarm()) return;

    [SCIPersistedQueryCatalog prewarmInBackground];

    if ([SCIUtils getBoolPref:@"igt_internaluse_observer"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            RGPQLogPriorityEntries();
        });
    }
}
