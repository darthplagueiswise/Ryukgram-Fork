#import "RYGExcludedChatsViewController.h"
#import "../Features/StoriesAndMessages/RYGExcludedThreads.h"
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

static NSString *RYGTail(NSString *s, NSUInteger n) {
	if (!s.length || s.length <= n) return s ?: @"";
	return [@"…" stringByAppendingString:[s substringFromIndex:s.length - n]];
}

static NSString *RYGAtName(NSString *s) {
	if (!s.length) return nil;
	return [s hasPrefix:@"@"] ? s : [@"@" stringByAppendingString:s];
}

static NSString *RYGEncodedQuery(NSString *s) {
	NSCharacterSet *allowed = NSCharacterSet.URLQueryAllowedCharacterSet;
	return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: s;
}

static NSString *RYGUsersLine(NSArray *users) {
	NSMutableArray *names = [NSMutableArray new];

	for (NSDictionary *u in users) {
		if (![u isKindOfClass:NSDictionary.class]) continue;

		NSString *name = RYGAtName(RYGText(u[@"username"]));
		if (name.length) [names addObject:name];
	}

	return [names componentsJoinedByString:@", "];
}

static NSString *RYGKeepDeletedText(NSDictionary *e) {
	RYGKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
	if (mode == RYGKeepDeletedOverrideExcluded) return RYGLocalized(@"Keep-deleted: OFF");
	if (mode == RYGKeepDeletedOverrideIncluded) return RYGLocalized(@"Keep-deleted: ON");
	return @"";
}

static NSDictionary *RYGNormalizedEntry(NSDictionary *e) {
	NSString *tid = RYGText(e[@"threadId"]);
	NSString *name = RYGText(e[@"threadName"]);
	BOOL group = [e[@"isGroup"] boolValue];
	NSArray *users = [e[@"users"] isKindOfClass:NSArray.class] ? e[@"users"] : @[];
	NSString *usersLine = RYGUsersLine(users);
	NSString *kd = RYGKeepDeletedText(e);

	if (!name.length) name = tid.length ? [NSString stringWithFormat:@"%@ %@", RYGLocalized(@"Thread"), RYGTail(tid, 8)] : RYGLocalized(@"Unknown");

	NSMutableArray *sub = [NSMutableArray new];
	if (usersLine.length) [sub addObject:usersLine];
	if (kd.length) [sub addObject:kd];
	if (!sub.count && tid.length) [sub addObject:tid];

	NSString *searchBlob = [NSString stringWithFormat:@"%@ %@ %@ %@",
		RYGLower(tid),
		RYGLower(name),
		RYGLower(usersLine),
		RYGLower(users)
	];

	NSMutableDictionary *out = [e mutableCopy] ?: [NSMutableDictionary new];
	out[@"threadId"] = tid;
	out[@"threadName"] = name;
	out[@"isGroup"] = @(group);
	out[@"users"] = users;
	out[@"title"] = name;
	out[@"subtitle"] = [sub componentsJoinedByString:@"  •  "] ?: @"";
	out[@"searchBlob"] = searchBlob ?: @"";
	out[@"sortName"] = name.lowercaseString ?: @"";
	out[@"addedAt"] = e[@"addedAt"] ?: @0;

	return out;
}

@implementation RYGExcludedChatsViewController

