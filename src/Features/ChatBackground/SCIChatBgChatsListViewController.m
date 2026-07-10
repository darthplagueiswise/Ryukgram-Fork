#import "SCIChatBgChatsListViewController.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgThreadPickerVC.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../StoriesAndMessages/SCIDirectUserResolver.h"

static NSCache<NSString *, UIImage *> *SCIChatBgThumbCache(void) {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSCache new];
		cache.countLimit = 80;
	});
	return cache;
}

static NSString *SCIText(id v) {
	return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @"";
}

static NSString *SCILower(id v) {
	return SCIText(v).lowercaseString ?: @"";
}

static NSString *SCITail(NSString *s, NSUInteger n) {
	if (!s.length || s.length <= n) return s ?: @"";
	return [@"…" stringByAppendingString:[s substringFromIndex:s.length - n]];
}

static NSString *SCIAtName(NSString *s) {
	s = [SCIText(s) stringByReplacingOccurrencesOfString:@"@" withString:@""];
	return s.length ? [@"@" stringByAppendingString:s] : @"";
}

static NSString *SCIEncodedQuery(NSString *s) {
	return [s stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: s;
}

static NSArray *SCIUsers(NSDictionary *meta) {
	return [meta[@"users"] isKindOfClass:NSArray.class] ? meta[@"users"] : @[];
}

static NSString *SCIUsernameForUser(NSDictionary *u) {
	NSString *name = SCIText(u[@"username"]);
	if (!name.length) name = sciDirectUserResolverUsernameForPK(SCIText(u[@"pk"]));
	return SCIAtName(name);
}

static NSString *SCIFullNameForUser(NSDictionary *u) {
	NSString *name = SCIText(u[@"fullName"]);
	if (!name.length) name = SCIText(u[@"full_name"]);
	return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *SCIJoinNames(NSDictionary *meta, BOOL fullNames) {
	NSMutableArray *out = [NSMutableArray new];

	for (NSDictionary *u in SCIUsers(meta)) {
		if (![u isKindOfClass:NSDictionary.class]) continue;
		NSString *name = fullNames ? SCIFullNameForUser(u) : SCIUsernameForUser(u);
		if (name.length) [out addObject:name];
	}

	if (!out.count && !fullNames && [meta[@"userPks"] isKindOfClass:NSArray.class]) {
		for (id pk in meta[@"userPks"]) {
			NSString *name = SCIAtName(sciDirectUserResolverUsernameForPK(SCIText(pk)));
			if (name.length) [out addObject:name];
		}
	}

	return [out componentsJoinedByString:@", "];
}

static NSDictionary *SCINormalizedEntry(NSString *tid, NSString *asset, NSDictionary *meta) {
	NSString *threadID = SCIText(tid);
	NSString *threadName = [SCIText(meta[@"threadName"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *fullLine = SCIJoinNames(meta, YES);
	NSString *userLine = SCIJoinNames(meta, NO);
	BOOL isGroup = [meta[@"isGroup"] boolValue];

	NSString *title = isGroup && threadName.length ? threadName : (fullLine.length ? fullLine : userLine);
	if (!title.length) title = threadName.length ? threadName : (threadID.length ? [NSString stringWithFormat:@"%@ %@", SCILocalized(@"Thread"), SCITail(threadID, 8)] : SCILocalized(@"Unknown"));

	NSString *subtitle = userLine.length ? userLine : (threadID.length ? [NSString stringWithFormat:@"%@ %@", SCILocalized(@"ID"), SCITail(threadID, 16)] : @"");
	if (isGroup && userLine.length) subtitle = [NSString stringWithFormat:@"%@  •  %@", SCILocalized(@"Group"), userLine];

	NSString *search = [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
		SCILower(threadID), SCILower(title), SCILower(subtitle), SCILower(threadName), SCILower(meta[@"users"])];

	return @{
		@"threadId": threadID,
		@"asset": SCIText(asset),
		@"title": title,
		@"subtitle": subtitle,
		@"searchBlob": search,
		@"sortName": title.lowercaseString ?: @"",
		@"updatedAt": meta[@"updatedAt"] ?: meta[@"createdAt"] ?: @0
	};
}

static UIImage *SCIThumb(NSString *asset) {
	if (!asset.length) return [UIImage systemImageNamed:@"photo"];

	UIImage *cached = [SCIChatBgThumbCache() objectForKey:asset];
	if (cached) return cached;

	UIImage *src = [[SCIChatBackgroundManager shared] imageForAsset:asset];
	if (!src || !src.CGImage) return [UIImage systemImageNamed:@"photo"];

	CGFloat side = MIN(src.size.width, src.size.height);
	CGRect crop = CGRectMake((src.size.width - side) * 0.5, (src.size.height - side) * 0.5, side, side);
	CGImageRef cg = CGImageCreateWithImageInRect(src.CGImage, crop);
	UIImage *square = cg ? [UIImage imageWithCGImage:cg scale:src.scale orientation:src.imageOrientation] : src;
	if (cg) CGImageRelease(cg);

	BOOL video = [SCIChatBackgroundManager isVideoAsset:asset];
	CGSize size = CGSizeMake(48, 48);
	UIGraphicsImageRendererFormat *fmt = UIGraphicsImageRendererFormat.preferredFormat;
	fmt.opaque = NO;

	UIImage *thumb = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
		[[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:13] addClip];
		[square drawInRect:(CGRect){CGPointZero, size}];
		if (video) {
			UIImage *play = [[UIImage systemImageNamed:@"play.circle.fill"] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
			CGFloat b = 18;
			[play drawInRect:CGRectMake(size.width - b - 3, size.height - b - 3, b, b)];
		}
	}];

	if (thumb) [SCIChatBgThumbCache() setObject:thumb forKey:asset];
	return thumb;
}

static NSString *SCIThreadIDForInput(NSString *input) {
	NSString *needle = [[input stringByReplacingOccurrencesOfString:@"@" withString:@""] lowercaseString];
	if (!needle.length) return nil;

	SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];
	for (NSString *tid in [m allThreadAssets]) {
		NSDictionary *meta = [m metadataForThreadID:tid] ?: @{};
		if ([tid.lowercaseString isEqualToString:needle]) return tid;
		if ([SCILower(meta[@"threadName"]) containsString:needle]) return tid;
		if ([SCILower(meta[@"users"]) containsString:needle]) return tid;
		if ([SCILower(meta[@"userPks"]) containsString:needle]) return tid;
	}
	return input;
}

@implementation SCIChatBgChatsListViewController

- (instancetype)init {
	SCIIDListConfig *cfg = [SCIIDListConfig new];

	cfg.title = SCILocalized(@"Chat Backgrounds");
	cfg.searchPlaceholder = SCILocalized(@"Search username, name, or thread ID");
	cfg.addAlertTitle = SCILocalized(@"Add Chat Background");
	cfg.addAlertMessage = SCILocalized(@"Enter a username, chat name, or thread ID.");
	cfg.addAlertPlaceholder = SCILocalized(@"Username or thread ID");
	cfg.allowsAdd = YES;
	cfg.allowsEdit = YES;
	cfg.sortTitles = @[SCILocalized(@"Recently set"), SCILocalized(@"Name"), SCILocalized(@"Thread ID")];

	cfg.itemsProvider = ^NSArray *{
		SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];
		NSDictionary<NSString *, NSString *> *map = [m allThreadAssets];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:map.count];

		for (NSString *tid in map) {
			[items addObject:SCINormalizedEntry(tid, map[tid], [m metadataForThreadID:tid] ?: @{})];
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
		return SCIThumb(e[@"asset"]);
	};

	cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
		NSString *query = q.lowercaseString ?: @"";
		return !query.length || [SCIText(e[@"searchBlob"]) containsString:query];
	};

	cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
		return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			if (mode == 0) {
				double da = [a[@"updatedAt"] doubleValue], db = [b[@"updatedAt"] doubleValue];
				if (da > db) return NSOrderedAscending;
				if (da < db) return NSOrderedDescending;
			}
			return mode == 1 ? [SCIText(a[@"sortName"]) compare:SCIText(b[@"sortName"])]
							 : [SCIText(a[@"threadId"]) compare:SCIText(b[@"threadId"])];
		}];
	};

	cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
		[SCIPopupChrome presentVC:[[SCIChatBgThreadPickerVC alloc] initWithThreadID:e[@"threadId"]] from:vc];
	};

	cfg.onAddRequest = ^(NSString *query, UIViewController *vc, void(^reload)(void)) {
		NSString *input = [[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"@" withString:@""];
		if (!input.length) return;

		BOOL numeric = [input rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
		if (numeric) {
			NSString *tid = SCIThreadIDForInput(input);
			[SCIPopupChrome presentVC:[[SCIChatBgThreadPickerVC alloc] initWithThreadID:tid] from:vc];
			if (reload) reload();
			return;
		}

		[SCIInstagramAPI sendRequestWithMethod:@"GET"
										  path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", SCIEncodedQuery(input)]
										  body:nil
									completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (err || ![user isKindOfClass:NSDictionary.class]) {
				[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), input]];
				return;
			}

			NSString *pk = SCIText(user[@"id"]);
			NSString *uname = SCIText(user[@"username"]).length ? SCIText(user[@"username"]) : input;
			NSString *full = SCIText(user[@"full_name"]);
			if (!pk.length) {
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")];
				return;
			}

			[SCIInstagramAPI sendRequestWithMethod:@"GET"
											  path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", SCIEncodedQuery(pk)]
											  body:nil
										completion:^(NSDictionary *threadResp, NSError *tErr) {
				NSDictionary *thread = [threadResp[@"thread"] isKindOfClass:NSDictionary.class] ? threadResp[@"thread"] : nil;
				if (!thread && [threadResp[@"threads"] isKindOfClass:NSArray.class]) thread = [threadResp[@"threads"] firstObject];

				NSString *tid = SCIText(thread[@"thread_id"]);
				if (tErr || !tid.length) {
					[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"No DM thread found with @%@"), uname]];
					return;
				}

				[[SCIChatBackgroundManager shared] setMetadata:@{
					@"threadName": full.length ? full : uname,
					@"isGroup": @NO,
					@"userPks": @[pk],
					@"users": @[@{@"pk": pk, @"username": uname, @"fullName": full}],
					@"updatedAt": @([[NSDate date] timeIntervalSince1970])
				} forThreadID:tid];

				[SCIPopupChrome presentVC:[[SCIChatBgThreadPickerVC alloc] initWithThreadID:tid] from:vc];
				if (reload) reload();
			}];
		}];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[[SCIChatBackgroundManager shared] clearAssetForThreadID:e[@"threadId"]];
	};

	cfg.contextMenuForItem = ^UIMenu *(NSDictionary *e, void(^reload)(void)) {
		UIAction *edit = [UIAction actionWithTitle:SCILocalized(@"Change Background") image:[UIImage systemImageNamed:@"photo.on.rectangle"] identifier:nil handler:^(__unused UIAction *_) {
			[SCIPopupChrome presentVC:[[SCIChatBgThreadPickerVC alloc] initWithThreadID:e[@"threadId"]] from:topMostController()];
		}];

		UIAction *remove = [UIAction actionWithTitle:SCILocalized(@"Remove") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *_) {
			[[SCIChatBackgroundManager shared] clearAssetForThreadID:e[@"threadId"]];
			if (reload) reload();
		}];

		remove.attributes = UIMenuElementAttributesDestructive;
		return [UIMenu menuWithTitle:@"" children:@[edit, remove]];
	};

	return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SCIChatBackgroundDidChangeNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end