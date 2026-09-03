// Records IGProfileViewController visits when profile_analyzer_track_visits is on.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGProfileAnalyzerStorage.h"
#import "RYGProfileAnalyzerModels.h"

// IGProfileViewController declared in InstagramHeaders.h

// 30s per-pk debounce so back-and-forth navigation doesn't inflate the count.
static NSMutableDictionary<NSString *, NSDate *> *rygVisitDebounce(void) {
    static NSMutableDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
    return m;
}

%hook IGProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (![RYGUtils getBoolPref:@"profile_analyzer_track_visits"]) return;

    id igUser = nil;
    @try { igUser = [self valueForKey:@"user"]; } @catch (NSException *e) {}
    if (!igUser) return;

    RYGProfileAnalyzerUser *user = [RYGProfileAnalyzerUser userFromIGUserObject:igUser];
    if (!user.pk.length) return;
    // Skip when fieldCache hasn't loaded yet — the next viewDidAppear catches it.
    if (!user.username.length) return;

    NSString *selfPK = [RYGUtils currentUserPK];
    if (selfPK.length && [user.pk isEqualToString:selfPK]) return;

    NSMutableDictionary *deb = rygVisitDebounce();
    NSString *key = [NSString stringWithFormat:@"%@>%@", selfPK ?: @"anon", user.pk];
    NSDate *last = deb[key];
    if (last && [[NSDate date] timeIntervalSinceDate:last] < 30.0) return;
    deb[key] = [NSDate date];

    [RYGProfileAnalyzerStorage recordVisitForUser:user forUserPK:selfPK];
}

%end