- (instancetype)init {
	RYGIDListConfig *cfg = [RYGIDListConfig new];

	cfg.title = [RYGExcludedThreads isBlockSelectedMode] ? RYGLocalized(@"Included chats") : RYGLocalized(@"Excluded chats");
	cfg.searchPlaceholder = RYGLocalized(@"Search by name or username");
	cfg.addAlertTitle = RYGLocalized(@"Add chat");
	cfg.addAlertMessage = RYGLocalized(@"Username (looks up the DM thread) or raw thread ID");
	cfg.addAlertPlaceholder = RYGLocalized(@"Username or thread ID");
	cfg.useUserPickerForAdd = YES;
	cfg.addIDLabel = RYGLocalized(@"Add by thread ID");
	cfg.sortTitles = @[RYGLocalized(@"Recently added"), RYGLocalized(@"Name (A–Z)")];

	cfg.itemsProvider = ^NSArray *{
		NSArray *raw = [RYGExcludedThreads allEntries] ?: @[];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];

		for (NSDictionary *e in raw) {
			if ([e isKindOfClass:NSDictionary.class]) [items addObject:RYGNormalizedEntry(e)];
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
		if ([e[@"isGroup"] boolValue]) return;

		NSArray *users = [e[@"users"] isKindOfClass:NSArray.class] ? e[@"users"] : @[];
		NSDictionary *u = users.count == 1 && [users.firstObject isKindOfClass:NSDictionary.class] ? users.firstObject : nil;
		NSString *username = RYGText(u[@"username"]);
		NSString *pk = RYGText(u[@"pk"]);
		if (!username.length && !pk.length) return;
		[RYGProfileOpener openProfileForPK:pk username:username from:vc];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[RYGExcludedThreads removeThreadId:e[@"threadId"]];
	};

	cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
		NSString *q = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"@" withString:@""];
		if (!q.length) return;

		BOOL numeric = [q rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
		if (numeric) {
			[RYGExcludedThreads addOrUpdateEntry:@{
				@"threadId": q,
				@"threadName": [NSString stringWithFormat:@"%@ %@", RYGLocalized(@"Thread"), RYGTail(q, 8)]
			}];
			if (reload) reload();
			return;
		}

		NSString *profilePath = [NSString stringWithFormat:@"users/web_profile_info/?username=%@", RYGEncodedQuery(q)];
		[RYGInstagramAPI sendRequestWithMethod:@"GET" path:profilePath body:nil completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (err || ![user isKindOfClass:NSDictionary.class]) {
				[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"User '%@' not found"), q]];
				return;
			}

			NSString *pk = RYGText(user[@"id"]);
			NSString *uname = RYGText(user[@"username"]).length ? RYGText(user[@"username"]) : q;
			NSString *fullName = RYGText(user[@"full_name"]);
			NSString *pic = RYGText(user[@"profile_pic_url_hd"]);
			if (!pic.length) pic = RYGText(user[@"profile_pic_url"]);

			if (!pk.length) {
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not resolve user ID")];
				return;
			}

			NSString *threadPath = [NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", RYGEncodedQuery(pk)];
			[RYGInstagramAPI sendRequestWithMethod:@"GET" path:threadPath body:nil completion:^(NSDictionary *threadResp, NSError *tErr) {
				NSDictionary *thread = [threadResp[@"thread"] isKindOfClass:NSDictionary.class] ? threadResp[@"thread"] : nil;
				if (!thread && [threadResp[@"threads"] isKindOfClass:NSArray.class]) thread = [threadResp[@"threads"] firstObject];

				NSString *threadId = RYGText(thread[@"thread_id"]);
				NSString *threadName = RYGText(thread[@"thread_title"]).length ? RYGText(thread[@"thread_title"]) : uname;

				if (tErr || !threadId.length) {
					[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"No DM thread found with @%@"), uname]];
					return;
				}

				NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];

				UIAlertController *confirm = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Add to list?")
																				 message:msg
																		  preferredStyle:UIAlertControllerStyleAlert];

				[confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
				[confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
					NSMutableDictionary *entry = [@{
						@"threadId": threadId,
						@"threadName": threadName,
						@"isGroup": @NO,
						@"users": @[@{
							@"pk": pk,
							@"username": uname,
							@"fullName": fullName,
							@"profilePicURL": pic ?: @""
						}]
					} mutableCopy];

					if (pic.length) entry[@"avatarURL"] = pic;

					[RYGExcludedThreads addOrUpdateEntry:entry];
					if (reload) reload();
				}]];

				[vc presentViewController:confirm animated:YES completion:nil];
			}];
		}];
	};

	cfg.leadingSwipeActionsForItem = ^NSArray<UIContextualAction *> *(NSDictionary *e, void(^reload)(void)) {
		NSString *tid = e[@"threadId"];
		RYGKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
		RYGKeepDeletedOverride next = (mode + 1) % 3;

		NSString *title = next == RYGKeepDeletedOverrideExcluded ? RYGLocalized(@"KD: OFF") : next == RYGKeepDeletedOverrideIncluded ? RYGLocalized(@"KD: ON") : RYGLocalized(@"KD: default");

		UIContextualAction *a = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:title handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^done)(BOOL)) {
			[RYGExcludedThreads setKeepDeletedOverride:next forThreadId:tid];
			if (reload) reload();
			done(YES);
		}];

		a.backgroundColor = UIColor.systemBlueColor;
		return @[a];
	};

	cfg.contextMenuForItem = ^UIMenu *(NSDictionary *e, void(^reload)(void)) {
		NSString *tid = e[@"threadId"];
		RYGKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];

		UIAction *(^kdAction)(NSString *, RYGKeepDeletedOverride) = ^UIAction *(NSString *title, RYGKeepDeletedOverride v) {
			UIAction *act = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *_) {
				[RYGExcludedThreads setKeepDeletedOverride:v forThreadId:tid];
				if (reload) reload();
			}];
			act.state = v == mode ? UIMenuElementStateOn : UIMenuElementStateOff;
			return act;
		};

		UIMenu *kd = [UIMenu menuWithTitle:RYGLocalized(@"Keep-deleted override")
									 image:[UIImage systemImageNamed:@"trash.slash"]
								identifier:nil
								   options:0
								  children:@[
			kdAction(RYGLocalized(@"Follow default"), RYGKeepDeletedOverrideDefault),
			kdAction(RYGLocalized(@"Force ON (preserve unsends)"), RYGKeepDeletedOverrideIncluded),
			kdAction(RYGLocalized(@"Force OFF (allow unsends)"), RYGKeepDeletedOverrideExcluded)
		]];

		UIAction *remove = [UIAction actionWithTitle:RYGLocalized(@"Remove from list") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *_) {
			[RYGExcludedThreads removeThreadId:tid];
			if (reload) reload();
		}];
		remove.attributes = UIMenuElementAttributesDestructive;

		return [UIMenu menuWithChildren:@[kd, remove]];
	};

	cfg.extraBatchActions = ^NSArray<UIBarButtonItem *> *(NSArray *sel, void(^reload)(void), void(^exitEdit)(void)) {
		UIBarButtonItem *kd = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Keep-deleted") style:UIBarButtonItemStylePlain target:nil action:nil];

		kd.primaryAction = [UIAction actionWithTitle:RYGLocalized(@"Keep-deleted") image:nil identifier:nil handler:^(__unused UIAction *_) {
			UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Set keep-deleted override") message:nil preferredStyle:UIAlertControllerStyleActionSheet];

			void (^apply)(RYGKeepDeletedOverride) = ^(RYGKeepDeletedOverride mode) {
				for (NSDictionary *e in sel) [RYGExcludedThreads setKeepDeletedOverride:mode forThreadId:e[@"threadId"]];
				if (exitEdit) exitEdit();
				if (reload) reload();
			};

			[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Follow default") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { apply(RYGKeepDeletedOverrideDefault); }]];
			[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Force ON (preserve unsends)") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { apply(RYGKeepDeletedOverrideIncluded); }]];
			[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Force OFF (allow unsends)") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { apply(RYGKeepDeletedOverrideExcluded); }]];
			[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

			UIViewController *top = topMostController();
			[top presentViewController:sheet animated:YES completion:nil];
		}];

		return @[kd];
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
	self.config.title = [RYGExcludedThreads isBlockSelectedMode] ? RYGLocalized(@"Included chats") : RYGLocalized(@"Excluded chats");
	[super viewWillAppear:animated];
}

@end