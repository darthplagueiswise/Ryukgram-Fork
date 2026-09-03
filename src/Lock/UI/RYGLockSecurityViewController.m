#import "RYGLockSecurityViewController.h"
#import "RYGLockPasscodeRootViewController.h"
#import "../RYGLockManager.h"
#import "../RYGLockGroups.h"
#import "../../UI/RYGIcon.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"
#import "../../Features/HiddenChats/RYGHiddenChats.h"
#import "../../Features/HiddenChats/RYGHiddenChatsViewController.h"

@implementation RYGLockSecurityViewController

- (instancetype)init {
	if ((self = [super initWithTitle:RYGLocalized(@"Security & Privacy")])) {
		[self rebuildSections];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.navigationController.navigationBar.prefersLargeTitles = NO;

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reloadFromNotification:)
												 name:RYGLockSessionDidChangeNotification
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

	RYGSetting *lock = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Lock with passcode") subtitle:@"" icon:nil viewController:[RYGLockPasscodeRootViewController new]];
	lock.dynamicSubtitle = ^{ return [weak lockSummary]; };
	lock.iconImage = [RYGIcon imageNamed:@"ig_icon_lock_prism_filled_24" pointSize:24];
	lock.whatsNewID = @"ui_lockpasscode";

	RYGSetting *hidden = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Hidden chats") subtitle:@"" icon:nil action:^{
		[weak.navigationController pushViewController:[RYGHiddenChatsViewController new] animated:YES];
	}];
	hidden.dynamicSubtitle = ^{
		NSUInteger count = [RYGHiddenChats allEntries].count;
		if (!count) return RYGLocalized(@"Long-press a DM to add");
		NSString *base = [NSString stringWithFormat:RYGLocalized(@"%lu hidden"), (unsigned long)count];
		return [RYGHiddenChats revealed] ? [base stringByAppendingString:RYGLocalized(@" · shown in inbox")] : base;
	};
	hidden.iconImage = [RYGIcon imageNamed:@"ig_icon_direct_off_prism_outline_24" pointSize:24];

	RYGSetting *holdReveal = [self switchRowWithTitle:RYGLocalized(@"Hold name to reveal")
											 subtitle:RYGLocalized(@"Long-press the account name atop the DM inbox to show or hide your hidden chats")
												  key:@"hidden_chats_reveal_on_hold"
											 restart:NO];
	holdReveal.whatsNewID = @"hidden_chats_reveal_on_hold";

	RYGSetting *hideUI = [self switchRowWithTitle:RYGLocalized(@"Hide UI on capture")
										 subtitle:RYGLocalized(@"Redact RyukGram buttons from screenshots, screen recordings, and mirroring")
											  key:@"hide_ui_on_capture"
										 restart:NO];

	RYGSetting *removeAlert = [self switchRowWithTitle:RYGLocalized(@"Remove screenshot alert")
											  subtitle:RYGLocalized(@"Suppress IG's \"X took a screenshot\" notification across stories, DMs and disappearing media")
												   key:@"remove_screenshot_alert"
											  restart:NO];

	RYGSetting *instants = [self switchRowWithTitle:RYGLocalized(@"Allow Instants screenshots")
										   subtitle:RYGLocalized(@"Bypasses the Instants screenshot block")
												key:@"instants_allow_screenshot"
										   restart:YES];

	[self applySettingSections:@[
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Lock")
											 footer:RYGLocalized(@"Passcode + biometric. Gate the tweak settings popup, gallery, deleted-messages log, individual chats and the whole app.")
											   rows:@[lock]],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Hidden chats")
											 footer:RYGLocalized(@"Long-press a DM thread → Hide chat to add it here. Hidden chats are filtered out of the inbox until you remove them from this list.")
											   rows:@[hidden, holdReveal]],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Screenshots & capture")
											 footer:RYGLocalized(@"Hides RyukGram UI from screenshots/recordings and routes around IG's per-feature screenshot alerts.")
											   rows:@[hideUI, removeAlert, instants]]
	]];
}

- (RYGSetting *)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key restart:(BOOL)restart {
	return [RYGSetting switchCellWithTitle:title subtitle:subtitle value:^BOOL{
		return [RYGUtils getBoolPref:key];
	} action:^(BOOL on) {
		[[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
		[[NSUserDefaults standardUserDefaults] synchronize];
		if (restart) [RYGUtils showRestartConfirmation];
	}];
}

#pragma mark - Text

- (NSString *)lockSummary {
	RYGLockManager *mgr = [RYGLockManager shared];

	if (![mgr hasPasscode]) return RYGLocalized(@"No passcode set");
	if (![mgr isMasterEnabled]) return RYGLocalized(@"Off");

	NSMutableArray *enabled = [NSMutableArray array];

	for (RYGLockGroupInfo *group in RYGLockAllGroups()) {
		if ([RYGUtils getBoolPref:RYGLockPrefEnabled(group.identifier)]) {
			[enabled addObject:group.displayName];
		}
	}

	if (!enabled.count) return RYGLocalized(@"On — no targets enabled");
	if (enabled.count <= 3) return [NSString stringWithFormat:RYGLocalized(@"On — %@"), [enabled componentsJoinedByString:@", "]];

	NSArray *first = [enabled subarrayWithRange:NSMakeRange(0, 2)];
	return [NSString stringWithFormat:RYGLocalized(@"On — %@ + %ld more"), [first componentsJoinedByString:@", "], (long)(enabled.count - 2)];
}

@end