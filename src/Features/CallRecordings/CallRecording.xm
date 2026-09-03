#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../InstagramHeaders.h"
#import "RYGCallRecorder.h"
#import "RYGCallRecordingModels.h"
#import "RYGCallRecordingStorage.h"
#import "RYGCallAudioTap.h"
#import "RYGCallRecordingGate.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL rygCallAutoHandled = NO;

@interface IGVideoCallViewController (RYGCallRec)
- (void)ryg_recordTapped;
- (void)ryg_recordLongPressed:(UILongPressGestureRecognizer *)g;
- (void)ryg_tryAutoRecord;
- (void)ryg_stateChanged;
- (void)ryg_installButton;
@end

static const void *kRYGRecRevealKey = &kRYGRecRevealKey;

static void rygMarkRevealed(UIView *button) {
	objc_setAssociatedObject(button, kRYGRecRevealKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface _RYGCallChromeMirror : NSObject
- (instancetype)initWithChrome:(UIView *)chrome button:(UIView *)button;
@end

@implementation _RYGCallChromeMirror {
	__weak UIView *_chrome;
	__weak UIView *_button;
	BOOL _wasVisible;
}

- (instancetype)initWithChrome:(UIView *)chrome button:(UIView *)button {
	if ((self = [super init])) {
		_chrome = chrome;
		_button = button;
		[chrome addObserver:self forKeyPath:@"alpha" options:NSKeyValueObservingOptionInitial context:NULL];
		[chrome addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionInitial context:NULL];
	}
	return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	UIView *chrome = _chrome, *button = _button;
	if (!chrome || !button) return;
	button.alpha = chrome.alpha;
	button.hidden = chrome.hidden;
	BOOL visible = !chrome.hidden && chrome.alpha > 0.5;
	if (visible && !_wasVisible) rygMarkRevealed(button);
	_wasVisible = visible;
}

- (void)dealloc {
	UIView *chrome = _chrome;
	if (!chrome) return;
	[chrome removeObserver:self forKeyPath:@"alpha"];
	[chrome removeObserver:self forKeyPath:@"hidden"];
}

@end

#pragma mark - Runtime helpers

static id rygIvar(id obj, const char *name) {
	if (!obj) return nil;
	Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
	return iv ? object_getIvar(obj, iv) : nil;
}

static NSString *rygUserField(id user, NSString *key) {
	if (!user) return nil;
	id cache = rygIvar(user, "_fieldCache");
	if ([cache isKindOfClass:NSDictionary.class]) {
		id v = cache[key];
		if ([v isKindOfClass:NSString.class]) return v;
		if ([v isKindOfClass:NSURL.class]) return [(NSURL *)v absoluteString];
	}
	return nil;
}

static NSString *rygStr(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

static BOOL rygBoolIvar(id obj, const char *name) {
	if (!obj) return NO;
	Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
	if (!iv) return NO;
	return *(BOOL *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

static id rygTry(id obj, NSString *sel) {
	if (!obj) return nil;
	SEL s = NSSelectorFromString(sel);
	if (![obj respondsToSelector:s]) return nil;
	return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}

// Named ivars only — a blind class-copy dump hits the weak _delgate and crashes.
static RYGCallRecording *rygBuildCallMeta(UIViewController *vc) {
	RYGCallRecording *m = [RYGCallRecording new];
	if (!vc) return m;
	id session = rygIvar(vc, "_videoCallSession");
	id tds = rygIvar(session, "_threadDataSource");
	id metadata = rygIvar(tds, "_latestThreadMetadata_Deprecated");
	m.threadId = rygStr(rygIvar(tds, "_threadId")) ?: rygStr(rygIvar(metadata, "_groupThreadJid"));
	id usersRaw = rygIvar(metadata, "_users");
	NSArray *users = [usersRaw isKindOfClass:NSArray.class] ? usersRaw
		: ([usersRaw isKindOfClass:NSSet.class] ? [(NSSet *)usersRaw allObjects] : nil);

	NSString *ownerPK = [RYGUtils currentUserPK];
	id peer = nil;
	for (id u in users) {
		NSString *pk = rygUserField(u, @"strong_id__") ?: rygUserField(u, @"pk");
		if (ownerPK.length && [pk isEqualToString:ownerPK]) continue;
		peer = u; break;
	}
	if (!peer) peer = users.firstObject;

	m.isGroup = rygBoolIvar(metadata, "_isGroup") || users.count > 2;   // _users is only the loaded subset
	m.threadTitle = rygStr(rygIvar(metadata, "_threadTitle"));
	if (m.isGroup && !m.threadTitle.length) {
		NSMutableArray *names = [NSMutableArray array];
		for (id u in users) {
			NSString *n = rygUserField(u, @"username");
			NSString *pk = rygUserField(u, @"strong_id__") ?: rygUserField(u, @"pk");
			if (n.length && !(ownerPK.length && [pk isEqualToString:ownerPK])) [names addObject:n];
		}
		if (names.count) m.threadTitle = [names componentsJoinedByString:@", "];
	}
	if (!m.isGroup && peer) {
		m.peerPk = rygUserField(peer, @"strong_id__") ?: rygUserField(peer, @"pk");
		m.peerUsername = rygUserField(peer, @"username") ?: rygStr(rygIvar(metadata, "_username"));
		m.peerFullName = rygUserField(peer, @"full_name");
		m.peerProfilePicURL = rygUserField(peer, @"profile_pic_url");
	}
	return m;
}

#pragma mark - Call VC (button above the footer bar + auto-record lifecycle)

static const void *kRYGRecBtnKey = &kRYGRecBtnKey;
static const void *kRYGRecMirrorKey = &kRYGRecMirrorKey;
static void *gRecCallVCPtr = NULL;   // compared only, never messaged

static void rygHaptic(void) {
	UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[g impactOccurred];
}

static void rygStyleButton(RYGChromeButton *btn) {
	BOOL rec = [RYGCallRecorder sharedRecorder].isRecording;
	btn.symbolName = rec ? @"stop.circle.fill" : @"record.circle";
	btn.iconTint = rec ? [UIColor systemRedColor] : [UIColor whiteColor];
	btn.bubbleColor = rec ? [[UIColor systemRedColor] colorWithAlphaComponent:0.30]
						  : [[UIColor blackColor] colorWithAlphaComponent:0.40];
}

%group CallRec

%hook IGVideoCallViewController

%new
- (void)ryg_recordTapped {
	RYGChromeButton *btn = objc_getAssociatedObject(self, kRYGRecBtnKey);
	RYGCallRecorder *rec = [RYGCallRecorder sharedRecorder];
	if (rec.isRecording) {
		[rec stop];
		rygCallAutoHandled = YES;
		rygHaptic();
		return;
	}
	if (rec.isFinalizing) return;
	// The tap that brings IG's auto-hidden chrome back also lands here.
	if ([self respondsToSelector:@selector(isShowingChrome)] && ![self isShowingChrome]) return;
	NSNumber *revealed = objc_getAssociatedObject(btn, kRYGRecRevealKey);
	if (revealed && CACurrentMediaTime() - revealed.doubleValue < 0.45) return;
	RYGCallRecording *meta = rygBuildCallMeta(self);
	gRecCallVCPtr = (__bridge void *)self;
	BOOL wantVideo = [RYGUtils getBoolPref:@"call_recordings_video"];
	[rec startWithVideo:wantVideo meta:meta automatic:NO];
	if (rec.isRecording) { rygCallAutoHandled = YES; rygHaptic(); }
}

%new
- (void)ryg_recordLongPressed:(UILongPressGestureRecognizer *)g {
	if (g.state != UIGestureRecognizerStateBegan) return;
	RYGCallRecording *meta = rygBuildCallMeta(self);
	NSString *identity = [RYGCallRecordingStorage identifierForRecording:meta];
	NSString *ownerPK = [RYGUtils currentUserPK] ?: @"anon";
	NSString *name = meta.displayName;
	BOOL ignored = [RYGCallRecordingStorage isCallIgnored:identity ownerPK:ownerPK];

	UIAlertController *ac = [UIAlertController alertControllerWithTitle:name
															   message:RYGLocalized(@"Ignored chats aren't auto-recorded. You can still record manually.")
														preferredStyle:UIAlertControllerStyleActionSheet];
	[ac addAction:[UIAlertAction actionWithTitle:(ignored ? RYGLocalized(@"Remove from ignore list") : RYGLocalized(@"Ignore auto-record for this chat"))
										   style:(ignored ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive) handler:^(UIAlertAction *a) {
		[RYGCallRecordingStorage setCall:identity ignored:!ignored name:name ownerPK:ownerPK];
		RYGNotifyInfo(RYG_NOTIF_CALL_RECORDING, ignored ? RYGLocalized(@"Auto-record on") : RYGLocalized(@"Auto-record ignored"), name);
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	RYGChromeButton *btn = objc_getAssociatedObject(self, kRYGRecBtnKey);
	ac.popoverPresentationController.sourceView = btn ?: self.view;
	ac.popoverPresentationController.sourceRect = btn ? btn.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:ac animated:YES completion:nil];
}

%new
- (void)ryg_stateChanged {
	RYGChromeButton *btn = objc_getAssociatedObject(self, kRYGRecBtnKey);
	if (btn) rygStyleButton(btn);
}

%new
- (void)ryg_installButton {
	if (![RYGUtils getBoolPref:@"call_recordings_enabled"]) return;
	RYGChromeButton *btn = objc_getAssociatedObject(self, kRYGRecBtnKey);
	if (btn) { [self.view bringSubviewToFront:btn]; return; }

	btn = [[RYGChromeButton alloc] initWithSymbol:@"record.circle" pointSize:26 diameter:52];
	btn.translatesAutoresizingMaskIntoConstraints = NO;
	[btn addTarget:self action:@selector(ryg_recordTapped) forControlEvents:UIControlEventTouchUpInside];
	[btn addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ryg_recordLongPressed:)]];
	rygStyleButton(btn);
	[self.view addSubview:btn];

	id footerVC = rygIvar(self, "_footerViewController");
	UIView *footer = rygTry(footerVC, @"view");
	NSLayoutConstraint *bottom;
	if ([footer isKindOfClass:UIView.class] && [footer isDescendantOfView:self.view])
		bottom = [btn.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-10];
	else
		bottom = [btn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-64];

	[NSLayoutConstraint activateConstraints:@[
		[btn.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		bottom,
		[btn.widthAnchor constraintEqualToConstant:52],
		[btn.heightAnchor constraintEqualToConstant:52],
	]];

	objc_setAssociatedObject(self, kRYGRecBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	rygMarkRevealed(btn);
	if ([footer isKindOfClass:UIView.class]) {
		objc_setAssociatedObject(self, kRYGRecMirrorKey, [[_RYGCallChromeMirror alloc] initWithChrome:footer button:btn], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		RYGProbeOnce(@"callrec.chrome-mirror", nil);
	} else {
		RYGProbeOnce(@"callrec.chrome-mirror-missing", nil);
	}
	if ([self respondsToSelector:@selector(isShowingChrome)]) RYGProbeOnce(@"callrec.chrome-state-api", nil);
	else RYGProbeOnce(@"callrec.chrome-state-api-missing", nil);
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ryg_stateChanged)
											   name:RYGCallRecorderStateDidChangeNotification object:nil];
}

// Identity resolves after the call screen appears, so an early decision misses the ignore list.
%new
- (void)ryg_tryAutoRecord {
	if (![RYGUtils getBoolPref:@"call_recordings_enabled"]) return;
	BOOL autoRecord = [RYGUtils getBoolPref:@"call_recordings_auto"];
	RYGCallRecorder *rec = [RYGCallRecorder sharedRecorder];
	// The VPIO stop is debounced, so a manual recording can ride into the next call.
	if (!autoRecord && !rec.isRecording) return;

	RYGCallRecording *meta = rygBuildCallMeta(self);
	NSString *ident = [RYGCallRecordingStorage identifierForRecording:meta];
	BOOL resolved = ident.length && ![ident isEqualToString:@"uncategorized"];

	// Another resolved chat mid-recording = a new call; the old one commits under its own.
	if (rec.isRecording) {
		NSString *cur = rec.currentIdentifier;
		if (resolved && cur.length && ![cur isEqualToString:ident]) {
			[rec stop];
			rygCallAutoHandled = NO;
			return;   // next pass (after finalize) decides this call
		}
		if (!cur.length || [cur isEqualToString:@"uncategorized"]) [rec backfillMeta:meta];
	}

	if (!autoRecord) return;
	if (rygCallAutoHandled) return;
	if (rec.isRecording || rec.isFinalizing) return;
	if (!resolved && ![RYGCallAudioTap isCallAudioLive]) return;   // too early — wait for identity or connection

	rygCallAutoHandled = YES;
	if (resolved && [RYGCallRecordingStorage isCallIgnored:ident ownerPK:([RYGUtils currentUserPK] ?: @"anon")]) {
		return;
	}
	gRecCallVCPtr = (__bridge void *)self;
	BOOL wantVideo = [RYGUtils getBoolPref:@"call_recordings_video"];
	[rec startWithVideo:wantVideo meta:meta automatic:YES];
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	[self ryg_installButton];
	[self ryg_tryAutoRecord];
}

- (void)viewDidLayoutSubviews {
	%orig;
	RYGChromeButton *btn = objc_getAssociatedObject(self, kRYGRecBtnKey);
	if (btn) [self.view bringSubviewToFront:btn];
	else [self ryg_installButton];
	[self ryg_tryAutoRecord];
}

- (void)_handleCallEndedForSession:(id)session callEndedModel:(id)model {
	RYGCallRecorder *rec = [RYGCallRecorder sharedRecorder];
	if (rec.isRecording) { [rec backfillMeta:rygBuildCallMeta(self)]; [rec stop]; }
	rygCallAutoHandled = NO;
	%orig;
}

- (void)dealloc {
	objc_setAssociatedObject(self, kRYGRecMirrorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	// This VC deallocs only when the call truly ends — minimized/PiP calls stay retained.
	if ((__bridge void *)self == gRecCallVCPtr) {
		gRecCallVCPtr = NULL;
		RYGCallRecorder *rec = [RYGCallRecorder sharedRecorder];
		if (rec.isRecording) [rec stop];
		rygCallAutoHandled = NO;
	}
	[NSNotificationCenter.defaultCenter removeObserver:self name:RYGCallRecorderStateDidChangeNotification object:nil];
	%orig;
}

%end

%end

%ctor {
	if (!RYGCallRecordingEnabled()) return;
	%init(CallRec);
	[NSNotificationCenter.defaultCenter addObserverForName:RYGCallRecorderCallDidEndNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
		rygCallAutoHandled = NO;   // let the next call auto-record
	}];
}
