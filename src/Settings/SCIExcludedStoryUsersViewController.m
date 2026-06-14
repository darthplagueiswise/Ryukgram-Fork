#import "SCIExcludedStoryUsersViewController.h"
#import "../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import "../Networking/SCIInstagramAPI.h"
#import "../Utils.h"
#import "../SCIURLOpener.h"
#import "../UI/SCIAvatarLoader.h"

static NSString *SCIText(id v) {
	return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @"";
}

static NSString *SCILower(id v) {
	return SCIText(v).lowercaseString ?: @"";
}

static NSString *SCIAtName(NSString *s) {
	if (!s.length) return nil;
	return [s hasPrefix:@"@"] ? s : [@"@" stringByAppendingString:s];
}

static NSString *SCIEncodedQuery(NSString *s) {
	return [s stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: s;
}

static NSDictionary *SCINormalizedStoryUser(NSDictionary *e) {
	NSString *pk = SCIText(e[@"pk"]);
	NSString *username = SCIText(e[@"username"]);
	NSString *fullName = SCIText(e[@"fullName"]);

	NSString *title = fullName.length ? fullName : (username.length ? SCIAtName(username) : SCILocalized(@"Unknown"));
	NSString *subtitle = username.length ? SCIAtName(username) : (pk.length ? pk : @"");

	NSString *searchBlob = [NSString stringWithFormat:@"%@ %@ %@",
		SCILower(pk),
		SCILower(username),
		SCILower(fullName)
	];

	NSMutableDictionary *out = [e mutableCopy] ?: [NSMutableDictionary new];
	out[@"pk"] = pk;
	out[@"username"] = username;
	out[@"fullName"] = fullName;
	out[@"title"] = title;
	out[@"subtitle"] = subtitle;
	out[@"searchBlob"] = searchBlob;
	out[@"sortName"] = username.length ? username.lowercaseString : title.lowercaseString;
	out[@"addedAt"] = e[@"addedAt"] ?: @0;

	return out;
}

@implementation SCIExcludedStoryUsersViewController

- (instancetype)init {
	SCIIDListConfig *cfg = [SCIIDListConfig new];

	cfg.title = SCILocalized(@"Excluded users");
	cfg.searchPlaceholder = SCILocalized(@"Search by username or name");
	cfg.addAlertTitle = SCILocalized(@"Add user");
	cfg.addAlertMessage = SCILocalized(@"Username or raw user PK");
	cfg.addAlertPlaceholder = SCILocalized(@"Username or PK");
	cfg.sortTitles = @[SCILocalized(@"Recently added"), SCILocalized(@"Username (A–Z)")];

	cfg.itemsProvider = ^NSArray *{
		NSArray *raw = [SCIExcludedStoryUsers allEntries] ?: @[];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];

		for (NSDictionary *e in raw) {
			if ([e isKindOfClass:NSDictionary.class]) [items addObject:SCINormalizedStoryUser(e)];
		}

		return items;
	};

	cfg.titleProvider = ^NSString *(NSDictionary *e) {
		return e[@"title"] ?: @"";
	};

	cfg.subtitleProvider = ^NSString *(NSDictionary *e) {
		return e[@"subtitle"] ?: @"";
	};

	cfg.iconProvider = ^UIImage *(NSDictionary *e) {
		return [SCIAvatarLoader avatarForEntry:e];
	};

	cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
		NSString *query = q.lowercaseString ?: @"";
		return !query.length || [SCIText(e[@"searchBlob"]) containsString:query];
	};

	cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
		return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			if (mode == 0) {
				double da = [a[@"addedAt"] doubleValue];
				double db = [b[@"addedAt"] doubleValue];
				if (da > db) return NSOrderedAscending;
				if (da < db) return NSOrderedDescending;
			}

			return [SCIText(a[@"sortName"]) compare:SCIText(b[@"sortName"])];
		}];
	};

	cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
		NSString *u = e[@"username"];
		if (!u.length) return;

		[vc.navigationController dismissViewControllerAnimated:YES completion:^{
			[SCIURLOpener openInstagramProfileForUsername:u];
		}];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[SCIExcludedStoryUsers removePK:e[@"pk"]];
	};

	cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
		NSString *q = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"@" withString:@""];
		if (!q.length) return;

		BOOL numeric = [q rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
		if (numeric) {
			[SCIExcludedStoryUsers addOrUpdateEntry:@{@"pk": q}];
			if (reload) reload();
			return;
		}

		NSString *query = q;
		NSString *path = [NSString stringWithFormat:@"users/web_profile_info/?username=%@", SCIEncodedQuery(query)];

		[SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (err || ![user isKindOfClass:NSDictionary.class]) {
				[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), query]];
				return;
			}

			NSString *pk = SCIText(user[@"id"]);
			NSString *uname = SCIText(user[@"username"]).length ? SCIText(user[@"username"]) : query;
			NSString *fullName = SCIText(user[@"full_name"]);
			NSString *pic = SCIText(user[@"profile_pic_url_hd"]);
			if (!pic.length) pic = SCIText(user[@"profile_pic_url"]);

			if (!pk.length) {
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")];
				return;
			}

			NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];

			UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add to list?")
																			 message:msg
																	  preferredStyle:UIAlertControllerStyleAlert];

			[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
			[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
				NSMutableDictionary *entry = [@{
					@"pk": pk,
					@"username": uname,
					@"fullName": fullName,
					@"profilePicURL": pic ?: @""
				} mutableCopy];

				if (pic.length) entry[@"avatarURL"] = pic;

				[SCIExcludedStoryUsers addOrUpdateEntry:entry];
				if (reload) reload();
			}]];

			[vc presentViewController:confirm animated:YES completion:nil];
		}];
	};

	return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIUIKit26ConfigureViewController(self);
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SCIAvatarLoadedNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	self.config.title = [SCIExcludedStoryUsers isBlockSelectedMode] ? SCILocalized(@"Included users") : SCILocalized(@"Excluded users");
	[super viewWillAppear:animated];
}

@end
