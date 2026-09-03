#import "RYGSettingsSections.h"
#import "../../Features/FollowRequests/RYGFollowRequestTracker.h"
#import "../../Features/FollowRequests/RYGFollowRequestStorage.h"
#import "../../UI/RYGFeatureIcons.h"

@implementation RYGTweakSettings (Section_FollowRequests)

+ (RYGSetting *)followRequestsNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"Follow Requests")
									  subtitle:@""
										  icon:[RYGFeatureIcons followRequests]
								   navSections:@[
		@{
			@"header": @"",
			@"footer": RYGLocalized(@"Logs follow requests you send and receive, and catches who cancels a request before you answer. All on-device."),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable tracker") subtitle:RYGLocalized(@"Log requests and check outcomes") defaultsKey:@"follow_requests_enabled"],
			]
		},
		@{
			@"header": RYGLocalized(@"What to track"),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Requests I send") subtitle:RYGLocalized(@"To private accounts") defaultsKey:@"follow_requests_track_outgoing"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Requests I receive") subtitle:RYGLocalized(@"From people who want to follow you") defaultsKey:@"follow_requests_track_incoming"],
			]
		},
		@{
			@"header": RYGLocalized(@"Background check"),
			@"footer": RYGLocalized(@"How often to check for outcomes while the app is open. Also checks on launch and when you open the list."),
			@"rows": @[
				[RYGSetting menuCellWithTitle:RYGLocalized(@"Check interval") subtitle:@"" menu:[self menus][@"follow_requests_check_interval"]],
			]
		},
		@{
			@"header": RYGLocalized(@"Notifications"),
			@"rows": @[
				[RYGSetting switchCellWithTitle:RYGLocalized(@"My request accepted") subtitle:RYGLocalized(@"A private account accepted you") defaultsKey:@"follow_requests_notify_accepted"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"My request declined") subtitle:RYGLocalized(@"No longer pending") defaultsKey:@"follow_requests_notify_rejected"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"New request received") subtitle:RYGLocalized(@"Someone asked to follow you") defaultsKey:@"follow_requests_notify_received"],
				[RYGSetting switchCellWithTitle:RYGLocalized(@"Request withdrawn") subtitle:RYGLocalized(@"Someone cancelled their request") defaultsKey:@"follow_requests_notify_withdrawn"],
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				({
					RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Show follow requests")
														   subtitle:@""
															   icon:[RYGSymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"list.bullet.rectangle"]
															 action:^{
						UIViewController *top = rygTopVC();
						RYGFollowRequestsViewController *vc = [RYGFollowRequestsViewController new];
						UINavigationController *nav = top.navigationController;
						if (!nav && [top isKindOfClass:UINavigationController.class]) nav = (UINavigationController *)top;
						if (nav) [nav pushViewController:vc animated:YES];
					}];
					s.badgeCount = ^NSInteger{ return [RYGFollowRequestStorage unreadCountForOwnerPK:[RYGUtils currentUserPK]]; };
					s;
				}),
				[RYGSetting buttonCellWithTitle:RYGLocalized(@"Check now")
									   subtitle:@""
										   icon:[RYGSymbol symbolWithName:@"arrow.clockwise"]
										 action:^{
					if (![RYGUtils getBoolPref:@"follow_requests_enabled"]) { [RYGUtils showToastForDuration:2 title:RYGLocalized(@"Enable the tracker first")]; return; }
					[RYGUtils showToastForDuration:1.2 title:RYGLocalized(@"Checking…")];
					[[RYGFollowRequestTracker shared] checkNowForced:YES completion:^(NSInteger changed) {
						if (changed > 0) [RYGUtils showToastForDuration:2 title:[NSString stringWithFormat:RYGLocalized(@"%ld request(s) updated"), (long)changed]];
						else [RYGUtils showToastForDuration:2 title:RYGLocalized(@"No changes")];
					}];
				}],
				[RYGSetting buttonCellWithTitle:RYGLocalized(@"Reset tracked data")
									   subtitle:@""
										   icon:[RYGSymbol symbolWithName:@"trash"]
										 action:^{
					[RYGUtils showConfirmation:^{
						[RYGFollowRequestStorage resetForOwnerPK:[RYGUtils currentUserPK]];
					} title:RYGLocalized(@"Reset tracked follow requests for this account?")];
				}],
			]
		},
	]];
}

@end
