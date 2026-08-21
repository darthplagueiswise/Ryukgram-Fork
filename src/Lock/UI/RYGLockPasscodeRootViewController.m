#import "RYGLockPasscodeRootViewController.h"

#import "RYGLockPasscodeViewController.h"
#import "RYGLockSetupViewController.h"
#import "RYGLockGroupDetailViewController.h"

#import "../RYGLockManager.h"
#import "../RYGLockGroups.h"

#import "../../UI/RYGPopupChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"
#import "../../UI/Notification/RYGNotificationCenter.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Settings/RYGSettingsViewController.h"

@interface RYGLockPasscodeRootViewController () <UITableViewDataSource, UITableViewDelegate, RYGSettingsSearchable>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic) BOOL configured;

@end

@implementation RYGLockPasscodeRootViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = RYGLocalized(@"Lock with passcode");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.navigationController.navigationBar.prefersLargeTitles = NO;

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
	self.tableView.estimatedRowHeight = 60.0;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;

	[self.view addSubview:self.tableView];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(sessionChanged:)
												 name:RYGLockSessionDidChangeNotification
											   object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutHero];
}

#pragma mark - Reload

- (void)sessionChanged:(__unused NSNotification *)note {
	[self reloadOnMain];
}

- (void)reloadOnMain {
	if (NSThread.isMainThread) {
		[self reload];
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		[self reload];
	});
}

- (void)reload {
	self.configured = [[RYGLockManager shared] hasPasscode];

	if (self.configured) {
		self.tableView.tableHeaderView = nil;
	} else {
		self.tableView.tableHeaderView = [self buildHero];
		[self layoutHero];
	}

	[self.tableView reloadData];
}

#pragma mark - Hero

