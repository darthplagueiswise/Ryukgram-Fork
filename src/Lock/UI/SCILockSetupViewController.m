#import "SCILockSetupViewController.h"
#import "SCILockPasscodeView.h"
#import "../SCILockManager.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"
#import "../../Localization/SCILocalization.h"
#import "../../UI/Notification/SCINotificationCenter.h"
#import "../../UI/Notification/SCINotificationActions.h"

@interface SCILockSetupViewController () <SCILockPasscodeViewDelegate>

@property (nonatomic, strong) SCILockPasscodeView *pad;
@property (nonatomic, strong) UISegmentedControl *lengthSegment;
@property (nonatomic, strong) UIView *segmentContainer;

@property (nonatomic, copy) NSString *firstPass;

@property (nonatomic) BOOL didFinish;
@property (nonatomic) BOOL onConfirmStep;
@property (nonatomic) BOOL wasNavigationBarHidden;

@end

@implementation SCILockSetupViewController

- (instancetype)initWithCodeLength:(NSInteger)length {
	if ((self = [super init])) {
		_codeLength = (length == 6) ? 6 : 4;
		self.modalPresentationStyle = UIModalPresentationFullScreen;
	}
	return self;
}

#pragma mark - View

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Set passcode");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.navigationController.navigationBar.prefersLargeTitles = NO;

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
							 target:self
							 action:@selector(tapCancel)];

	[self buildSegmentControl];
	[self buildPasscodeView];
	[self activateLayout];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	self.wasNavigationBarHidden = self.navigationController.navigationBarHidden;
	[self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	if (!self.didFinish) {
		[self.navigationController setNavigationBarHidden:self.wasNavigationBarHidden animated:animated];
	}
}

#pragma mark - Build

- (void)buildSegmentControl {
	self.segmentContainer = UIView.new;
	self.segmentContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.segmentContainer.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	self.segmentContainer.layer.cornerRadius = 14.0;
	self.segmentContainer.layer.cornerCurve = kCACornerCurveContinuous;

	self.lengthSegment = [[UISegmentedControl alloc] initWithItems:@[
		SCILocalized(@"4 digits"),
		SCILocalized(@"6 digits")
	]];

	self.lengthSegment.translatesAutoresizingMaskIntoConstraints = NO;
	self.lengthSegment.selectedSegmentIndex = self.codeLength == 6 ? 1 : 0;

	if (@available(iOS 13.0, *)) {
		self.lengthSegment.selectedSegmentTintColor = [self primaryColor];
		[self.lengthSegment setTitleTextAttributes:@{
			NSForegroundColorAttributeName: UIColor.whiteColor
		} forState:UIControlStateSelected];
		[self.lengthSegment setTitleTextAttributes:@{
			NSForegroundColorAttributeName: UIColor.labelColor
		} forState:UIControlStateNormal];
	} else {
		self.lengthSegment.tintColor = [self primaryColor];
	}

	[self.lengthSegment addTarget:self action:@selector(lengthChanged) forControlEvents:UIControlEventValueChanged];

	[self.segmentContainer addSubview:self.lengthSegment];
	[self.view addSubview:self.segmentContainer];
}

- (void)buildPasscodeView {
	self.pad = SCILockPasscodeView.new;
	self.pad.translatesAutoresizingMaskIntoConstraints = NO;
	self.pad.delegate = self;
	self.pad.codeLength = self.codeLength;
	self.pad.titleText = SCILocalized(@"Create passcode");
	self.pad.subtitleText = SCILocalized(@"Choose a code you'll remember.");
	self.pad.biometricButtonVisible = NO;

	[self.view addSubview:self.pad];
}

- (void)activateLayout {
	UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

	[NSLayoutConstraint activateConstraints:@[
		[self.segmentContainer.topAnchor constraintEqualToAnchor:guide.topAnchor constant:12.0],
		[self.segmentContainer.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
		[self.segmentContainer.widthAnchor constraintLessThanOrEqualToAnchor:guide.widthAnchor constant:-40.0],
		[self.segmentContainer.widthAnchor constraintEqualToConstant:250.0],
		[self.segmentContainer.heightAnchor constraintEqualToConstant:44.0],

		[self.lengthSegment.leadingAnchor constraintEqualToAnchor:self.segmentContainer.leadingAnchor constant:6.0],
		[self.lengthSegment.trailingAnchor constraintEqualToAnchor:self.segmentContainer.trailingAnchor constant:-6.0],
		[self.lengthSegment.topAnchor constraintEqualToAnchor:self.segmentContainer.topAnchor constant:5.0],
		[self.lengthSegment.bottomAnchor constraintEqualToAnchor:self.segmentContainer.bottomAnchor constant:-5.0],

		[self.pad.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
		[self.pad.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
		[self.pad.topAnchor constraintEqualToAnchor:self.segmentContainer.bottomAnchor constant:10.0],
		[self.pad.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-12.0],
	]];
}

#pragma mark - Actions

- (void)lengthChanged {
	if (self.onConfirmStep) {
		self.lengthSegment.selectedSegmentIndex = self.codeLength == 6 ? 1 : 0;
		return;
	}

	self.codeLength = self.lengthSegment.selectedSegmentIndex == 1 ? 6 : 4;
	self.firstPass = nil;

	self.pad.codeLength = self.codeLength;
	self.pad.titleText = SCILocalized(@"Create passcode");
	[self.pad setSubtitleText:SCILocalized(@"Choose a code you'll remember.") flash:NO];
}

- (void)tapCancel {
	[self finish:NO];
}

#pragma mark - Finish

- (void)finish:(BOOL)success {
	if (self.didFinish) return;

	self.didFinish = YES;

	void (^callback)(BOOL) = self.completion;
	self.completion = nil;

	if (callback) callback(success);

	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - SCILockPasscodeViewDelegate

- (void)passcodeView:(SCILockPasscodeView *)view didCompleteCode:(NSString *)code {
	if (!self.onConfirmStep) {
		self.firstPass = code;
		self.onConfirmStep = YES;

		self.segmentContainer.hidden = YES;

		[view reset];
		view.titleText = SCILocalized(@"Confirm passcode");
		[view setSubtitleText:SCILocalized(@"Re-enter the same passcode") flash:NO];

		return;
	}

	if (![code isEqualToString:self.firstPass]) {
		self.firstPass = nil;
		self.onConfirmStep = NO;

		self.segmentContainer.hidden = NO;
		self.lengthSegment.selectedSegmentIndex = self.codeLength == 6 ? 1 : 0;

		[view flashError];
		view.titleText = SCILocalized(@"Create passcode");
		[view setSubtitleText:SCILocalized(@"Passcodes did not match — try again") flash:YES];

		return;
	}

	NSError *error = nil;
	BOOL saved = [[SCILockManager shared] setPasscode:code error:&error];

	if (!saved) {
		[view flashError];
		[view setSubtitleText:error.localizedDescription.length ? error.localizedDescription : SCILocalized(@"Could not save passcode") flash:YES];
		return;
	}

	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"lock_master_enabled"];

	SCINotifySuccess(SCI_NOTIF_LOCK_SETUP, SCILocalized(@"Passcode set"), nil);

	[self finish:YES];
}

- (void)passcodeViewDidTapCancel:(__unused SCILockPasscodeView *)view {
	[self finish:NO];
}

#pragma mark - Helpers

- (UIColor *)primaryColor {
	return [SCIUtils SCIColor_Primary] ?: UIColor.systemBlueColor;
}

@end