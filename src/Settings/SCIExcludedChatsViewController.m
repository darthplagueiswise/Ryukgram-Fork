#import "SCIExcludedChatsViewController.h"
#import "../Features/StoriesAndMessages/SCIExcludedThreads.h"
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

static NSString *SCITail(NSString *s, NSUInteger n) {
	if (!s.length || s.length <= n) return s ?: @"";
	return [@"…" stringByAppendingString:[s substringFromIndex:s.length - n]];
}

static NSString *SCIAtName(NSString *s) {
	if (!s.length) return nil;
	return [s hasPrefix:@"@"] ? s : [@"@" stringByAppendingString:s];
}

static NSString *SCIEncodedQuery(NSString *s) {
	NSCharacterSet *allowed = NSCharacterSet.URLQueryAllowedCharacterSet;
	return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: s;
}

static NSString *SCIUsersLine(NSArray *users) {
	NSMutableArray *names = [NSMutableArray new];

	for (NSDictionary *u in users) {
		if (![u isKindOfClass:NSDictionary.class]) continue;

		NSString *name = SCIAtName(SCIText(u[@"username"]));
		if (name.length) [names addObject:name];
	}

	return [names componentsJoinedByString:@", "];
}

static NSString *SCIKeepDeletedText(NSDictionary *e) {
	SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
	if (mode == SCIKeepDeletedOverrideExcluded) return SCILocalized(@"Keep-deleted: OFF");
	if (mode == SCIKeepDeletedOverrideIncluded) return SCILocalized(@"Keep-deleted: ON");
	return @"";
}

