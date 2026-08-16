#import "RYGExcludedStoryUsersViewController.h"
#import "../Features/StoriesAndMessages/RYGExcludedStoryUsers.h"
#import "../Networking/RYGInstagramAPI.h"
#import "../Utils.h"
#import "../RYGProfileOpener.h"
#import "../UI/RYGAvatarLoader.h"

static NSString *RYGText(id v) {
	return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @"";
}

static NSString *RYGLower(id v) {
	return RYGText(v).lowercaseString ?: @"";
}

static NSString *RYGAtName(NSString *s) {
	if (!s.length) return nil;
	return [s hasPrefix:@"@"] ? s : [@"@" stringByAppendingString:s];
}

static NSDictionary *RYGNormalizedStoryUser(NSDictionary *e) {
	NSString *pk = RYGText(e[@"pk"]);
	NSString *username = RYGText(e[@"username"]);
	NSString *fullName = RYGText(e[@"fullName"]);

	NSString *title = fullName.length ? fullName : (username.length ? RYGAtName(username) : RYGLocalized(@"Unknown"));
	NSString *subtitle = username.length ? RYGAtName(username) : (pk.length ? pk : @"");

	NSString *searchBlob = [NSString stringWithFormat:@"%@ %@ %@",
		RYGLower(pk),
		RYGLower(username),
		RYGLower(fullName)
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

@implementation RYGExcludedStoryUsersViewController

- (instancetype)init {
	RYGIDListConfig *cfg = [RYGIDListConfig new];

	cfg.title = RYGLocalized(@"Excluded users");
	cfg.searchPlaceholder = RYGLocalized(@"Search by username or name");
	cfg.addAlertTitle = RYGLocalized(@"Add user");
	cfg.addAlertMessage = RYGLocalized(@"Username or raw user PK");
	cfg.addAlertPlaceholder = RYGLocalized(@"Username or PK");
	cfg.sortTitles = @[RYGLocalized(@"Recently added"), RYGLocalized(@"Username (A–Z)")];

	cfg.itemsProvider = ^NSArray *{
		NSArray *raw = [RYGExcludedStoryUsers allEntries] ?: @[];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];

		for (NSDictionary *e in raw) {
			if ([e isKindOfClass:NSDictionary.class]) [items addObject:RYGNormalizedStoryUser(e)];
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
		return [RYGAvatarLoader avatarForEntry:e];
	};

	cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
		NSString *query = q.lowercaseString ?: @"";
		return !query.length || [RYGText(e[@"searchBlob"]) containsString:query];
	};

	cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
		return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			if (mode == 0) {
				double da = [a[@"addedAt"] doubleValue];
				double db = [b[@"addedAt"] doubleValue];
				if (da > db) return NSOrderedAscending;
				if (da < db) return NSOrderedDescending;
			}

			return [RYGText(a[@"sortName"]) compare:RYGText(b[@"sortName"])];
		}];
	};

	cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
		NSString *u = e[@"username"];
		NSString *pk = RYGText(e[@"pk"]);
		if (!u.length && !pk.length) return;
		[RYGProfileOpener openProfileForPK:pk username:u from:vc];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[RYGExcludedStoryUsers removePK:e[@"pk"]];
	};

	cfg.onAddResolvedUser = ^(NSDictionary *user, void(^reload)(void)) {
		NSString *pk = RYGText(user[@"pk"]);
		if (!pk.length) return;
		NSMutableDictionary *entry = [@{
			@"pk": pk,
			@"username": RYGText(user[@"username"]),
			@"fullName": RYGText(user[@"fullName"]),
			@"profilePicURL": RYGText(user[@"profilePicURL"])
		} mutableCopy];
		if (RYGText(user[@"profilePicURL"]).length) entry[@"avatarURL"] = RYGText(user[@"profilePicURL"]);
		[RYGExcludedStoryUsers addOrUpdateEntry:entry];
		if (reload) reload();
	};

	return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGAvatarLoadedNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	self.config.title = [RYGExcludedStoryUsers isBlockSelectedMode] ? RYGLocalized(@"Included users") : RYGLocalized(@"Excluded users");
	[super viewWillAppear:animated];
}

@end