#import "SCILockSecurityViewController.h"
#import "SCILockPasscodeRootViewController.h"
#import "../SCILockManager.h"
#import "../SCILockGroups.h"
#import "../../UI/SCIIcon.h"
#import "../../Utils.h"
#import "../../Localization/SCILocalization.h"
#import "../../Features/HiddenChats/SCIHiddenChats.h"
#import "../../Features/HiddenChats/SCIHiddenChatsViewController.h"

@implementation SCILockSecurityViewController

- (instancetype)init {
	if ((self = [super initWithTitle:SCILocalized(@"Security & Privacy")])) {
		[self rebuildSections];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.navigationController.navigationBar.prefersLargeTitles = NO;

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reloadFromNotification:)
												 name:SCILockSessionDidChangeNotification
											   object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuildSections];
}

- (void)reloadFromNotification:(__unused NSNotification *)note {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self rebuildSections];
	});
}

#pragma mark - Sections

- (void)rebuildSections {
	__weak typeof(self) weak = self;

	SCISetting *lock = [SCISetting navigationCellWithTitle:SCILocalized(@"Lock with passcode") subtitle:@"" icon:nil viewController:[SCILockPasscodeRootViewController new]];
	lock.dynamicSubtitle = ^{ return [weak lockSummary]; };
	lock.iconImage = [SCIIcon imageNamed:@"ig_icon_lock_prism_filled_24" pointSize:24];

	SCISetting *hidden = [SCISetting buttonCellWithTitle:SCILocalized(@"Hidden chats") subtitle:@"" icon:nil action:^{
		[weak.navigationController pushViewController:[SCIHiddenChatsViewController new] animated:YES];
	}];
	hidden.dynamicSubtitle = ^{
		NSUInteger count = [SCIHiddenChats allEntries].count;
		if (!count) return SCILocalized(@"Long-press a DM to add");
		NSString *base = [NSString stringWithFormat:SCILocalized(@"%lu hidden"), (unsigned long)count];
		return [SCIHiddenChats revealed] ? [base stringByAppendingString:SCILocalized(@" · shown in inbox")] : base;
	};
	hidden.iconImage = [SCIIcon imageNamed:@"ig_icon_direct_off_prism_outline_24" pointSize:24];

	SCISetting *holdReveal = [self switchRowWithTitle:SCILocalized(@"Hold name to reveal")
											 subtitle:SCILocalized(@"Long-press the account name atop the DM inbox to show or hide your hidden chats")
												  key:@"hidden_chats_reveal_on_hold"
											 restart:NO];

	SCISetting *hideUI = [self switchRowWithTitle:SCILocalized(@"Hide UI on capture")
										 subtitle:SCILocalized(@"Redact RyukGram buttons from screenshots, screen recordings, and mirroring")
											  key:@"hide_ui_on_capture"
										 restart:NO];

	SCISetting *removeAlert = [self switchRowWithTitle:SCILocalized(@"Remove screenshot alert")
											  subtitle:SCILocalized(@"Suppress IG's \"X took a screenshot\" notification across stories, DMs and disappearing media")
												   key:@"remove_screenshot_alert"
											  restart:NO];

	SCISetting *instants = [self switchRowWithTitle:SCILocalized(@"Allow Instants screenshots")
										   subtitle:SCILocalized(@"Bypasses the Instants screenshot block")
												key:@"instants_allow_screenshot"
										   restart:YES];

	[self applySettingSections:@[
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Lock")
											 footer:SCILocalized(@"Passcode + biometric. Gate the tweak settings popup, gallery, deleted-messages log, individual chats and the whole app.")
											   rows:@[lock]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Hidden chats")
											 footer:SCILocalized(@"Long-press a DM thread → Hide chat to add it here. Hidden chats are filtered out of the inbox until you remove them from this list.")
											   rows:@[hidden, holdReveal]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Screenshots & capture")
											 footer:SCILocalized(@"Hides RyukGram UI from screenshots/recordings and routes around IG's per-feature screenshot alerts.")
											   rows:@[hideUI, removeAlert, instants]]
	]];
}

- (SCISetting *)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key restart:(BOOL)restart {
	return [SCISetting switchCellWithTitle:title subtitle:subtitle value:^BOOL{
		return [SCIUtils getBoolPref:key];
	} action:^(BOOL on) {
		[[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
		[[NSUserDefaults standardUserDefaults] synchronize];
		if (restart) [SCIUtils showRestartConfirmation];
	}];
}

#pragma mark - Text

- (NSString *)lockSummary {
	SCILockManager *mgr = [SCILockManager shared];

	if (![mgr hasPasscode]) return SCILocalized(@"No passcode set");
	if (![mgr isMasterEnabled]) return SCILocalized(@"Off");

	NSMutableArray *enabled = [NSMutableArray array];

	for (SCILockGroupInfo *group in SCILockAllGroups()) {
		if ([SCIUtils getBoolPref:SCILockPrefEnabled(group.identifier)]) {
			[enabled addObject:group.displayName];
		}
	}

	if (!enabled.count) return SCILocalized(@"On — no targets enabled");
	if (enabled.count <= 3) return [NSString stringWithFormat:SCILocalized(@"On — %@"), [enabled componentsJoinedByString:@", "]];

	NSArray *first = [enabled subarrayWithRange:NSMakeRange(0, 2)];
	return [NSString stringWithFormat:SCILocalized(@"On — %@ + %ld more"), [first componentsJoinedByString:@", "], (long)(enabled.count - 2)];
}

@end