#import "RYGExperimentalGuard.h"
#import "../../Utils.h"

static NSString *const kCounterKey = @"ryg_exp_unstable_launches";
static NSInteger  const kThreshold = 5;
static BOOL gDidReset = NO;

@implementation RYGExperimentalGuard

+ (NSArray<NSString *> *)allPrefKeys {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            @"igt_homecoming",
            @"igt_quicksnap",
            @"igt_prism",
            @"igt_directnotes_friendmap",
            @"igt_directnotes_audio_reply",
            @"igt_directnotes_avatar_reply",
            @"igt_directnotes_gifs_reply",
            @"igt_directnotes_photo_reply",
            @"igt_ip_appicon",
            @"igt_ip_storyfonts",
            @"igt_ip_chatfonts",
            @"igt_ip_biofont",
            @"igt_ip_customlists",
            @"igt_ip_storypeek",
            @"igt_ip_dmpeek",
            @"igt_ip_brandedthreads",
            @"igt_ip_timestampviewers",
            @"igt_ip_searchviewers",
            @"igt_ip_storyspotlight",
            @"igt_ip_superlikes",
            @"igt_ip_storyrewatch",
            @"igt_ip_storyextend",
            @"igt_ip_pinnedposts",
            @"igt_ip_silentprofile",
            @"igt_ip_silenthighlights",
        ];
    });
    return keys;
}

+ (BOOL)anyEnabled {
    for (NSString *k in [self allPrefKeys]) {
        if ([RYGUtils getBoolPref:k]) return YES;
    }
    return NO;
}

+ (void)resetAll {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in [self allPrefKeys]) [ud setBool:NO forKey:k];
}

+ (BOOL)didResetThisLaunch { return gDidReset; }

+ (void)load {
    if (![self anyEnabled]) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger c = [ud integerForKey:kCounterKey] + 1;

    if (c >= kThreshold) {
        [self resetAll];
        [ud removeObjectForKey:kCounterKey];
        gDidReset = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            RYGNotifyWarning(RYG_NOTIF_EXPERIMENTAL_WARN,
                             RYGLocalized(@"Experimental flags reset"),
                             RYGLocalized(@"Disabled after repeated crashes."));
        });
        return;
    }

    [ud setInteger:c forKey:kCounterKey];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCounterKey];
    });
}

@end
