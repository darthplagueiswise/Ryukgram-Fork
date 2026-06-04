#import "SCIReelsPlaybackMenu.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>

static const void *kSCIReelsPlaybackLPRKey = &kSCIReelsPlaybackLPRKey;
static const NSInteger kSCIReelsPlaybackPanelTag = 988422;

#pragma mark - Module registry

typedef struct {
	NSString *moduleID;
	SCIReelsModuleIsOn isOn;
	SCIReelsModuleBuildSection build;
} SCIReelsModuleEntry;

static NSMutableArray *sciModuleEntries(void) {
	static NSMutableArray *arr;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ arr = [NSMutableArray array]; });
	return arr;
}

@implementation SCIReelsPlaybackMenu

+ (void)registerModuleWithID:(NSString *)moduleID
                        isOn:(SCIReelsModuleIsOn)isOn
                buildSection:(SCIReelsModuleBuildSection)buildSection {
	if (!moduleID || !isOn || !buildSection) return;
	NSMutableArray *list = sciModuleEntries();
	@synchronized (list) {
		[list addObject:@{ @"id": moduleID, @"isOn": [isOn copy], @"build": [buildSection copy] }];
	}
}

+ (BOOL)anyModuleEnabled {
	NSArray *snapshot;
	NSMutableArray *list = sciModuleEntries();
	@synchronized (list) { snapshot = [list copy]; }
	for (NSDictionary *entry in snapshot) {
		SCIReelsModuleIsOn isOn = entry[@"isOn"];
		if (isOn && isOn()) return YES;
	}
	return NO;
}

+ (NSArray<UIView *> *)buildSections {
	NSMutableArray<UIView *> *out = [NSMutableArray array];
	NSArray *snapshot;
	NSMutableArray *list = sciModuleEntries();
	@synchronized (list) { snapshot = [list copy]; }
	for (NSDictionary *entry in snapshot) {
		SCIReelsModuleIsOn isOn = entry[@"isOn"];
		SCIReelsModuleBuildSection build = entry[@"build"];
		if (!isOn || !isOn() || !build) continue;
		UIView *v = build();
		if (v) [out addObject:v];
	}
	return out;
}

@end

#pragma mark - Section card

@implementation SCIReelsPlaybackSection

