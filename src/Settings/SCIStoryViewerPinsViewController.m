#import "SCIStoryViewerPinsViewController.h"
#import "../Features/StoriesAndMessages/SCIStoryViewerPins.h"
#import "../Networking/SCIInstagramAPI.h"
#import "../Utils.h"
#import "../SCIURLOpener.h"
#import "../UI/SCIAvatarLoader.h"

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

    NSString *title = fullName.length ? fullName : (username.length ? SVAtName(username) : SCILocalized(@"Unknown"));
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

@implementation SCIStoryViewerPinsViewController

- (instancetype)init {
    SCIIDListConfig *cfg = [SCIIDListConfig new];
    cfg.title = SCILocalized(@"Pinned viewers");
    cfg.searchPlaceholder = SCILocalized(@"Search by username or name");
    cfg.addAlertTitle = SCILocalized(@"Pin a viewer");
    cfg.addAlertMessage = SCILocalized(@"Username or raw user PK. Pinned viewers always stay at the top of your story viewers list.");
    cfg.addAlertPlaceholder = SCILocalized(@"Username or PK");
    cfg.sortTitles = @[SCILocalized(@"Pin order"), SCILocalized(@"Username (A–Z)")];

    cfg.itemsProvider = ^NSArray *{
        NSArray *raw = [SCIStoryViewerPins allEntries] ?: @[];
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];
        for (NSDictionary *e in raw)
            if ([e isKindOfClass:NSDictionary.class]) [items addObject:SVNormalized(e)];
        return items;
    };
    cfg.titleProvider = ^NSString *(NSDictionary *e) { return e[@"title"] ?: @""; };
    cfg.subtitleProvider = ^NSString *(NSDictionary *e) { return e[@"subtitle"] ?: @""; };
    cfg.iconProvider = ^UIImage *(NSDictionary *e) { return [SCIAvatarLoader avatarForEntry:e]; };
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
        if (!u.length) return;
        [vc.navigationController dismissViewControllerAnimated:YES completion:^{
            [SCIURLOpener openInstagramProfileForUsername:u];
        }];
    };
    cfg.onRemoveItem = ^(NSDictionary *e) { [SCIStoryViewerPins removePK:e[@"pk"]]; };

    cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
        NSString *q = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                       stringByReplacingOccurrencesOfString:@"@" withString:@""];
        if (!q.length) return;

        BOOL numeric = [q rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
        if (numeric) {
            [SCIStoryViewerPins addOrUpdateEntry:@{@"pk": q}];
            if (reload) reload();
            return;
        }

        NSString *path = [NSString stringWithFormat:@"users/web_profile_info/?username=%@", SVEncoded(q)];
        [SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
            NSDictionary *user = resp[@"data"][@"user"];
            if (err || ![user isKindOfClass:NSDictionary.class]) {
                [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), q]];
                return;
            }
            NSString *pk = SVText(user[@"id"]);
            NSString *uname = SVText(user[@"username"]).length ? SVText(user[@"username"]) : q;
            NSString *fullName = SVText(user[@"full_name"]);
            NSString *pic = SVText(user[@"profile_pic_url_hd"]);
            if (!pic.length) pic = SVText(user[@"profile_pic_url"]);
            if (!pk.length) {
                [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")];
                return;
            }
            NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Pin this viewer?")
                                                                            message:msg
                                                                     preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Pin") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
                NSMutableDictionary *entry = [@{@"pk": pk, @"username": uname, @"fullName": fullName} mutableCopy];
                if (pic.length) { entry[@"avatarURL"] = pic; entry[@"profilePicURL"] = pic; }
                [SCIStoryViewerPins addOrUpdateEntry:entry];
                if (reload) reload();
            }]];
            [vc presentViewController:confirm animated:YES completion:nil];
        }];
    };

    return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SCIAvatarLoadedNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