- (UIView *)buildHero {
	UIView *wrap = UIView.new;
	wrap.backgroundColor = UIColor.clearColor;

	UIView *card = UIView.new;
	card.translatesAutoresizingMaskIntoConstraints = NO;
	card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	card.layer.cornerRadius = 22.0;
	card.layer.cornerCurve = kCACornerCurveContinuous;

	UIImageView *icon = UIImageView.new;
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.image = [RYGIcon imageNamed:@"lock.shield.fill" pointSize:42.0 weight:UIImageSymbolWeightSemibold];
	icon.tintColor = [self primaryColor];
	icon.contentMode = UIViewContentModeScaleAspectFit;

	UILabel *title = UILabel.new;
	title.translatesAutoresizingMaskIntoConstraints = NO;
	title.text = RYGLocalized(@"Lock the tweak");
	title.textColor = UIColor.labelColor;
	title.textAlignment = NSTextAlignmentCenter;
	title.numberOfLines = 0;
	title.font = [UIFont systemFontOfSize:23.0 weight:UIFontWeightBold];

	UILabel *subtitle = UILabel.new;
	subtitle.translatesAutoresizingMaskIntoConstraints = NO;
	subtitle.text = RYGLocalized(@"Set a passcode to protect Settings, Gallery, deleted messages, chats, the DM inbox, Profile Analyzer, or Instagram itself.");
	subtitle.textColor = UIColor.secondaryLabelColor;
	subtitle.textAlignment = NSTextAlignmentCenter;
	subtitle.numberOfLines = 0;
	subtitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];

	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.backgroundColor = [self primaryColor];
	button.layer.cornerRadius = 14.0;
	button.layer.cornerCurve = kCACornerCurveContinuous;
	button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

	[button setTitle:RYGLocalized(@"Set passcode") forState:UIControlStateNormal];
	[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[button addTarget:self action:@selector(tapSetPasscode) forControlEvents:UIControlEventTouchUpInside];

	[wrap addSubview:card];
	[card addSubview:icon];
	[card addSubview:title];
	[card addSubview:subtitle];
	[card addSubview:button];

	[NSLayoutConstraint activateConstraints:@[
		[card.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:20.0],
		[card.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-20.0],
		[card.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:18.0],
		[card.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-10.0],

		[icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:28.0],
		[icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
		[icon.widthAnchor constraintEqualToConstant:54.0],
		[icon.heightAnchor constraintEqualToConstant:54.0],

		[title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:14.0],
		[title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22.0],
		[title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],

		[subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
		[subtitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22.0],
		[subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],

		[button.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:20.0],
		[button.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22.0],
		[button.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],
		[button.heightAnchor constraintEqualToConstant:50.0],
		[button.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22.0],
	]];

	return wrap;
}

- (void)layoutHero {
	UIView *hero = self.tableView.tableHeaderView;
	if (!hero) return;

	CGFloat width = self.tableView.bounds.size.width;
	if (width <= 0.0) return;

	CGSize size = [hero systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
					  withHorizontalFittingPriority:UILayoutPriorityRequired
							verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

	if (fabs(hero.frame.size.height - size.height) < 0.5) return;

	hero.frame = CGRectMake(0.0, 0.0, width, size.height);
	self.tableView.tableHeaderView = hero;
}

#pragma mark - Search

- (NSArray<NSDictionary *> *)rygSearchableSettingsEntries {
	NSString *passcode = RYGLocalized(@"Passcode");
	NSMutableArray *out = [NSMutableArray arrayWithArray:@[
		@{ @"title": RYGLocalized(@"Enable lock"), @"subtitle": @"", @"section": @"" },
		@{ @"title": RYGLocalized(@"Change passcode"), @"subtitle": @"", @"section": passcode },
		@{ @"title": RYGLocalized(@"Reset passcode"), @"subtitle": RYGLocalized(@"Requires your current passcode"), @"section": passcode },
	]];

	if ([self hasBiometric]) {
		NSString *kind = [RYGLockManager biometricKindDisplayName] ?: RYGLocalized(@"Biometric");
		[out addObject:@{ @"title": [NSString stringWithFormat:RYGLocalized(@"Use %@"), kind], @"subtitle": @"", @"section": passcode }];
	}

	NSString *targets = RYGLocalized(@"Lock targets");
	for (RYGLockGroupInfo *info in RYGLockAllGroups())
		if (info.displayName.length) [out addObject:@{ @"title": info.displayName, @"subtitle": @"", @"section": targets }];

	return out;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
	return self.configured ? 3 : 0;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!self.configured) return 0;

	if (section == 0) return 1;

	if (section == 1) {
		return [self hasBiometric] ? 3 : 2;
	}

	return RYGLockAllGroups().count;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (!self.configured) return nil;

	if (section == 1) return RYGLocalized(@"Passcode");
	if (section == 2) return RYGLocalized(@"Lock targets");

	return nil;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.configured) return nil;

	if (section == 0) {
		return RYGLocalized(@"Master switch. Turn off to disable every lock target without losing per-target configuration.");
	}

	if (section == 2) {
		return RYGLocalized(@"Each target has its own enable, timeout, and re-lock configuration.");
	}

	return nil;
}

- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) return [self masterCell];
	if (indexPath.section == 1) return [self passcodeRowAt:indexPath.row];
	return [self targetRowAt:indexPath.row];
}

#pragma mark - Cell Helpers

