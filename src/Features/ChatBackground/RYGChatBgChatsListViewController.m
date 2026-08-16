#import "RYGChatBgChatsListViewController.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgThreadPickerVC.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../StoriesAndMessages/RYGDirectUserResolver.h"

static NSCache<NSString *, UIImage *> *RYGChatBgThumbCache(void) {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSCache new];
		cache.countLimit = 80;
	});
	return cache;
}

static NSString *RYGText(id v) {
	return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @"";
}

static NSString *RYGLower(id v) {
	return RYGText(v).lowercaseString ?: @"";
}

static NSString *RYGTail(NSString *s, NSUInteger n) {
	if (!s.length || s.length <= n) return s ?: @"";
	return [@"…" stringByAppendingString:[s substringFromIndex:s.length - n]];
}

static NSString *RYGAtName(NSString *s) {
	s = [RYGText(s) stringByReplacingOccurrencesOfString:@"@" withString:@""];
	return s.length ? [@"@" stringByAppendingString:s] : @"";
}

static NSString *RYGEncodedQuery(NSString *s) {
	return [s stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: s;
}

static NSArray *RYGUsers(NSDictionary *meta) {
	return [meta[@"users"] isKindOfClass:NSArray.class] ? meta[@"users"] : @[];
}

static NSString *RYGUsernameForUser(NSDictionary *u) {
	NSString *name = RYGText(u[@"username"]);
	if (!name.length) name = rygDirectUserResolverUsernameForPK(RYGText(u[@"pk"]));
	return RYGAtName(name);
}

static NSString *RYGFullNameForUser(NSDictionary *u) {
	NSString *name = RYGText(u[@"fullName"]);
	if (!name.length) name = RYGText(u[@"full_name"]);
	return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *RYGJoinNames(NSDictionary *meta, BOOL fullNames) {
	NSMutableArray *out = [NSMutableArray new];

	for (NSDictionary *u in RYGUsers(meta)) {
		if (![u isKindOfClass:NSDictionary.class]) continue;
		NSString *name = fullNames ? RYGFullNameForUser(u) : RYGUsernameForUser(u);
		if (name.length) [out addObject:name];
	}

	if (!out.count && !fullNames && [meta[@"userPks"] isKindOfClass:NSArray.class]) {
		for (id pk in meta[@"userPks"]) {
			NSString *name = RYGAtName(rygDirectUserResolverUsernameForPK(RYGText(pk)));
			if (name.length) [out addObject:name];
		}
	}

	return [out componentsJoinedByString:@", "];
}

static NSDictionary *RYGNormalizedEntry(NSString *tid, NSString *asset, NSDictionary *meta) {
	NSString *threadID = RYGText(tid);
	NSString *threadName = [RYGText(meta[@"threadName"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *fullLine = RYGJoinNames(meta, YES);
	NSString *userLine = RYGJoinNames(meta, NO);
	BOOL isGroup = [meta[@"isGroup"] boolValue];

	NSString *title = isGroup && threadName.length ? threadName : (fullLine.length ? fullLine : userLine);
	if (!title.length) title = threadName.length ? threadName : (threadID.length ? [NSString stringWithFormat:@"%@ %@", RYGLocalized(@"Thread"), RYGTail(threadID, 8)] : RYGLocalized(@"Unknown"));

	NSString *subtitle = userLine.length ? userLine : (threadID.length ? [NSString stringWithFormat:@"%@ %@", RYGLocalized(@"ID"), RYGTail(threadID, 16)] : @"");
	if (isGroup && userLine.length) subtitle = [NSString stringWithFormat:@"%@  •  %@", RYGLocalized(@"Group"), userLine];

	NSString *search = [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
		RYGLower(threadID), RYGLower(title), RYGLower(subtitle), RYGLower(threadName), RYGLower(meta[@"users"])];

	return @{
		@"threadId": threadID,
		@"asset": RYGText(asset),
		@"title": title,
		@"subtitle": subtitle,
		@"searchBlob": search,
		@"sortName": title.lowercaseString ?: @"",
		@"updatedAt": meta[@"updatedAt"] ?: meta[@"createdAt"] ?: @0
	};
}

static UIImage *RYGThumb(NSString *asset) {
	if (!asset.length) return [UIImage systemImageNamed:@"photo"];

	UIImage *cached = [RYGChatBgThumbCache() objectForKey:asset];
	if (cached) return cached;

	UIImage *src = [[RYGChatBackgroundManager shared] imageForAsset:asset];
	if (!src || !src.CGImage) return [UIImage systemImageNamed:@"photo"];

	CGFloat side = MIN(src.size.width, src.size.height);
	CGRect crop = CGRectMake((src.size.width - side) * 0.5, (src.size.height - side) * 0.5, side, side);
	CGImageRef cg = CGImageCreateWithImageInRect(src.CGImage, crop);
	UIImage *square = cg ? [UIImage imageWithCGImage:cg scale:src.scale orientation:src.imageOrientation] : src;
	if (cg) CGImageRelease(cg);

	BOOL video = [RYGChatBackgroundManager isVideoAsset:asset];
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

	if (thumb) [RYGChatBgThumbCache() setObject:thumb forKey:asset];
	return thumb;
}

static NSString *RYGThreadIDForInput(NSString *input) {
	NSString *needle = [[input stringByReplacingOccurrencesOfString:@"@" withString:@""] lowercaseString];
	if (!needle.length) return nil;

	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	for (NSString *tid in [m allThreadAssets]) {
		NSDictionary *meta = [m metadataForThreadID:tid] ?: @{};
		if ([tid.lowercaseString isEqualToString:needle]) return tid;
		if ([RYGLower(meta[@"threadName"]) containsString:needle]) return tid;
		if ([RYGLower(meta[@"users"]) containsString:needle]) return tid;
		if ([RYGLower(meta[@"userPks"]) containsString:needle]) return tid;
	}
	return input;
}

@implementation RYGChatBgChatsListViewController

- (instancetype)init {
	RYGIDListConfig *cfg = [RYGIDListConfig new];

	cfg.title = RYGLocalized(@"Chat Backgrounds");
	cfg.searchPlaceholder = RYGLocalized(@"Search username, name, or thread ID");
	cfg.addAlertTitle = RYGLocalized(@"Add Chat Background");
	cfg.addAlertMessage = RYGLocalized(@"Enter a username, chat name, or thread ID.");
	cfg.addAlertPlaceholder = RYGLocalized(@"Username or thread ID");
	cfg.useUserPickerForAdd = YES;
	cfg.addIDLabel = RYGLocalized(@"Add by thread ID");
	cfg.allowsAdd = YES;
	cfg.allowsEdit = YES;
	cfg.sortTitles = @[RYGLocalized(@"Recently set"), RYGLocalized(@"Name"), RYGLocalized(@"Thread ID")];

	cfg.itemsProvider = ^NSArray *{
		RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
		NSDictionary<NSString *, NSString *> *map = [m allThreadAssets];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:map.count];

		for (NSString *tid in map) {
			[items addObject:RYGNormalizedEntry(tid, map[tid], [m metadataForThreadID:tid] ?: @{})];
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
		return RYGThumb(e[@"asset"]);
	};

	cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
		NSString *query = q.lowercaseString ?: @"";
		return !query.length || [RYGText(e[@"searchBlob"]) containsString:query];
	};

	cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
		return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			if (mode == 0) {
				double da = [a[@"updatedAt"] doubleValue], db = [b[@"updatedAt"] doubleValue];
				if (da > db) return NSOrderedAscending;
				if (da < db) return NSOrderedDescending;
			}
			return mode == 1 ? [RYGText(a[@"sortName"]) compare:RYGText(b[@"sortName"])]
							 : [RYGText(a[@"threadId"]) compare:RYGText(b[@"threadId"])];
		}];
	};

	cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
		[RYGPopupChrome presentVC:[[RYGChatBgThreadPickerVC alloc] initWithThreadID:e[@"threadId"]] from:vc];
	};

	cfg.onAddRequest = ^(NSString *query, UIViewController *vc, void(^reload)(void)) {
		NSString *input = [[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"@" withString:@""];
		if (!input.length) return;

		BOOL numeric = [input rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
		if (numeric) {
			NSString *tid = RYGThreadIDForInput(input);
			[RYGPopupChrome presentVC:[[RYGChatBgThreadPickerVC alloc] initWithThreadID:tid] from:vc];
			if (reload) reload();
			return;
		}

		[RYGInstagramAPI sendRequestWithMethod:@"GET"
										  path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", RYGEncodedQuery(input)]
										  body:nil
									completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (err || ![user isKindOfClass:NSDictionary.class]) {
				[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"User '%@' not found"), input]];
				return;
			}

			NSString *pk = RYGText(user[@"id"]);
			NSString *uname = RYGText(user[@"username"]).length ? RYGText(user[@"username"]) : input;
			NSString *full = RYGText(user[@"full_name"]);
			if (!pk.length) {
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not resolve user ID")];
				return;
			}

			[RYGInstagramAPI sendRequestWithMethod:@"GET"
											  path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", RYGEncodedQuery(pk)]
											  body:nil
										completion:^(NSDictionary *threadResp, NSError *tErr) {
				NSDictionary *thread = [threadResp[@"thread"] isKindOfClass:NSDictionary.class] ? threadResp[@"thread"] : nil;
				if (!thread && [threadResp[@"threads"] isKindOfClass:NSArray.class]) thread = [threadResp[@"threads"] firstObject];

				NSString *tid = RYGText(thread[@"thread_id"]);
				if (tErr || !tid.length) {
					[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"No DM thread found with @%@"), uname]];
					return;
				}

				[[RYGChatBackgroundManager shared] setMetadata:@{
					@"threadName": full.length ? full : uname,
					@"isGroup": @NO,
					@"userPks": @[pk],
					@"users": @[@{@"pk": pk, @"username": uname, @"fullName": full}],
					@"updatedAt": @([[NSDate date] timeIntervalSince1970])
				} forThreadID:tid];

				[RYGPopupChrome presentVC:[[RYGChatBgThreadPickerVC alloc] initWithThreadID:tid] from:vc];
				if (reload) reload();
			}];
		}];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[[RYGChatBackgroundManager shared] clearAssetForThreadID:e[@"threadId"]];
	};

	cfg.contextMenuForItem = ^UIMenu *(NSDictionary *e, void(^reload)(void)) {
		UIAction *edit = [UIAction actionWithTitle:RYGLocalized(@"Change Background") image:[UIImage systemImageNamed:@"photo.on.rectangle"] identifier:nil handler:^(__unused UIAction *_) {
			[RYGPopupChrome presentVC:[[RYGChatBgThreadPickerVC alloc] initWithThreadID:e[@"threadId"]] from:topMostController()];
		}];

		UIAction *remove = [UIAction actionWithTitle:RYGLocalized(@"Remove") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *_) {
			[[RYGChatBackgroundManager shared] clearAssetForThreadID:e[@"threadId"]];
			if (reload) reload();
		}];

		remove.attributes = UIMenuElementAttributesDestructive;
		return [UIMenu menuWithTitle:@"" children:@[edit, remove]];
	};

	return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGChatBackgroundDidChangeNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end