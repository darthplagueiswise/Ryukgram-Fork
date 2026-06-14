// Hide Instagram TestFlight beta update popup.

#import "../../Utils.h"
#import <Foundation/Foundation.h>

#pragma mark - Primary: receipt URL spoof

// Apple's standard TF detection reads NSBundle.mainBundle.appStoreReceiptURL
// and checks lastPathComponent == "sandboxReceipt". Rewrite to "receipt" and
// IG never enters the TestFlight code path; no VC is ever instantiated.

%group SCIHideTestFlightNagReceipt
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
	NSURL *url = %orig;
	if (self == NSBundle.mainBundle && [url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
		return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
	}
	return url;
}
%end
%end

#pragma mark - Fallback (disabled): VC dismiss

// %group SCIHideTestFlightNagVC
// %hook _TtC29IGCoreRootTestFlightNagPlugin35TestFlightUpdateNudgeViewController
//
// - (void)viewDidLoad {
// 	%orig;
// 	UIViewController *vc = (UIViewController *)(id)self;
// 	if (![vc isKindOfClass:UIViewController.class]) return;
// 	vc.view.hidden = YES;
// 	vc.view.userInteractionEnabled = NO;
// }
//
// - (void)viewDidAppear:(BOOL)animated {
// 	%orig;
// 	UIViewController *vc = (UIViewController *)(id)self;
// 	if (![vc isKindOfClass:UIViewController.class]) return;
// 	[vc dismissViewControllerAnimated:NO completion:nil];
// }
//
// %end
// %end

%ctor {
	if ([SCIUtils getBoolPref:@"hide_testflight_nag"]) {
		%init(SCIHideTestFlightNagReceipt);
	}
}
