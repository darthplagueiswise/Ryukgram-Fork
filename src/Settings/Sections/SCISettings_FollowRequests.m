#import "SCISettingsSections.h"
#import "../../Features/FollowRequests/SCIFollowRequestTracker.h"
#import "../../Features/FollowRequests/SCIFollowRequestStorage.h"

@implementation SCITweakSettings (Section_FollowRequests)

+ (SCISetting *)followRequestsNavCell {
	return [SCISetting navigationCellWithTitle:SCILocalized(@"Follow Requests Tracker")
									  subtitle:@""
										  icon:[SCISymbol symbolWithIGName:@"bcn_users-add_outline_24" fallback:@"person.crop.circle.badge.plus"]
								   navSections:@[
		@{
			@"header": @"",
			@"footer": SCILocalized(@"Logs follow requests you send and receive, and catches who cancels a request before you answer. All on-device."),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"Enable tracker") subtitle:SCILocalized(@"Log requests and check outcomes") defaultsKey:@"follow_requests_enabled"],
			]
		},
		@{
			@"header": SCILocalized(@"What to track"),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"Requests I send") subtitle:SCILocalized(@"To private accounts") defaultsKey:@"follow_requests_track_outgoing"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Requests I receive") subtitle:SCILocalized(@"From people who want to follow you") defaultsKey:@"follow_requests_track_incoming"],
			]
		},
		@{
			@"header": SCILocalized(@"Background check"),
			@"footer": SCILocalized(@"How often to check for outcomes while the app is open. Also checks on launch and when you open the list."),
			@"rows": @[
				[SCISetting menuCellWithTitle:SCILocalized(@"Check interval") subtitle:@"" menu:[self menus][@"follow_requests_check_interval"]],
			]
		},
		@{
			@"header": SCILocalized(@"Notifications"),
			@"rows": @[
				[SCISetting switchCellWithTitle:SCILocalized(@"My request accepted") subtitle:SCILocalized(@"A private account accepted you") defaultsKey:@"follow_requests_notify_accepted"],
				[SCISetting switchCellWithTitle:SCILocalized(@"My request declined") subtitle:SCILocalized(@"No longer pending") defaultsKey:@"follow_requests_notify_rejected"],
				[SCISetting switchCellWithTitle:SCILocalized(@"New request received") subtitle:SCILocalized(@"Someone asked to follow you") defaultsKey:@"follow_requests_notify_received"],
				[SCISetting switchCellWithTitle:SCILocalized(@"Request withdrawn") subtitle:SCILocalized(@"Someone cancelled their request") defaultsKey:@"follow_requests_notify_withdrawn"],
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				({
					SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Show follow requests")
														   subtitle:@""
															   icon:[SCISymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"list.bullet.rectangle"]
															 action:^{
						UIViewController *top = sciTopVC();
						SCIFollowRequestsViewController *vc = [SCIFollowRequestsViewController new];
						UINavigationController *nav = top.navigationController;
						if (!nav && [top isKindOfClass:UINavigationController.class]) nav = (UINavigationController *)top;
						if (nav) [nav pushViewController:vc animated:YES];
					}];
					s.badgeCount = ^NSInteger{ return [SCIFollowRequestStorage unreadCountForOwnerPK:[SCIUtils currentUserPK]]; };
					s;
				}),
				[SCISetting buttonCellWithTitle:SCILocalized(@"Check now")
									   subtitle:@""
										   icon:[SCISymbol symbolWithName:@"arrow.clockwise"]
										 action:^{
					if (![SCIUtils getBoolPref:@"follow_requests_enabled"]) { [SCIUtils showToastForDuration:2 title:SCILocalized(@"Enable the tracker first")]; return; }
					[SCIUtils showToastForDuration:1.2 title:SCILocalized(@"Checking…")];
					[[SCIFollowRequestTracker shared] checkNowForced:YES completion:^(NSInteger changed) {
						if (changed > 0) [SCIUtils showToastForDuration:2 title:[NSString stringWithFormat:SCILocalized(@"%ld request(s) updated"), (long)changed]];
						else [SCIUtils showToastForDuration:2 title:SCILocalized(@"No changes")];
					}];
				}],
				[SCISetting buttonCellWithTitle:SCILocalized(@"Reset tracked data")
									   subtitle:@""
										   icon:[SCISymbol symbolWithName:@"trash"]
										 action:^{
					[SCIUtils showConfirmation:^{
						[SCIFollowRequestStorage resetForOwnerPK:[SCIUtils currentUserPK]];
					} title:SCILocalized(@"Reset tracked follow requests for this account?")];
				}],
			]
		},
	]];
}

@end