- (UITableViewCell *)baseCellWithTitle:(NSString *)title
							  subtitle:(NSString *)subtitle
								  image:(UIImage *)image
							  tintColor:(UIColor *)tintColor {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = title;
	config.textProperties.color = UIColor.labelColor;

	if (subtitle.length) {
		config.secondaryText = subtitle;
		config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
		config.textToSecondaryTextVerticalPadding = 4.5;
	}

	if (image) {
		config.image = image;
		config.imageProperties.tintColor = tintColor ?: UIColor.labelColor;
		config.imageProperties.maximumSize = CGSizeMake(25.0, 25.0);
		config.imageToTextPadding = 14.0;
	}

	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title
								subtitle:(NSString *)subtitle
									image:(UIImage *)image
								tintColor:(UIColor *)tintColor
								 enabled:(BOOL)enabled
								  action:(SEL)action {
	UITableViewCell *cell = [self baseCellWithTitle:title
										   subtitle:subtitle
											  image:image
										  tintColor:tintColor];

	UISwitch *toggle = UISwitch.new;
	toggle.on = enabled;
	toggle.onTintColor = [self primaryColor];
	[toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];

	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}

#pragma mark - Cells

- (UITableViewCell *)masterCell {
	return [self switchCellWithTitle:RYGLocalized(@"Enable lock")
							subtitle:nil
								image:[RYGIcon imageNamed:@"lock.fill" pointSize:22.0]
							tintColor:[self primaryColor]
							 enabled:[RYGUtils getBoolPref:@"lock_master_enabled"]
							  action:@selector(toggleMaster:)];
}

- (UITableViewCell *)passcodeRowAt:(NSInteger)row {
	if (row == 0) {
		UITableViewCell *cell = [self baseCellWithTitle:RYGLocalized(@"Change passcode")
											   subtitle:nil
												  image:[RYGIcon imageNamed:@"key.fill" pointSize:22.0]
											  tintColor:[self primaryColor]];

		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (row == 1) {
		UITableViewCell *cell = [self baseCellWithTitle:RYGLocalized(@"Reset passcode")
											   subtitle:RYGLocalized(@"Requires your current passcode")
												  image:[RYGIcon imageNamed:@"arrow.counterclockwise.circle.fill" pointSize:22.0]
											  tintColor:UIColor.systemRedColor];

		UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
		config.textProperties.color = UIColor.systemRedColor;
		cell.contentConfiguration = config;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	}

	if (row == 2 && [self hasBiometric]) {
		NSString *kind = [RYGLockManager biometricKindDisplayName] ?: RYGLocalized(@"Biometric");
		NSString *symbol = [RYGLockManager biometricSymbolName] ?: @"faceid";

		return [self switchCellWithTitle:[NSString stringWithFormat:RYGLocalized(@"Use %@"), kind]
								subtitle:nil
									image:[RYGIcon imageNamed:symbol pointSize:22.0]
								tintColor:[self primaryColor]
								 enabled:[RYGUtils getBoolPref:@"lock_biometric_enabled"]
								  action:@selector(toggleBiometric:)];
	}

	return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

- (UITableViewCell *)targetRowAt:(NSInteger)row {
	NSArray *groups = RYGLockAllGroups();
	if (row >= (NSInteger)groups.count) {
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}

	RYGLockGroupInfo *info = groups[row];

	BOOL enabled = [RYGUtils getBoolPref:RYGLockPrefEnabled(info.identifier)];
	NSString *subtitle = [self summaryForTarget:info enabled:enabled];

	UITableViewCell *cell = [self baseCellWithTitle:info.displayName
										   subtitle:subtitle
											  image:[RYGIcon imageNamed:info.iconSymbol pointSize:22.0]
										  tintColor:UIColor.labelColor];

	UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
	config.secondaryTextProperties.color = enabled ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}

#pragma mark - Summary

- (NSString *)summaryForTarget:(RYGLockGroupInfo *)info enabled:(BOOL)enabled {
	if (!enabled) return RYGLocalized(@"Off");

	NSMutableArray *parts = [NSMutableArray arrayWithObject:RYGLocalized(@"On")];

	if ([RYGUtils getBoolPref:RYGLockPrefRelockOnDismiss(info.identifier)]) {
		[parts addObject:RYGLocalized(@"every use")];
	} else {
		double timeout = [RYGUtils getDoublePref:RYGLockPrefIdleTimeout(info.identifier)];
		if (timeout > 0.0) [parts addObject:[self formattedIdleTimeout:timeout]];
	}

	if ([RYGUtils getBoolPref:RYGLockPrefRelockOnBackground(info.identifier)]) {
		[parts addObject:RYGLocalized(@"re-lock on bg")];
	}

	if ([info.identifier isEqualToString:RYGLockGroupChats]) {
		NSInteger count = [[RYGLockManager shared] lockedChatIDs].count;
		if (count > 0) {
			[parts addObject:[NSString stringWithFormat:RYGLocalized(@"%ld locked"), (long)count]];
		}
	}

	return [parts componentsJoinedByString:@" · "];
}

- (NSString *)formattedIdleTimeout:(double)timeout {
	if (timeout < 60.0) {
		return [NSString stringWithFormat:RYGLocalized(@"%lds idle"), (long)timeout];
	}

	if (timeout < 3600.0) {
		return [NSString stringWithFormat:RYGLocalized(@"%ldm idle"), (long)(timeout / 60.0)];
	}

	return [NSString stringWithFormat:RYGLocalized(@"%ldh idle"), (long)(timeout / 3600.0)];
}

#pragma mark - Actions

- (void)toggleMaster:(UISwitch *)sender {
	[[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:@"lock_master_enabled"];

	// Toggling master either way nukes every session so the next gated open prompts fresh.
	[[RYGLockManager shared] lockAll];

	[self.tableView reloadData];
}

- (void)toggleBiometric:(UISwitch *)sender {
	[[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:@"lock_biometric_enabled"];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (!self.configured) return;

	if (indexPath.section == 1) {
		if (indexPath.row == 0) {
			[self tapChangePasscode];
		} else if (indexPath.row == 1) {
			[self tapResetPasscode];
		}

		return;
	}

	if (indexPath.section == 2) {
		NSArray *groups = RYGLockAllGroups();
		if (indexPath.row >= (NSInteger)groups.count) return;

		RYGLockGroupInfo *info = groups[indexPath.row];
		RYGLockGroupDetailViewController *vc = [[RYGLockGroupDetailViewController alloc] initWithGroupID:info.identifier];

		[self.navigationController pushViewController:vc animated:YES];
	}
}

#pragma mark - Setup / Change / Reset

- (void)tapSetPasscode {
	RYGLockSetupViewController *setup = [[RYGLockSetupViewController alloc] initWithCodeLength:4];

	__weak typeof(self) weakSelf = self;

	setup.completion = ^(__unused BOOL success) {
		[weakSelf reloadOnMain];
	};

	[self presentFullscreenController:setup];
}

- (void)tapChangePasscode {
	RYGLockPasscodeViewController *verify = [[RYGLockPasscodeViewController alloc]
		initWithTitle:RYGLocalized(@"Confirm current passcode")
			 subtitle:RYGLocalized(@"Enter your current passcode to change it")];

	verify.allowsBiometric = YES;
	verify.allowsCancel = YES;

	__weak typeof(self) weakSelf = self;

	verify.completion = ^(BOOL success) {
		if (!success) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			NSInteger length = [[RYGLockManager shared] passcodeLength];
			RYGLockSetupViewController *setup = [[RYGLockSetupViewController alloc] initWithCodeLength:length];

			setup.completion = ^(BOOL changed) {
				[self reloadOnMain];

				if (changed) {
					RYGNotifySuccess(RYG_NOTIF_LOCK_CHANGED, RYGLocalized(@"Passcode changed"), nil);
				}
			};

			[self presentFullscreenController:setup];
		});
	};

	[self presentFullscreenController:verify];
}

- (void)tapResetPasscode {
	RYGLockPasscodeViewController *verify = [[RYGLockPasscodeViewController alloc]
		initWithTitle:RYGLocalized(@"Confirm current passcode")
			 subtitle:RYGLocalized(@"Enter your current passcode to reset it")];

	// Important: reset should ask for the passcode, not Face ID.
	verify.allowsBiometric = NO;
	verify.allowsCancel = YES;

	__weak typeof(self) weakSelf = self;

	verify.completion = ^(BOOL success) {
		if (!success) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			[self presentResetConfirmation];
		});
	};

	[self presentFullscreenController:verify];
}

- (void)presentResetConfirmation {
	if (self.presentedViewController) {
		__weak typeof(self) weakSelf = self;

		[self dismissViewControllerAnimated:NO completion:^{
			[weakSelf presentResetConfirmation];
		}];

		return;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset passcode?")
																   message:RYGLocalized(@"This clears the passcode, disables every lock target, and unlocks all chats. Gallery and Keep-Deleted data are untouched.")
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
											  style:UIAlertActionStyleCancel
											handler:nil]];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset")
											  style:UIAlertActionStyleDestructive
											handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		[[RYGLockManager shared] clearPasscodeAndState];

		RYGNotifySuccess(RYG_NOTIF_LOCK_RESET, RYGLocalized(@"Passcode reset"), nil);

		[self reloadOnMain];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Presentation

- (void)presentFullscreenController:(UIViewController *)controller {
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationFullScreen;

	[self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Helpers

- (BOOL)hasBiometric {
	return [RYGLockManager availableBiometricKind] != RYGBiometricKindNone;
}

- (UIColor *)primaryColor {
	return [RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor;
}

@end
