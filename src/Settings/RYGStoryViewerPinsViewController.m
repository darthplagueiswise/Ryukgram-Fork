#import "RYGStoryViewerPinsViewController.h"
#import "../Features/StoriesAndMessages/RYGStoryViewerPins.h"
#import "../Networking/RYGInstagramAPI.h"
#import "../Utils.h"
#import "../RYGProfileOpener.h"
#import "../UI/RYGAvatarLoader.h"

static NSString *SVText(id v) {
    return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @"";
}
static NSString *SVLower(id v) { return SVText(v).lowercaseString ?: @""; }
static NSString *SVAtName(NSString *s) {
    if (!s.length) return nil;
    return [s hasPrefix:@"@"] ? s : [@"@" stringByAppendingString:s];
}
static NSString *SVEncoded(NSString *s) {
    return [s stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: s;
}

static NSDictionary *SVNormalized(NSDictionary *e) {
    NSString *pk = SVText(e[@"pk"]);
    NSString *username = SVText(e[@"username"]);
    NSString *fullName = SVText(e[@"fullName"]);

    NSString *title = fullName.length ? fullName : (username.length ? SVAtName(username) : RYGLocalized(@"Unknown"));
    NSString *subtitle = username.length ? SVAtName(username) : (pk.length ? pk : @"");

    NSMutableDictionary *out = [e mutableCopy] ?: [NSMutableDictionary new];
    out[@"pk"] = pk;
    out[@"username"] = username;
    out[@"fullName"] = fullName;
    out[@"title"] = title;
    out[@"subtitle"] = subtitle;
    out[@"searchBlob"] = [NSString stringWithFormat:@"%@ %@ %@", SVLower(pk), SVLower(username), SVLower(fullName)];
    out[@"sortName"] = username.length ? username.lowercaseString : title.lowercaseString;
    out[@"addedAt"] = e[@"addedAt"] ?: @0;
    if ([e[@"avatarURL"] length]) out[@"avatarURL"] = e[@"avatarURL"];
    return out;
}

@implementation RYGStoryViewerPinsViewController

- (instancetype)init {
    RYGIDListConfig *cfg = [RYGIDListConfig new];
    cfg.title = RYGLocalized(@"Pinned viewers");
    cfg.searchPlaceholder = RYGLocalized(@"Search by username or name");
    cfg.addAlertTitle = RYGLocalized(@"Pin a viewer");
    cfg.addAlertMessage = RYGLocalized(@"Username or raw user PK. Pinned viewers always stay at the top of your story viewers list.");
    cfg.addAlertPlaceholder = RYGLocalized(@"Username or PK");
    cfg.useUserPickerForAdd = YES;
    cfg.sortTitles = @[RYGLocalized(@"Pin order"), RYGLocalized(@"Username (A–Z)")];

    cfg.itemsProvider = ^NSArray *{
        NSArray *raw = [RYGStoryViewerPins allEntries] ?: @[];
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];
        for (NSDictionary *e in raw)
            if ([e isKindOfClass:NSDictionary.class]) [items addObject:SVNormalized(e)];
        return items;
    };
    cfg.titleProvider = ^NSString *(NSDictionary *e) { return e[@"title"] ?: @""; };
    cfg.subtitleProvider = ^NSString *(NSDictionary *e) { return e[@"subtitle"] ?: @""; };
    cfg.iconProvider = ^UIImage *(NSDictionary *e) { return [RYGAvatarLoader avatarForEntry:e]; };
    cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
        NSString *query = q.lowercaseString ?: @"";
        return !query.length || [SVText(e[@"searchBlob"]) containsString:query];
    };
    cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
        if (mode == 0) return items;   // already in pin order
        return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [SVText(a[@"sortName"]) compare:SVText(b[@"sortName"])];
        }];
    };
    cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
        NSString *u = e[@"username"];
        NSString *pk = e[@"pk"];
        if (!u.length && !pk.length) return;
        [RYGProfileOpener openProfileForPK:pk username:u from:vc];
    };
    cfg.onRemoveItem = ^(NSDictionary *e) { [RYGStoryViewerPins removePK:e[@"pk"]]; };

    cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
        NSString *q = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                       stringByReplacingOccurrencesOfString:@"@" withString:@""];
        if (!q.length) return;

        BOOL numeric = [q rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
        if (numeric) {
            [RYGStoryViewerPins addOrUpdateEntry:@{@"pk": q}];
            if (reload) reload();
            return;
        }

        NSString *path = [NSString stringWithFormat:@"users/web_profile_info/?username=%@", SVEncoded(q)];
        [RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
            NSDictionary *user = resp[@"data"][@"user"];
            if (err || ![user isKindOfClass:NSDictionary.class]) {
                [RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"User '%@' not found"), q]];
                return;
            }
            NSString *pk = SVText(user[@"id"]);
            NSString *uname = SVText(user[@"username"]).length ? SVText(user[@"username"]) : q;
            NSString *fullName = SVText(user[@"full_name"]);
            NSString *pic = SVText(user[@"profile_pic_url_hd"]);
            if (!pic.length) pic = SVText(user[@"profile_pic_url"]);
            if (!pk.length) {
                [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not resolve user ID")];
                return;
            }
            NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Pin this viewer?")
                                                                            message:msg
                                                                     preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Pin") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
                NSMutableDictionary *entry = [@{@"pk": pk, @"username": uname, @"fullName": fullName} mutableCopy];
                if (pic.length) { entry[@"avatarURL"] = pic; entry[@"profilePicURL"] = pic; }
                [RYGStoryViewerPins addOrUpdateEntry:entry];
                if (reload) reload();
            }]];
            [vc presentViewController:confirm animated:YES completion:nil];
        }];
    };

    return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGAvatarLoadedNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