static NSDictionary *SCINormalizedEntry(NSDictionary *e) {
	NSString *tid = SCIText(e[@"threadId"]);
	NSString *name = SCIText(e[@"threadName"]);
	BOOL group = [e[@"isGroup"] boolValue];
	NSArray *users = [e[@"users"] isKindOfClass:NSArray.class] ? e[@"users"] : @[];
	NSString *usersLine = SCIUsersLine(users);
	NSString *kd = SCIKeepDeletedText(e);

	if (!name.length) name = tid.length ? [NSString stringWithFormat:@"%@ %@", SCILocalized(@"Thread"), SCITail(tid, 8)] : SCILocalized(@"Unknown");

	NSMutableArray *sub = [NSMutableArray new];
	if (usersLine.length) [sub addObject:usersLine];
	if (kd.length) [sub addObject:kd];
	if (!sub.count && tid.length) [sub addObject:tid];

	NSString *searchBlob = [NSString stringWithFormat:@"%@ %@ %@ %@",
		SCILower(tid),
		SCILower(name),
		SCILower(usersLine),
		SCILower(users)
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

@implementation SCIExcludedChatsViewController

- (instancetype)init {
	SCIIDListConfig *cfg = [SCIIDListConfig new];

	cfg.title = [SCIExcludedThreads isBlockSelectedMode] ? SCILocalized(@"Included chats") : SCILocalized(@"Excluded chats");
	cfg.searchPlaceholder = SCILocalized(@"Search by name or username");
	cfg.addAlertTitle = SCILocalized(@"Add chat");
	cfg.addAlertMessage = SCILocalized(@"Username (looks up the DM thread) or raw thread ID");
	cfg.addAlertPlaceholder = SCILocalized(@"Username or thread ID");
	cfg.sortTitles = @[SCILocalized(@"Recently added"), SCILocalized(@"Name (A–Z)")];

	cfg.itemsProvider = ^NSArray *{
		NSArray *raw = [SCIExcludedThreads allEntries] ?: @[];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];

		for (NSDictionary *e in raw) {
			if ([e isKindOfClass:NSDictionary.class]) [items addObject:SCINormalizedEntry(e)];
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
		if ([e[@"isGroup"] boolValue]) return;

		NSArray *users = [e[@"users"] isKindOfClass:NSArray.class] ? e[@"users"] : @[];
		NSDictionary *u = users.count == 1 && [users.firstObject isKindOfClass:NSDictionary.class] ? users.firstObject : nil;
		NSString *username = SCIText(u[@"username"]);
		if (!username.length) return;

		[vc.navigationController dismissViewControllerAnimated:YES completion:^{
			[SCIURLOpener openInstagramProfileForUsername:username];
		}];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[SCIExcludedThreads removeThreadId:e[@"threadId"]];
	};

	cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
		NSString *q = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"@" withString:@""];
		if (!q.length) return;

		BOOL numeric = [q rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
		if (numeric) {
			[SCIExcludedThreads addOrUpdateEntry:@{
				@"threadId": q,
				@"threadName": [NSString stringWithFormat:@"%@ %@", SCILocalized(@"Thread"), SCITail(q, 8)]
			}];
			if (reload) reload();
			return;
		}

		NSString *profilePath = [NSString stringWithFormat:@"users/web_profile_info/?username=%@", SCIEncodedQuery(q)];
		[SCIInstagramAPI sendRequestWithMethod:@"GET" path:profilePath body:nil completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (err || ![user isKindOfClass:NSDictionary.class]) {
				[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), q]];
				return;
			}

			NSString *pk = SCIText(user[@"id"]);
			NSString *uname = SCIText(user[@"username"]).length ? SCIText(user[@"username"]) : q;
			NSString *fullName = SCIText(user[@"full_name"]);
			NSString *pic = SCIText(user[@"profile_pic_url_hd"]);
			if (!pic.length) pic = SCIText(user[@"profile_pic_url"]);

			if (!pk.length) {
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")];
				return;
			}

			NSString *threadPath = [NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", SCIEncodedQuery(pk)];
			[SCIInstagramAPI sendRequestWithMethod:@"GET" path:threadPath body:nil completion:^(NSDictionary *threadResp, NSError *tErr) {
				NSDictionary *thread = [threadResp[@"thread"] isKindOfClass:NSDictionary.class] ? threadResp[@"thread"] : nil;
				if (!thread && [threadResp[@"threads"] isKindOfClass:NSArray.class]) thread = [threadResp[@"threads"] firstObject];

				NSString *threadId = SCIText(thread[@"thread_id"]);
				NSString *threadName = SCIText(thread[@"thread_title"]).length ? SCIText(thread[@"thread_title"]) : uname;

				if (tErr || !threadId.length) {
					[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"No DM thread found with @%@"), uname]];
					return;
				}

				NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];

				UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add to list?")
																				 message:msg
																		  preferredStyle:UIAlertControllerStyleAlert];

				[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
				[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
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

					[SCIExcludedThreads addOrUpdateEntry:entry];
					if (reload) reload();
				}]];

				[vc presentViewController:confirm animated:YES completion:nil];
			}];
		}];
	};

	cfg.leadingSwipeActionsForItem = ^NSArray<UIContextualAction *> *(NSDictionary *e, void(^reload)(void)) {
		NSString *tid = e[@"threadId"];
		SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
		SCIKeepDeletedOverride next = (mode + 1) % 3;

		NSString *title = next == SCIKeepDeletedOverrideExcluded ? SCILocalized(@"KD: OFF") : next == SCIKeepDeletedOverrideIncluded ? SCILocalized(@"KD: ON") : SCILocalized(@"KD: default");

		UIContextualAction *a = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:title handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^done)(BOOL)) {
			[SCIExcludedThreads setKeepDeletedOverride:next forThreadId:tid];
			if (reload) reload();
			done(YES);
		}];

		a.backgroundColor = UIColor.systemBlueColor;
		return @[a];
	};

	cfg.contextMenuForItem = ^UIMenu *(NSDictionary *e, void(^reload)(void)) {
		NSString *tid = e[@"threadId"];
		SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];

		UIAction *(^kdAction)(NSString *, SCIKeepDeletedOverride) = ^UIAction *(NSString *title, SCIKeepDeletedOverride v) {
			UIAction *act = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *_) {
				[SCIExcludedThreads setKeepDeletedOverride:v forThreadId:tid];
				if (reload) reload();
			}];
			act.state = v == mode ? UIMenuElementStateOn : UIMenuElementStateOff;
			return act;
		};

		UIMenu *kd = [UIMenu menuWithTitle:SCILocalized(@"Keep-deleted override")
									 image:[UIImage systemImageNamed:@"trash.slash"]
								identifier:nil
								   options:0
								  children:@[
			kdAction(SCILocalized(@"Follow default"), SCIKeepDeletedOverrideDefault),
			kdAction(SCILocalized(@"Force ON (preserve unsends)"), SCIKeepDeletedOverrideIncluded),
			kdAction(SCILocalized(@"Force OFF (allow unsends)"), SCIKeepDeletedOverrideExcluded)
		]];

		UIAction *remove = [UIAction actionWithTitle:SCILocalized(@"Remove from list") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *_) {
			[SCIExcludedThreads removeThreadId:tid];
			if (reload) reload();
		}];
		remove.attributes = UIMenuElementAttributesDestructive;

		return [UIMenu menuWithChildren:@[kd, remove]];
	};

	cfg.extraBatchActions = ^NSArray<UIBarButtonItem *> *(NSArray *sel, void(^reload)(void), void(^exitEdit)(void)) {
		UIBarButtonItem *kd = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Keep-deleted") style:UIBarButtonItemStylePlain target:nil action:nil];

		kd.primaryAction = [UIAction actionWithTitle:SCILocalized(@"Keep-deleted") image:nil identifier:nil handler:^(__unused UIAction *_) {
			UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Set keep-deleted override") message:nil preferredStyle:UIAlertControllerStyleActionSheet];

			void (^apply)(SCIKeepDeletedOverride) = ^(SCIKeepDeletedOverride mode) {
				for (NSDictionary *e in sel) [SCIExcludedThreads setKeepDeletedOverride:mode forThreadId:e[@"threadId"]];
				if (exitEdit) exitEdit();
				if (reload) reload();
			};

			[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Follow default") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { apply(SCIKeepDeletedOverrideDefault); }]];
			[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Force ON (preserve unsends)") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { apply(SCIKeepDeletedOverrideIncluded); }]];
			[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Force OFF (allow unsends)") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { apply(SCIKeepDeletedOverrideExcluded); }]];
			[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

			UIViewController *top = topMostController();
			[top presentViewController:sheet animated:YES completion:nil];
		}];

		return @[kd];
	};

	return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SCIAvatarLoadedNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	self.config.title = [SCIExcludedThreads isBlockSelectedMode] ? SCILocalized(@"Included chats") : SCILocalized(@"Excluded chats");
	[super viewWillAppear:animated];
}

@end