#import "RYGLockPasscodeViewController.h"
#import "RYGLockPasscodeView.h"

#import "../RYGLockManager.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Localization/RYGLocalization.h"

#import <LocalAuthentication/LocalAuthentication.h>

@interface RYGLockPasscodeViewController () <RYGLockPasscodeViewDelegate>

@property (nonatomic, strong) RYGLockPasscodeView *pad;
@property (nonatomic, strong, nullable) LAContext *liveContext;

@property (nonatomic) NSInteger failCount;
@property (nonatomic) BOOL didFinish;
@property (nonatomic) BOOL didAutoRunBiometric;
@property (nonatomic) BOOL wasNavigationBarHidden;

@end

@implementation RYGLockPasscodeViewController

- (instancetype)init {
	return [self initWithTitle:RYGLocalized(@"Enter passcode") subtitle:nil];
}

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
	if ((self = [super init])) {
		_promptTitle = [title copy];
		_promptSubtitle = [subtitle copy];
		_allowsBiometric = YES;
		_allowsCancel = YES;

		self.modalPresentationStyle = UIModalPresentationFullScreen;
	}
	return self;
}

#pragma mark - View

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	self.pad = RYGLockPasscodeView.new;
	self.pad.translatesAutoresizingMaskIntoConstraints = NO;
	self.pad.delegate = self;
	self.pad.codeLength = [[RYGLockManager shared] passcodeLength];
	self.pad.titleText = self.promptTitle.length ? self.promptTitle : RYGLocalized(@"Enter passcode");
	self.pad.subtitleText = self.promptSubtitle.length ? self.promptSubtitle : nil;
	self.pad.biometricButtonVisible = [self shouldAllowBiometric];

	if (self.allowsCancel) {
		self.pad.cancelTitle = RYGLocalized(@"Cancel");
	}

	[self.view addSubview:self.pad];

	UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

	[NSLayoutConstraint activateConstraints:@[
		[self.pad.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
		[self.pad.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
		[self.pad.topAnchor constraintEqualToAnchor:guide.topAnchor constant:18.0],
		[self.pad.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-18.0],
	]];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	self.wasNavigationBarHidden = self.navigationController.navigationBarHidden;
	[self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];

	if (!self.didAutoRunBiometric && [self shouldAllowBiometric]) {
		self.didAutoRunBiometric = YES;
		[self runBiometric];
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	[self invalidateLiveContext];

	if (!self.didFinish) {
		[self.navigationController setNavigationBarHidden:self.wasNavigationBarHidden animated:animated];
	}
}

- (void)dealloc {
	[self invalidateLiveContext];
}

#pragma mark - Helpers

- (BOOL)shouldAllowBiometric {
	return self.allowsBiometric && [[RYGLockManager shared] isBiometricEnabledByUser];
}

- (void)runBiometric {
	if (self.didFinish || self.liveContext) return;

	NSString *reason = self.promptTitle.length ? self.promptTitle : RYGLocalized(@"Unlock Instagram");

	__weak typeof(self) weakSelf = self;

	self.liveContext = [[RYGLockManager shared] evaluateBiometricWithReason:reason completion:^(BOOL success, __unused NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || self.didFinish) return;

			self.liveContext = nil;

			if (success) {
				[self finishSuccess];
			}
		});
	}];
}

- (void)invalidateLiveContext {
	LAContext *context = self.liveContext;
	if (!context) return;

	self.liveContext = nil;
	[context invalidate];
}

#pragma mark - Finish

- (void)finishSuccess {
	[self finishWithResult:YES];
}

- (void)finishCancelled {
	[self finishWithResult:NO];
}

- (void)finishWithResult:(BOOL)success {
	if (self.didFinish) return;

	self.didFinish = YES;

	[self invalidateLiveContext];

	void (^callback)(BOOL) = self.completion;
	self.completion = nil;

	BOOL animated = !(success && self.instantDismissOnSuccess);
	[self dismissSelfAnimated:animated then:^{
		if (callback) callback(success);
	}];
}

- (void)dismissSelfAnimated:(BOOL)animated then:(void (^)(void))completion {
	UINavigationController *navigationController = self.navigationController;

	if (navigationController && navigationController.viewControllers.firstObject != self) {
		[navigationController setNavigationBarHidden:self.wasNavigationBarHidden animated:animated];
		[navigationController popViewControllerAnimated:animated];

		if (completion) {
			dispatch_async(dispatch_get_main_queue(), completion);
		}

		return;
	}

	UIViewController *presenter = self.presentingViewController ?: navigationController.presentingViewController;

	if (!presenter) {
		if (completion) {
			dispatch_async(dispatch_get_main_queue(), completion);
		}

		return;
	}

	[presenter dismissViewControllerAnimated:animated completion:completion];
}

#pragma mark - RYGLockPasscodeViewDelegate

- (void)passcodeView:(RYGLockPasscodeView *)view didCompleteCode:(NSString *)code {
	if (self.didFinish) return;

	if ([[RYGLockManager shared] verifyPasscode:code]) {
		[self finishSuccess];
		return;
	}

	self.failCount++;

	[view flashError];
	[view setSubtitleText:[self wrongPasscodeMessage] flash:YES];
}

- (void)passcodeViewDidTapBiometric:(__unused RYGLockPasscodeView *)view {
	[self runBiometric];
}

- (void)passcodeViewDidTapCancel:(__unused RYGLockPasscodeView *)view {
	[self finishCancelled];
}

- (void)passcodeViewDidBeginInput:(__unused RYGLockPasscodeView *)view {
	[self invalidateLiveContext];
}

#pragma mark - Text

- (NSString *)wrongPasscodeMessage {
	if (self.failCount <= 1) {
		return RYGLocalized(@"Wrong passcode");
	}

	return [NSString stringWithFormat:RYGLocalized(@"Wrong passcode • %ld attempts"), (long)self.failCount];
}

@end