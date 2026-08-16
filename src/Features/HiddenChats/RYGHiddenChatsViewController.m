#import "RYGHiddenChatsViewController.h"
#import "RYGHiddenChats.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Utils.h"
#import "../../RYGProfileOpener.h"
#import "../../Localization/RYGLocalization.h"
#import "../../UI/RYGAvatarLoader.h"

@implementation RYGHiddenChatsViewController

- (instancetype)init {
	RYGIDListConfig *cfg = [RYGIDListConfig new];
	cfg.title = RYGLocalized(@"Hidden chats");
	cfg.searchPlaceholder = RYGLocalized(@"Search by name or username");
	cfg.allowsAdd = YES;
	cfg.addAlertTitle = RYGLocalized(@"Add hidden chat");
	cfg.addAlertMessage = RYGLocalized(@"Username (looks up the DM thread) or raw thread ID");
	cfg.addAlertPlaceholder = RYGLocalized(@"Username or thread ID");
	cfg.useUserPickerForAdd = YES;
	cfg.addIDLabel = RYGLocalized(@"Add by thread ID");
	cfg.sortTitles = @[RYGLocalized(@"Recently hidden"), RYGLocalized(@"Name (A–Z)")];

	cfg.itemsProvider = ^NSArray *{ return [RYGHiddenChats allEntries]; };

	cfg.titleProvider = ^NSString *(NSDictionary *e) {
		NSString *name = e[@"threadName"];
		if ([name isKindOfClass:[NSString class]] && name.length) {
			BOOL isGroup = [e[@"isGroup"] boolValue];
			return [NSString stringWithFormat:@"%@%@", isGroup ? @"👥 " : @"", name];
		}
		return [NSString stringWithFormat:RYGLocalized(@"Thread %@"), e[@"threadId"] ?: @"?"];
	};
	cfg.subtitleProvider = ^NSString *(NSDictionary *e) {
		NSArray *users = e[@"users"];
		if (![users isKindOfClass:[NSArray class]] || !users.count) return e[@"threadId"] ?: @"";
		NSMutableArray *unames = [NSMutableArray new];
		for (NSDictionary *u in users) {
			if (u[@"username"]) [unames addObject:[@"@" stringByAppendingString:u[@"username"]]];
		}
		return [unames componentsJoinedByString:@", "];
	};

	cfg.iconProvider = ^UIImage *(NSDictionary *e) {
		return [RYGAvatarLoader avatarForEntry:e];
	};

	cfg.matchesQuery = ^BOOL(NSDictionary *e, NSString *q) {
		if ([[e[@"threadName"] lowercaseString] containsString:q]) return YES;
		if ([[e[@"threadId"] lowercaseString] containsString:q]) return YES;
		for (NSDictionary *u in (NSArray *)e[@"users"]) {
			if ([[u[@"username"] lowercaseString] containsString:q]) return YES;
			if ([[u[@"fullName"] lowercaseString] containsString:q]) return YES;
		}
		return NO;
	};
	cfg.sortedItems = ^NSArray *(NSArray *items, NSInteger mode) {
		return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			if (mode == 0) return [b[@"hiddenAt"] ?: @0 compare:a[@"hiddenAt"] ?: @0];
			return [a[@"threadName"] ?: @"" caseInsensitiveCompare:b[@"threadName"] ?: @""];
		}];
	};
	cfg.onTapItem = ^(NSDictionary *e, UIViewController *vc) {
		NSArray *users = e[@"users"];
		if ([e[@"isGroup"] boolValue] || users.count != 1) return;
		NSString *username = users.firstObject[@"username"];
		NSString *pk = users.firstObject[@"pk"];
		if (!username.length && !pk.length) return;
		[RYGProfileOpener openProfileForPK:pk username:username from:vc];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[RYGHiddenChats removeThreadId:e[@"threadId"]];
		[RYGHiddenChats refreshInboxInPlace];
	};

	cfg.statusProvider = ^NSString *{
		return [RYGHiddenChats revealed] ? RYGLocalized(@"👁 Shown in the inbox · Tap to hide") : nil;
	};
	__weak typeof(self) weak = self;
	cfg.onStatusTap = ^{ [RYGHiddenChats toggleRevealFrom:weak]; };

	cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
		if (!input.length) return;
		NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];

		NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
		BOOL numeric = trimmed.length > 0 && [trimmed rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
		if (numeric) {
			[RYGHiddenChats addEntry:@{ @"threadId": trimmed }];
			reload();
			return;
		}

		// Username -> resolve via IG API, then resolve the DM thread.
		NSString *username = trimmed;
		[RYGInstagramAPI sendRequestWithMethod:@"GET"
			path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", username]
			body:nil completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (!user || err) {
				[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"User '%@' not found"), username]];
				return;
			}
			NSString *pk = [user[@"id"] description] ?: @"";
			NSString *uname = user[@"username"] ?: username;
			NSString *fullName = user[@"full_name"] ?: @"";
			NSString *pic = user[@"profile_pic_url_hd"] ?: user[@"profile_pic_url"] ?: @"";
			if (!pk.length) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not resolve user ID")]; return; }

			[RYGInstagramAPI sendRequestWithMethod:@"GET"
				path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", pk]
				body:nil completion:^(NSDictionary *threadResp, NSError *tErr) {
				NSString *threadId = threadResp[@"thread"][@"thread_id"];
				NSString *threadName = threadResp[@"thread"][@"thread_title"] ?: uname;
				if (!threadId.length || tErr) {
					[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"No DM thread found with @%@"), uname]];
					return;
				}
				NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
				UIAlertController *confirm = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Hide this chat?")
																				 message:msg
																		  preferredStyle:UIAlertControllerStyleAlert];
				[confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
				[confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Hide") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
					[RYGHiddenChats addEntry:@{
						@"threadId": threadId,
						@"threadName": threadName,
						@"isGroup": @NO,
						@"avatarURL": pic,
						@"users": @[@{ @"pk": pk, @"username": uname, @"fullName": fullName, @"profilePicURL": pic }],
					}];
					reload();
				}]];
				[vc presentViewController:confirm animated:YES completion:nil];
			}];
		}];
	};

	return [super initWithConfig:cfg];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGAvatarLoadedNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:RYGHiddenChatsRevealDidChangeNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end