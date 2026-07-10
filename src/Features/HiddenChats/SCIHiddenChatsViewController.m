#import "SCIHiddenChatsViewController.h"
#import "SCIHiddenChats.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../Localization/SCILocalization.h"
#import "../../UI/SCIAvatarLoader.h"

@implementation SCIHiddenChatsViewController

- (instancetype)init {
	SCIIDListConfig *cfg = [SCIIDListConfig new];
	cfg.title = SCILocalized(@"Hidden chats");
	cfg.searchPlaceholder = SCILocalized(@"Search by name or username");
	cfg.allowsAdd = YES;
	cfg.addAlertTitle = SCILocalized(@"Add hidden chat");
	cfg.addAlertMessage = SCILocalized(@"Username (looks up the DM thread) or raw thread ID");
	cfg.addAlertPlaceholder = SCILocalized(@"Username or thread ID");
	cfg.sortTitles = @[SCILocalized(@"Recently hidden"), SCILocalized(@"Name (A–Z)")];

	cfg.itemsProvider = ^NSArray *{ return [SCIHiddenChats allEntries]; };

	cfg.titleProvider = ^NSString *(NSDictionary *e) {
		NSString *name = e[@"threadName"];
		if ([name isKindOfClass:[NSString class]] && name.length) {
			BOOL isGroup = [e[@"isGroup"] boolValue];
			return [NSString stringWithFormat:@"%@%@", isGroup ? @"👥 " : @"", name];
		}
		return [NSString stringWithFormat:SCILocalized(@"Thread %@"), e[@"threadId"] ?: @"?"];
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
		return [SCIAvatarLoader avatarForEntry:e];
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
		if (!username.length) return;
		[vc.navigationController dismissViewControllerAnimated:YES completion:^{
			[SCIURLOpener openInstagramProfileForUsername:username];
		}];
	};

	cfg.onRemoveItem = ^(NSDictionary *e) {
		[SCIHiddenChats removeThreadId:e[@"threadId"]];
		[SCIHiddenChats refreshInboxInPlace];
	};

	cfg.statusProvider = ^NSString *{
		return [SCIHiddenChats revealed] ? SCILocalized(@"👁 Shown in the inbox · Tap to hide") : nil;
	};
	__weak typeof(self) weak = self;
	cfg.onStatusTap = ^{ [SCIHiddenChats toggleRevealFrom:weak]; };

	cfg.onAddRequest = ^(NSString *input, UIViewController *vc, void(^reload)(void)) {
		if (!input.length) return;
		NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];

		NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
		BOOL numeric = trimmed.length > 0 && [trimmed rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
		if (numeric) {
			[SCIHiddenChats addEntry:@{ @"threadId": trimmed }];
			reload();
			return;
		}

		// Username -> resolve via IG API, then resolve the DM thread.
		NSString *username = trimmed;
		[SCIInstagramAPI sendRequestWithMethod:@"GET"
			path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", username]
			body:nil completion:^(NSDictionary *resp, NSError *err) {
			NSDictionary *user = resp[@"data"][@"user"];
			if (!user || err) {
				[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), username]];
				return;
			}
			NSString *pk = [user[@"id"] description] ?: @"";
			NSString *uname = user[@"username"] ?: username;
			NSString *fullName = user[@"full_name"] ?: @"";
			NSString *pic = user[@"profile_pic_url_hd"] ?: user[@"profile_pic_url"] ?: @"";
			if (!pk.length) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")]; return; }

			[SCIInstagramAPI sendRequestWithMethod:@"GET"
				path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", pk]
				body:nil completion:^(NSDictionary *threadResp, NSError *tErr) {
				NSString *threadId = threadResp[@"thread"][@"thread_id"];
				NSString *threadName = threadResp[@"thread"][@"thread_title"] ?: uname;
				if (!threadId.length || tErr) {
					[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"No DM thread found with @%@"), uname]];
					return;
				}
				NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
				UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Hide this chat?")
																				 message:msg
																		  preferredStyle:UIAlertControllerStyleAlert];
				[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
				[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Hide") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
					[SCIHiddenChats addEntry:@{
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
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SCIAvatarLoadedNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SCIHiddenChatsRevealDidChangeNotification object:nil];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

@end