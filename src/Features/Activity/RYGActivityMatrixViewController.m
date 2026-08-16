#import "RYGActivityMatrixViewController.h"
#import "RYGActivityPersonViewController.h"
#import "RYGActivityConfig.h"
#import "../StoriesAndMessages/RYGDirectUserResolver.h"
#import "../../UI/RYGAvatarLoader.h"

static NSString *amStr(id v) { return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @""; }

static NSString *amUsername(NSString *pk) {
    NSString *u = [RYGActivityConfig overrideUsernameForPK:pk];
    if (!u.length) u = rygDirectUserResolverUsernameForPK(pk);
    return u;
}
static NSString *amPic(NSString *pk) {
    NSString *p = [RYGActivityConfig overridePicURLForPK:pk];
    if (!p.length) p = rygDirectUserResolverPicForPK(pk);
    return p;
}

static RYGActivityType amAllTypes(void) {
    RYGActivityType all = 0;
    for (NSNumber *n in RYGActivityConfig.allTypes) all |= (RYGActivityType)n.unsignedIntegerValue;
    return all;
}
static NSString *amShort(RYGActivityType mask) {
    if (mask == 0) return RYGLocalized(@"Off");
    if (mask == amAllTypes()) return RYGLocalized(@"All");
    NSMutableArray *names = [NSMutableArray array];
    for (NSNumber *n in RYGActivityConfig.allTypes) {
        RYGActivityType t = (RYGActivityType)n.unsignedIntegerValue;
        if (mask & t) [names addObject:[RYGActivityConfig titleForType:t]];
    }
    return [names componentsJoinedByString:@", "];
}
static NSString *amSummary(RYGActivityType notify, RYGActivityType log) {
    if (notify == 0 && log == 0) return RYGLocalized(@"Muted");
    if (notify == log) return amShort(notify);
    return [NSString stringWithFormat:RYGLocalized(@"Notify: %@ · Log: %@"), amShort(notify), amShort(log)];
}

@implementation RYGActivityMatrixViewController

- (instancetype)init {
    RYGIDListConfig *cfg = [RYGIDListConfig new];
    cfg.title = RYGLocalized(@"Per-person notifications");
    cfg.searchPlaceholder = RYGLocalized(@"Search by username");
    cfg.addAlertTitle = RYGLocalized(@"Notify about someone");
    cfg.allowsEdit = NO;

    cfg.itemsProvider = ^NSArray *{
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *pk in [RYGActivityConfig peopleWithOverrides]) {
            NSString *un = amUsername(pk);
            [out addObject:@{ @"pk": pk, @"username": un ?: @"", @"pic": amPic(pk) ?: @"",
                              @"notify": @([RYGActivityConfig overrideMaskForPK:pk]),
                              @"log": @([RYGActivityConfig overrideLogMaskForPK:pk]) }];
        }
        return out;
    };
    cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
        return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [amStr(a[@"username"]) caseInsensitiveCompare:amStr(b[@"username"])];
        }];
    };
    cfg.titleProvider = ^NSString *(NSDictionary *e) {
        NSString *un = amStr(e[@"username"]);
        return un.length ? [@"@" stringByAppendingString:un] : amStr(e[@"pk"]);
    };
    cfg.subtitleProvider = ^NSString *(NSDictionary *e) {
        return amSummary((RYGActivityType)[e[@"notify"] unsignedIntegerValue], (RYGActivityType)[e[@"log"] unsignedIntegerValue]);
    };
    cfg.iconProvider = ^UIImage *(NSDictionary *e) {
        return [RYGAvatarLoader avatarForEntry:@{ @"pk": e[@"pk"] ?: @"", @"profilePicURL": e[@"pic"] ?: @"" }];
    };
    cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
        return !q.length || [amStr(e[@"username"]).lowercaseString containsString:q] || [amStr(e[@"pk"]) containsString:q];
    };
    cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
        [vc.navigationController pushViewController:[[RYGActivityPersonViewController alloc] initWithPK:e[@"pk"] username:e[@"username"]] animated:YES];
    };
    cfg.onRemoveItem = ^(NSDictionary *e) {
        [RYGActivityConfig clearOverrideForPK:e[@"pk"]];
    };
    cfg.onAddResolvedUser = ^(NSDictionary *user, void(^reload)(void)) {
        NSString *pk = amStr(user[@"pk"]);
        if (!pk.length) return;
        RYGActivityType n = [RYGActivityConfig hasOverrideForPK:pk] ? [RYGActivityConfig overrideMaskForPK:pk] : [RYGActivityConfig globalNotifyMask];
        RYGActivityType l = [RYGActivityConfig hasLogOverrideForPK:pk] ? [RYGActivityConfig overrideLogMaskForPK:pk] : [RYGActivityConfig globalLogMask];
        [RYGActivityConfig setOverrideNotifyMask:n logMask:l forPK:pk username:amStr(user[@"username"]) picURL:amStr(user[@"profilePicURL"])];
        if (reload) reload();
    };

    self = [super initWithConfig:cfg];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGActivityConfigDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGAvatarLoadedNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
