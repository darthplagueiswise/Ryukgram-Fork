// SCISettings_InternalGates.m
// Tela "Internal Gates": status ao vivo dos 7 gates EasyGating + sinal de
// internal-apps, toggles de força e o log ([SCIGate]) visível dentro da tweak.
#import "SCISettingsSections.h"
#import "../../Features/Dogfooding/SCIInternalGatesEngine.h"
#import "../../Features/Dogfooding/SCIInternalGatePrefs.h"
#import "../../SCIFileLog.h"

@implementation SCITweakSettings (Section_InternalGates)

static UIViewController *SCIGatesTopVC(void) {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		if (scene.activationState != UISceneActivationStateForegroundActive) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) { window = w; break; }
		}
		if (window) break;
	}
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController && !top.presentedViewController.isBeingDismissed)
		top = top.presentedViewController;
	return top;
}

+ (void)sci_gatesAlert:(NSString *)title message:(NSString *)message {
	UIViewController *top = SCIGatesTopVC();
	if (!top) return;
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title
		message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[top presentViewController:a animated:YES completion:nil];
}

+ (void)sci_showGateStatus {
	NSMutableString *s = [NSMutableString string];
	[s appendFormat:@"EasyGating evaluators hooked: %ld/3\nInternal-apps: %@\nForce EG: %@ · Force apps: %@\nEvaluator calls: %ld\nTotal forces: %ld\n\n",
		(long)[SCIInternalGatesEngine easyGatingEvaluatorsHooked],
		[SCIInternalGatesEngine internalAppsHooked] ? @"hooked" : @"off",
		[SCIInternalGatesEngine easyGatingForceActive] ? @"on" : @"off",
		[SCIInternalGatesEngine internalAppsForceActive] ? @"on" : @"off",
		(long)[SCIInternalGatesEngine evaluatorCallsSeen],
		(long)[SCIInternalGatesEngine totalForcedHits]];
	for (NSDictionary *g in [SCIInternalGatesEngine gateStatuses]) {
		[s appendFormat:@"%@ %@ · %ld×\n",
			[g[@"resolved"] boolValue] ? @"✓" : @"✗",
			g[@"name"], (long)[g[@"forced"] integerValue]];
	}
	[self sci_gatesAlert:SCILocalized(@"Gate status") message:s];
}

+ (void)sci_showGateLog {
	NSString *path = SCIFileLogPath();
	NSString *content = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
	if (!content.length) {
		[self sci_gatesAlert:SCILocalized(@"Gate log")
			message:SCILocalized(@"Log empty. Enable the file log, restart, then tap Internal Settings.")];
		return;
	}
	// only [SCIGate] lines, last ~60
	NSMutableArray *lines = [NSMutableArray array];
	for (NSString *line in [content componentsSeparatedByString:@"\n"])
		if ([line containsString:@"SCIGate"]) [lines addObject:line];
	if (!lines.count) {
		[self sci_gatesAlert:SCILocalized(@"Gate log")
			message:SCILocalized(@"No [SCIGate] lines yet. Tap Internal Settings with a force toggle on.")];
		return;
	}
	NSUInteger start = lines.count > 60 ? lines.count - 60 : 0;
	NSString *tail = [[lines subarrayWithRange:NSMakeRange(start, lines.count - start)] componentsJoinedByString:@"\n"];
	[self sci_gatesAlert:SCILocalized(@"Gate log") message:tail];
}

+ (void)sci_shareGateLog {
	NSURL *url = SCIFileLogURL();
	UIViewController *top = SCIGatesTopVC();
	if (!url || !top) return;
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	vc.popoverPresentationController.sourceView = top.view;
	vc.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width / 2.0, top.view.bounds.size.height / 2.0, 1, 1);
	[top presentViewController:vc animated:YES completion:nil];
}