- (instancetype)initWithTitle:(NSString *)title content:(UIView *)content {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		UILabel *header = [UILabel new];
		header.translatesAutoresizingMaskIntoConstraints = NO;
		header.text = [title uppercaseString];
		header.textColor = [UIColor colorWithWhite:1 alpha:0.55];
		header.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
		[self addSubview:header];

		content.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:content];

		[NSLayoutConstraint activateConstraints:@[
			[header.topAnchor constraintEqualToAnchor:self.topAnchor],
			[header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
			[header.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-18],

			[content.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
			[content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];
	}
	return self;
}

@end

#pragma mark - Panel

@interface SCIReelsPlaybackPanel : UIView
- (void)present;
@end

@implementation SCIReelsPlaybackPanel {
	UIView *_card;
	UIStackView *_stack;
}

- (instancetype)init {
	if ((self = [super initWithFrame:UIScreen.mainScreen.bounds])) {
		self.tag = kSCIReelsPlaybackPanelTag;
		self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(_onBackdropTap:)];
		tap.cancelsTouchesInView = NO;
		[self addGestureRecognizer:tap];

		_card = [UIView new];
		_card.translatesAutoresizingMaskIntoConstraints = NO;
		_card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
		_card.layer.cornerRadius = 22;
		_card.layer.cornerCurve = kCACornerCurveContinuous;
		_card.layer.masksToBounds = YES;
		_card.layer.borderWidth = 0.5;
		_card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
		[self addSubview:_card];

		UILabel *title = [UILabel new];
		title.translatesAutoresizingMaskIntoConstraints = NO;
		title.text = SCILocalized(@"Playback");
		title.textColor = [UIColor whiteColor];
		title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
		[_card addSubview:title];

		UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
		close.translatesAutoresizingMaskIntoConstraints = NO;
		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
			configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
		[close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg]
				forState:UIControlStateNormal];
		close.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
		close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
		close.layer.cornerRadius = 14;
		[close addTarget:self action:@selector(_dismiss) forControlEvents:UIControlEventTouchUpInside];
		[_card addSubview:close];

		_stack = [UIStackView new];
		_stack.translatesAutoresizingMaskIntoConstraints = NO;
		_stack.axis = UILayoutConstraintAxisVertical;
		_stack.spacing = 14;
		_stack.alignment = UIStackViewAlignmentFill;
		[_card addSubview:_stack];

		NSArray<UIView *> *sections = [SCIReelsPlaybackMenu buildSections];
		for (NSUInteger i = 0; i < sections.count; i++) {
			[_stack addArrangedSubview:sections[i]];
			if (i + 1 < sections.count) {
				UIView *divider = [UIView new];
				divider.translatesAutoresizingMaskIntoConstraints = NO;
				divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
				[divider.heightAnchor constraintEqualToConstant:0.5].active = YES;
				[_stack addArrangedSubview:divider];
			}
		}

		[NSLayoutConstraint activateConstraints:@[
			[_card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
			[_card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
			[_card.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],

			[title.topAnchor constraintEqualToAnchor:_card.topAnchor constant:14],
			[title.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:18],

			[close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
			[close.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
			[close.widthAnchor constraintEqualToConstant:28],
			[close.heightAnchor constraintEqualToConstant:28],

			[_stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
			[_stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
			[_stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
			[_stack.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-16],
		]];
	}
	return self;
}

- (void)_onBackdropTap:(UITapGestureRecognizer *)gr {
	CGPoint pt = [gr locationInView:self];
	if (CGRectContainsPoint(_card.frame, pt)) return;
	[self _dismiss];
}

- (void)present {
	UIWindow *win = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if (![s isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)s).windows) {
			if (w.isKeyWindow) { win = w; break; }
		}
		if (win) break;
		win = ((UIWindowScene *)s).windows.firstObject;
	}
	if (!win) return;

	[[win viewWithTag:kSCIReelsPlaybackPanelTag] removeFromSuperview];

	self.frame = win.bounds;
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[win addSubview:self];

	_card.transform = CGAffineTransformMakeTranslation(0, 140);
	_card.alpha = 0;
	[UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.6
						options:UIViewAnimationOptionCurveEaseOut animations:^{
		self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
		_card.transform = CGAffineTransformIdentity;
		_card.alpha = 1.0;
	} completion:nil];
}

- (void)_dismiss {
	[UIView animateWithDuration:0.20 animations:^{
		self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
		_card.transform = CGAffineTransformMakeTranslation(0, 140);
		_card.alpha = 0;
	} completion:^(BOOL fin) {
		[self removeFromSuperview];
	}];
}

@end

#pragma mark - Long-press target

@interface SCIReelsPlaybackLPTarget : NSObject
+ (instancetype)shared;
- (void)longPress:(UILongPressGestureRecognizer *)gr;
@end

@implementation SCIReelsPlaybackLPTarget

+ (instancetype)shared {
	static SCIReelsPlaybackLPTarget *t;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ t = [SCIReelsPlaybackLPTarget new]; });
	return t;
}

- (void)longPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateBegan) return;
	if (![SCIReelsPlaybackMenu anyModuleEnabled]) return;

	UIView *anchor = gr.view;
	if ([anchor isKindOfClass:[UIControl class]]) {
		UIControl *c = (UIControl *)anchor;
		[c cancelTrackingWithEvent:nil];
		c.highlighted = NO;
	}

	UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc]
		initWithStyle:UIImpactFeedbackStyleMedium];
	[h impactOccurred];

	[[SCIReelsPlaybackPanel new] present];
}

@end

#pragma mark - Hooks

%hook IGSundialViewerVerticalUFI

- (void)layoutSubviews {
	%orig;
	if (![SCIReelsPlaybackMenu anyModuleEnabled]) return;

	UIButton *more = nil;
	@try { more = [self valueForKey:@"moreOptionsButton"]; } @catch (__unused id e) {}
	if (!more) return;
	if (objc_getAssociatedObject(more, kSCIReelsPlaybackLPRKey)) return;

	UILongPressGestureRecognizer *lpr = [[UILongPressGestureRecognizer alloc]
		initWithTarget:[SCIReelsPlaybackLPTarget shared] action:@selector(longPress:)];
	lpr.minimumPressDuration = 0.32;
	lpr.cancelsTouchesInView = YES;
	[more addGestureRecognizer:lpr];
	objc_setAssociatedObject(more, kSCIReelsPlaybackLPRKey, lpr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end