+ (SCISetting *)internalGatesNavCell {
	// live status rows (captured at menu-build time; Refresh button shows live)
	NSMutableArray *statusRows = [NSMutableArray array];
	for (NSDictionary *g in [SCIInternalGatesEngine gateStatuses]) {
		NSString *sub = [NSString stringWithFormat:SCILocalized(@"resolved: %@ · forced: %ld×"),
			[g[@"resolved"] boolValue] ? @"✓" : @"✗", (long)[g[@"forced"] integerValue]];
		[statusRows addObject:[SCISetting staticCellWithTitle:g[@"name"] subtitle:sub icon:nil]];
	}
	[statusRows addObject:[SCISetting buttonCellWithTitle:SCILocalized(@"Refresh gate status")
		subtitle:@"" icon:[SCISymbol symbolWithName:@"arrow.clockwise"]
		action:^{ [self sci_showGateStatus]; }]];

	NSString *summary = [NSString stringWithFormat:SCILocalized(@"Hooked %ld/3 · %ld calls · internal-apps %@ · %ld forces"),
		(long)[SCIInternalGatesEngine easyGatingEvaluatorsHooked],
		(long)[SCIInternalGatesEngine evaluatorCallsSeen],
		[SCIInternalGatesEngine internalAppsHooked] ? SCILocalized(@"on") : SCILocalized(@"off"),
		(long)[SCIInternalGatesEngine totalForcedHits]];

	return [SCISetting navigationCellWithTitle:SCILocalized(@"Internal Gates")
		subtitle:@""
		icon:[SCISymbol symbolWithIGName:@"lock" fallback:@"lock.shield"]
		navSections:@[
			@{
				@"header": SCILocalized(@"EasyGating force"),
				@"footer": SCILocalized(@"Forces the employee/test-user/dogfooder EasyGating gates Instagram imports from FBSharedFramework (ig_is_employee, ig_is_employee_or_test_user, ig_dogfooding_assistant, ig_dogfooding_first_client, ig_user_session_canary_test, ig_device_session_canary_test, xav_switcher_ig_ios_test_user_check_fdid). Hooks the EasyGatingGetBoolean evaluators and returns YES only when the argument is one of these gate descriptors (resolved via dlsym); everything else falls through untouched. Restart required."),
				@"rows": @[
					[SCISetting switchCellWithTitle:SCILocalized(@"Force employee / test-user / dogfooder gates")
						subtitle:SCILocalized(@"EasyGatingGetBoolean evaluator fishhook, pointer-targeted to the 7 descriptors")
						defaultsKey:@"sci_force_easygating_internal"
						requiresRestart:YES],
					[SCISetting switchCellWithTitle:SCILocalized(@"Force internal-apps signal")
						subtitle:SCILocalized(@"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 -> YES")
						defaultsKey:@"sci_force_internal_apps_gate"
						requiresRestart:YES],
				],
			},
			@{
				@"header": SCILocalized(@"Gate status"),
				@"footer": summary,
				@"rows": statusRows,
			},
			@{
				@"header": SCILocalized(@"Gate log"),
				@"footer": SCILocalized(@"Records each gate the first time it is forced. View or share here — no Mac/Console needed."),
				@"rows": @[
					[SCISetting switchCellWithTitle:SCILocalized(@"Enable gate file log")
						subtitle:SCILocalized(@"Writes [SCIGate] lines to the tweak log file")
						value:^BOOL { return SCIFileLogIsEnabled(); }
						action:^(BOOL on) { SCIFileLogSetEnabled(on); }],
					[SCISetting buttonCellWithTitle:SCILocalized(@"Show gate log")
						subtitle:@"" icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
						action:^{ [self sci_showGateLog]; }],
					[SCISetting buttonCellWithTitle:SCILocalized(@"Share log file")
						subtitle:@"" icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
						action:^{ [self sci_shareGateLog]; }],
					[SCISetting buttonCellWithTitle:SCILocalized(@"Clear log")
						subtitle:@"" icon:[SCISymbol symbolWithName:@"trash"]
						action:^{ SCIFileLogClear(); [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Clear completed") subtitle:@""]; }],
				],
			},
		]];
}

@end
