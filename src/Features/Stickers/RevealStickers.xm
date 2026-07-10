// Reveal poll/quiz/slider results on story/reel stickers, force the
// legacy Quiz + Reveal stickers back into the composer tray, and bypass
// the Reveal sticker blur on the consumer side.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../StoriesAndMessages/StoryHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern "C" __weak UIViewController *sciActiveStoryViewerVC;

#pragma mark - Prefs

static inline BOOL sciPref(NSString *key) {
	return [SCIUtils getBoolPref:key];
}

static inline BOOL sciRevealAnyEnabled(void) {
	return sciPref(@"stories_show_poll_votes_count") ||
		   sciPref(@"stories_show_quiz_answer") ||
		   sciPref(@"reels_show_poll_votes_count") ||
		   sciPref(@"reels_show_quiz_answer");
}

static inline BOOL sciSecretAnyEnabled(void) {
	return sciPref(@"force_enable_quiz_sticker") ||
		   sciPref(@"bypass_reveal_sticker");
}

#pragma mark - Runtime helpers

static id sciSend0(id obj, NSString *name) {
	if (!obj) return nil;
	SEL sel = NSSelectorFromString(name);
	if (![obj respondsToSelector:sel]) return nil;
	@try {
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id sciSend1(id obj, SEL sel, id arg) {
	if (!obj || ![obj respondsToSelector:sel]) return nil;
	@try {
		return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
	} @catch (__unused id e) {
		return nil;
	}
}

static Ivar sciIvar(Class cls, const char *name) {
	for (Class c = cls; c && c != NSObject.class; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (iv) return iv;
	}
	return nil;
}

static id sciObjectIvar(id obj, const char *name) {
	Ivar iv = obj ? sciIvar([obj class], name) : nil;
	return iv ? object_getIvar(obj, iv) : nil;
}

static BOOL sciBoolIvar(id obj, const char *name) {
	Ivar iv = obj ? sciIvar([obj class], name) : nil;
	if (!iv) return NO;

	BOOL value = NO;
	memcpy(&value, (uint8_t *)(__bridge void *)obj + ivar_getOffset(iv), sizeof(value));
	return value;
}

static NSUInteger sciNSUIntegerIvar(id obj, const char *name) {
	Ivar iv = obj ? sciIvar([obj class], name) : nil;
	if (!iv) return 0;

	NSUInteger value = 0;
	memcpy(&value, (uint8_t *)(__bridge void *)obj + ivar_getOffset(iv), sizeof(value));
	return value;
}

static NSArray *sciArrayIvar(id obj, const char *name) {
	id value = sciObjectIvar(obj, name);
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static UICollectionView *sciCollectionIvar(id obj, const char *name) {
	id value = sciObjectIvar(obj, name);
	return [value isKindOfClass:UICollectionView.class] ? value : nil;
}

#pragma mark - Context / media lookup

static BOOL sciIsReelsContext(UIResponder *anchor) {
	Class reels = NSClassFromString(@"IGSundialFeedViewController");

	for (UIResponder *r = anchor; r; r = r.nextResponder) {
		if (reels && [r isKindOfClass:reels]) return YES;
		if ([NSStringFromClass([r class]) hasPrefix:@"IGSundial"]) return YES;
	}
	return NO;
}

static BOOL sciShowCounts(UIView *anchor) {
	return sciPref(sciIsReelsContext(anchor) ? @"reels_show_poll_votes_count" : @"stories_show_poll_votes_count");
}

static BOOL sciShowAnswer(UIView *anchor) {
	return sciPref(sciIsReelsContext(anchor) ? @"reels_show_quiz_answer" : @"stories_show_quiz_answer");
}

static IGMedia *sciMediaFromResponderChain(UIResponder *anchor) {
	Class mediaCls = NSClassFromString(@"IGMedia");
	Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
	Class managerCls = NSClassFromString(@"IGStoryStickerManager");
	Class storyVCCls = NSClassFromString(@"IGStoryViewerViewController");
	Class reelsVCCls = NSClassFromString(@"IGSundialFeedViewController");

	for (UIResponder *r = anchor; r; r = r.nextResponder) {
		if (overlayCls && [r isKindOfClass:overlayCls]) {
			id media = sciObjectIvar(r, "_media") ?: sciSend0(r, @"media");
			if ([media isKindOfClass:mediaCls]) return media;

			id manager = sciObjectIvar(r, "_stickerManager") ?: sciSend0(r, @"stickerManager");
			id item = sciSend0(manager, @"currentStoryItem");
			IGMedia *nested = sciExtractMediaFromItem(item);
			if (nested) return nested;
		}

		if (managerCls && [r isKindOfClass:managerCls]) {
			IGMedia *media = sciExtractMediaFromItem(sciSend0(r, @"currentStoryItem"));
			if (media) return media;
		}

		if (storyVCCls && [r isKindOfClass:storyVCCls]) {
			id item = sciSend0(r, @"currentStoryItem");
			IGMedia *media = [item isKindOfClass:mediaCls] ? item : sciExtractMediaFromItem(item);
			if (media) return media;

			id vm = sciSend0(r, @"currentViewModel");
			item = sciSend1(r, @selector(currentStoryItemForViewModel:), vm);
			media = [item isKindOfClass:mediaCls] ? item : sciExtractMediaFromItem(item);
			if (media) return media;
		}

		if (reelsVCCls && [r isKindOfClass:reelsVCCls]) {
			id media = sciSend0(r, @"currentPlaybackMedia");
			if ([media isKindOfClass:mediaCls]) return media;
		}
	}

	if (sciActiveStoryViewerVC) {
		id item = sciSend0(sciActiveStoryViewerVC, @"currentStoryItem");
		IGMedia *media = [item isKindOfClass:mediaCls] ? item : sciExtractMediaFromItem(item);
		if (media) return media;

		id vm = sciSend0(sciActiveStoryViewerVC, @"currentViewModel");
		item = sciSend1(sciActiveStoryViewerVC, @selector(currentStoryItemForViewModel:), vm);
		media = [item isKindOfClass:mediaCls] ? item : sciExtractMediaFromItem(item);
		if (media) return media;
	}

	return nil;
}

static id sciAuthoritativeSticker(UIView *anchor, NSString *mediaArraySel, NSString *entryStickerSel, id viewModel, NSString *idSel) {
	IGMedia *media = sciMediaFromResponderChain(anchor);
	id raw = sciSend0(media, mediaArraySel);
	NSArray *array = [raw isKindOfClass:NSArray.class] ? (NSArray *)raw : nil;
	if (!array.count) return nil;

	NSString *viewId = [[sciSend0(viewModel, idSel) description] copy];

	for (id entry in array) {
		id sticker = sciSend0(entry, entryStickerSel);
		if (!sticker) continue;

		if (viewId.length) {
			NSString *stickerId = [[sciSend0(sticker, idSel) description] copy];
			if ([stickerId isEqualToString:viewId]) return sticker;
		}
	}

	return sciSend0(array.firstObject, entryStickerSel) ?: array.firstObject;
}

#pragma mark - Editing / relayout

static BOOL sciIsEditingSticker(UIView *view) {
	if (sciBoolIvar(view, "_isEditing") ||
		sciBoolIvar(view, "_editing") ||
		sciBoolIvar(view, "_editingQuestion")) {
		return YES;
	}

	for (UIResponder *r = view; r; r = r.nextResponder) {
		NSString *name = NSStringFromClass([r class]);
		if ([name isEqualToString:@"IGStoryStickerTrayViewController"] ||
			[name isEqualToString:@"IGStoryPostCaptureEditingViewController"] ||
			[name isEqualToString:@"IGStoryMediaCompositionEditingViewController"]) {
			return YES;
		}
	}

	return NO;
}

static void sciForceStickerRelayout(UIView *root) {
	if (!root || !sciRevealAnyEnabled()) return;

	Class poll2 = NSClassFromString(@"IGPollStickerV2View");
	Class poll1 = NSClassFromString(@"IGPollStickerView");
	Class slider = NSClassFromString(@"IGSliderStickerView");
	Class quiz = NSClassFromString(@"IGQuizStickerView");

	NSMutableArray *stack = [NSMutableArray arrayWithObject:root];

	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];

		if ((poll2 && [view isKindOfClass:poll2]) ||
			(poll1 && [view isKindOfClass:poll1]) ||
			(slider && [view isKindOfClass:slider]) ||
			(quiz && [view isKindOfClass:quiz])) {
			[view setNeedsLayout];
		}

		for (UIView *subview in view.subviews) {
			[stack addObject:subview];
		}
	}
}

static void sciRetryApply(UIView *view, SEL action) {
	if (!view || !view.window) return;

	__weak UIView *weakView = view;
	NSTimeInterval delays[] = {0.12, 0.45, 0.85};

	for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
		NSTimeInterval delay = delays[i];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			UIView *v = weakView;
			if (v.window) ((void (*)(id, SEL))objc_msgSend)(v, action);
		});
	}
}

#pragma mark - Badge / highlight UI

static char kSciCountBadgeKey;
static char kSciSliderBadgeKey;
static char kSciQuizHighlightKey;
static char kSciQuizShapeKey;

// Capture-aware badge — label + pill inside an SCIChromeCanvas so Hide UI on
// Capture redacts it. Frame driven externally.
@interface SCIStickerBadge : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong, readonly) UILabel *label;
@property (nonatomic, strong, readonly) UIView *bg;
@end

@implementation SCIStickerBadge

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		SCIChromeCanvas *canvas = [SCIChromeCanvas new];
		canvas.userInteractionEnabled = NO;
		canvas.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:canvas];

		UIView *host = canvas.contentContainer;

		_bg = [UIView new];
		_bg.translatesAutoresizingMaskIntoConstraints = NO;
		_bg.userInteractionEnabled = NO;
		_bg.clipsToBounds = YES;

		_label = [UILabel new];
		_label.translatesAutoresizingMaskIntoConstraints = NO;
		_label.textAlignment = NSTextAlignmentCenter;

		[host addSubview:_bg];
		[host addSubview:_label];

		[NSLayoutConstraint activateConstraints:@[
			[canvas.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[canvas.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[canvas.topAnchor constraintEqualToAnchor:self.topAnchor],
			[canvas.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

			[_bg.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
			[_bg.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
			[_bg.topAnchor constraintEqualToAnchor:host.topAnchor],
			[_bg.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],

			[_label.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
			[_label.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
			[_label.topAnchor constraintEqualToAnchor:host.topAnchor],
			[_label.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
		]];
	}
	return self;
}

- (void)setText:(NSString *)text { _label.text = text; }
- (NSString *)text { return _label.text; }
- (CGSize)sizeThatFits:(CGSize)size { return [_label sizeThatFits:size]; }
- (CGSize)intrinsicContentSize { return _label.intrinsicContentSize; }

@end

static SCIStickerBadge *sciBadge(void) {
	SCIStickerBadge *badge = [[SCIStickerBadge alloc] initWithFrame:CGRectZero];
	badge.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
	badge.label.textColor = UIColor.whiteColor;
	badge.bg.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.95 alpha:0.92];
	badge.bg.layer.cornerRadius = 10.0;
	badge.userInteractionEnabled = NO;
	return badge;
}

static SCIStickerBadge *sciBadgeForView(UIView *view, const void *key) {
	SCIStickerBadge *badge = objc_getAssociatedObject(view, key);
	if (!badge) {
		badge = sciBadge();
		[view addSubview:badge];
		objc_setAssociatedObject(view, key, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return badge;
}

static void sciRemoveAssociatedView(UIView *view, const void *key) {
	UIView *old = objc_getAssociatedObject(view, key);
	if (old) {
		[old removeFromSuperview];
		objc_setAssociatedObject(view, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

static void sciSetCountBadge(UIView *view, NSInteger count, double total) {
	SCIStickerBadge *badge = sciBadgeForView(view, &kSciCountBadgeKey);

	badge.text = total > 0.0
		? [NSString stringWithFormat:@" %ld · %.0f%% ", (long)count, 100.0 * (double)count / total]
		: [NSString stringWithFormat:@" %ld ", (long)count];

	[badge sizeToFit];

	CGSize size = badge.bounds.size;
	size.width += 10.0;
	size.height = MAX(size.height + 4.0, 22.0);

	CGRect bounds = view.bounds;
	badge.frame = CGRectMake(bounds.size.width - size.width - 4.0, -size.height * 0.35, size.width, size.height);
	badge.layer.zPosition = 1000.0;

	view.clipsToBounds = NO;
	[view bringSubviewToFront:badge];
}

static void sciSetSliderBadge(UIView *view, NSUInteger count, double average) {
	SCIStickerBadge *badge = sciBadgeForView(view, &kSciSliderBadgeKey);

	badge.text = [NSString stringWithFormat:SCILocalized(@"  %lu votes · avg %.0f%%  "),
		(unsigned long)count,
		average * 100.0
	];

	[badge sizeToFit];

	CGSize size = badge.bounds.size;
	size.height = MAX(size.height, 18.0);

	CGRect bounds = view.bounds;
	badge.frame = CGRectMake((bounds.size.width - size.width) * 0.5, -size.height - 4.0, size.width, size.height);

	view.clipsToBounds = NO;
	[view bringSubviewToFront:badge];
}

static void sciSetHighlight(UIView *view, CGFloat radius) {
	// Shape lives in a chrome-canvas overlay so Hide UI on Capture redacts it.
	SCIChromeCanvas *canvas = objc_getAssociatedObject(view, &kSciQuizHighlightKey);
	CAShapeLayer *layer;

	if (!canvas) {
		canvas = [SCIChromeCanvas new];
		canvas.userInteractionEnabled = NO;
		canvas.translatesAutoresizingMaskIntoConstraints = YES;

		layer = [CAShapeLayer layer];
		UIColor *green = [UIColor colorWithRed:0.24 green:0.76 blue:0.38 alpha:1.0];
		layer.fillColor = [green colorWithAlphaComponent:0.35].CGColor;
		layer.strokeColor = green.CGColor;
		layer.lineWidth = 2.0;

		[canvas.contentContainer.layer addSublayer:layer];
		[view addSubview:canvas];

		objc_setAssociatedObject(view, &kSciQuizHighlightKey, canvas, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(canvas, &kSciQuizShapeKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	} else {
		layer = objc_getAssociatedObject(canvas, &kSciQuizShapeKey);
	}

	canvas.frame = view.bounds;
	[view bringSubviewToFront:canvas];

	CGRect rect = CGRectInset(view.bounds, 1.0, 1.0);
	layer.frame = view.bounds;
	layer.path = radius > 0.0
		? [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius].CGPath
		: [UIBezierPath bezierPathWithRect:rect].CGPath;
}

#pragma mark - Poll / quiz / slider logic

static NSInteger sciBestTallyIndex(NSArray *tallies) {
	NSInteger bestIndex = -1;
	NSInteger bestCount = 0;

	for (NSUInteger i = 0; i < tallies.count; i++) {
		NSInteger count = [(NSNumber *)sciSend0(tallies[i], @"totalCount") integerValue];
		if (count > bestCount) {
			bestIndex = (NSInteger)i;
			bestCount = count;
		}
	}

	return bestIndex;
}

static void sciApplyPoll(UIView *pollView, NSArray *options) {
	BOOL showCounts = sciShowCounts(pollView);
	BOOL showWinner = sciShowAnswer(pollView);

	if ((!showCounts && !showWinner) || sciIsEditingSticker(pollView)) {
		for (UIView *option in options) {
			sciRemoveAssociatedView(option, &kSciCountBadgeKey);
			sciRemoveAssociatedView(option, &kSciQuizHighlightKey);
		}
		return;
	}

	id viewModel = sciSend0(pollView, @"igapiStickerModel") ?: sciSend0(pollView, @"exportModel");
	id model = sciAuthoritativeSticker(pollView, @"storyPolls", @"pollSticker", viewModel, @"pollId") ?: viewModel;
	NSArray *tallies = [sciSend0(model, @"tallies") isKindOfClass:NSArray.class] ? sciSend0(model, @"tallies") : nil;

	if (!tallies.count) {
		for (UIView *option in options) {
			sciRemoveAssociatedView(option, &kSciCountBadgeKey);
			sciRemoveAssociatedView(option, &kSciQuizHighlightKey);
		}
		return;
	}

	double total = [(NSNumber *)sciSend0(model, @"totalVotes") doubleValue];
	NSNumber *correct = sciSend0(model, @"correctAnswer");
	NSInteger winner = correct ? correct.integerValue : sciBestTallyIndex(tallies);

	for (NSUInteger i = 0; i < options.count; i++) {
		UIView *option = options[i];

		if (![option isKindOfClass:UIView.class] || i >= tallies.count) {
			sciRemoveAssociatedView(option, &kSciCountBadgeKey);
			sciRemoveAssociatedView(option, &kSciQuizHighlightKey);
			continue;
		}

		if (showCounts) {
			NSInteger count = [(NSNumber *)sciSend0(tallies[i], @"totalCount") integerValue];
			sciSetCountBadge(option, count, total);
		} else {
			sciRemoveAssociatedView(option, &kSciCountBadgeKey);
		}

		if (showWinner && winner >= 0 && (NSInteger)i == winner) {
			sciSetHighlight(option, 0.0);
		} else {
			sciRemoveAssociatedView(option, &kSciQuizHighlightKey);
		}
	}
}

static void sciApplySlider(UIView *sliderView) {
	if (!sciShowCounts(sliderView) || sciIsEditingSticker(sliderView)) {
		sciRemoveAssociatedView(sliderView, &kSciSliderBadgeKey);
		return;
	}

	id model = sciSend0(sliderView, @"igapiStickerModel") ?: sciSend0(sliderView, @"exportModel");

	NSUInteger count = [(NSNumber *)sciSend0(model, @"sliderVoteCount") unsignedIntegerValue];
	double average = [(NSNumber *)sciSend0(model, @"sliderVoteAverage") doubleValue];

	if (count == 0 && average == 0.0) {
		count = sciNSUIntegerIvar(sliderView, "_voteCount");

		id averageVote = sciObjectIvar(sliderView, "_averageVote");
		if ([averageVote respondsToSelector:@selector(doubleValue)]) {
			average = [averageVote doubleValue];
		}
	}

	if (count == 0 && average == 0.0) {
		sciRemoveAssociatedView(sliderView, &kSciSliderBadgeKey);
		return;
	}

	sciSetSliderBadge(sliderView, count, average);
}

static void sciApplyQuiz(UIView *quizView) {
	UICollectionView *collectionView = sciCollectionIvar(quizView, "_optionsCollectionView");

	if (collectionView) {
		[collectionView setNeedsLayout];
		[collectionView layoutIfNeeded];
		collectionView.userInteractionEnabled = YES;
	}
	quizView.userInteractionEnabled = YES;

	NSArray *cells = collectionView.visibleCells ?: @[];

	if (!sciShowAnswer(quizView) || sciIsEditingSticker(quizView)) {
		for (UIView *cell in cells) {
			sciRemoveAssociatedView(cell, &kSciQuizHighlightKey);
		}
		return;
	}

	id viewModel = sciSend0(quizView, @"igapiStickerModel") ?: sciSend0(quizView, @"exportModel");
	id model = sciAuthoritativeSticker(quizView, @"storyQuizs", @"quizSticker", viewModel, @"quizId") ?: viewModel;

	NSNumber *correct = sciSend0(model, @"correctAnswer");
	NSInteger winner;
	if (correct) {
		winner = correct.integerValue;
	} else if (sciIvar([quizView class], "_correctOption")) {
		// ivar exists → trust its value (including 0); ivar missing → no fallback signal
		winner = (NSInteger)sciNSUIntegerIvar(quizView, "_correctOption");
	} else {
		winner = -1;
	}

	if (winner < 0) return;

	for (UICollectionViewCell *cell in cells) {
		if (![cell isKindOfClass:UICollectionViewCell.class]) continue;

		NSIndexPath *indexPath = [collectionView indexPathForCell:cell];
		if (!indexPath) continue;

		if ((NSInteger)indexPath.row == winner) {
			sciSetHighlight(cell, 18.0);
		} else {
			sciRemoveAssociatedView(cell, &kSciQuizHighlightKey);
		}
	}
}

#pragma mark - Tray injection helpers

static id sciStickerSection(id neighbor) {
	return sciSend0(neighbor, @"stickerSection");
}

static void sciSetStickerSection(id model, id section) {
	if (model && section && [model respondsToSelector:@selector(setStickerSection:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(model, @selector(setStickerSection:), section);
	}
}

static id sciMakeTrayModel(NSString *className, id neighbor) {
	Class cls = NSClassFromString(className);
	if (!cls) return nil;

	id model = [[cls alloc] init];
	if (!model) return nil;

	sciSetStickerSection(model, sciStickerSection(neighbor));

	if ([model respondsToSelector:@selector(setPrompts:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(model, @selector(setPrompts:), @[]);
	}

	return model;
}

static BOOL sciArrayHasClassName(NSArray *items, NSString *className) {
	for (id item in items) {
		if ([NSStringFromClass([item class]) isEqualToString:className]) return YES;
	}
	return NO;
}

static BOOL sciArrayHasQuiz(NSArray *items) {
	for (id item in items) {
		if ([NSStringFromClass([item class]) rangeOfString:@"Quiz" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

static NSUInteger sciInteractiveInsertIndex(NSArray *items, id *neighborOut) {
	NSArray *preferred = @[
		@"IGQuizStickerTrayModel",
		@"IGPollStickerV2TrayModel",
		@"IGPollStickerTrayModel",
		@"IGQuestionAnswerStickerModel"
	];

	for (NSString *className in preferred) {
		for (NSUInteger i = 0; i < items.count; i++) {
			if ([NSStringFromClass([items[i] class]) isEqualToString:className]) {
				if (neighborOut) *neighborOut = items[i];
				return i + 1;
			}
		}
	}

	if (neighborOut) *neighborOut = items.firstObject;
	return items.count;
}

#pragma mark - Hooks

%group StickerReveal

%hook IGStoryViewerViewController

- (void)viewDidLayoutSubviews {
	%orig;
	sciForceStickerRelayout(((UIViewController *)self).view);
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	sciForceStickerRelayout(((UIViewController *)self).view);
}

%end

%hook IGSundialFeedViewController

- (void)viewDidLayoutSubviews {
	%orig;
	sciForceStickerRelayout(((UIViewController *)self).view);
}

%end

%hook IGPollStickerV2View

%new
- (void)sci_applyStickerReveal {
	sciApplyPoll((UIView *)self, sciArrayIvar(self, "_optionViews") ?: @[]);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sci_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) sciRetryApply((UIView *)self, @selector(sci_applyStickerReveal));
}

%end

%hook IGPollStickerView

%new
- (void)sci_applyStickerReveal {
	UIView *voteView = sciObjectIvar(self, "_voteView");
	NSArray *options = sciArrayIvar(voteView, "_optionViews")
					?: sciArrayIvar(voteView, "_voteOptionViews")
					?: sciArrayIvar(voteView, "_options")
					?: sciArrayIvar(self, "_optionViews")
					?: sciArrayIvar(self, "_voteOptionViews")
					?: sciArrayIvar(self, "_options");

	sciApplyPoll((UIView *)self, options ?: @[]);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sci_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) sciRetryApply((UIView *)self, @selector(sci_applyStickerReveal));
}

%end

%hook IGSliderStickerView

%new
- (void)sci_applyStickerReveal {
	sciApplySlider((UIView *)self);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sci_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) sciRetryApply((UIView *)self, @selector(sci_applyStickerReveal));
}

- (void)_sliderValueChanged:(id)arg {
	%orig;
	sciRetryApply((UIView *)self, @selector(sci_applyStickerReveal));
}

%end

%hook IGQuizStickerView

%new
- (void)sci_applyStickerReveal {
	sciApplyQuiz((UIView *)self);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sci_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) sciRetryApply((UIView *)self, @selector(sci_applyStickerReveal));
}

%end

%end

%group StickerComposer

%hook IGStoryStickerDataSourceImpl

- (NSArray *)items {
	NSArray *orig = %orig;
	if (!orig.count || !sciPref(@"force_enable_quiz_sticker")) return orig;

	NSMutableArray *items = nil;

	if (!sciArrayHasQuiz(orig)) {
		id neighbor = nil;
		NSUInteger index = sciInteractiveInsertIndex(orig, &neighbor);
		id quiz = sciMakeTrayModel(@"IGQuizStickerTrayModel", neighbor);

		if (quiz) {
			items = [orig mutableCopy];
			[items insertObject:quiz atIndex:MIN(index, items.count)];
		}
	}

	NSArray *base = items ?: orig;

	if (!sciArrayHasClassName(base, @"IGSecretStickerTrayModel")) {
		id neighbor = nil;
		NSUInteger index = sciInteractiveInsertIndex(base, &neighbor);
		id secret = sciMakeTrayModel(@"IGSecretStickerTrayModel", neighbor);

		if (secret) {
			if (!items) items = [orig mutableCopy];
			[items insertObject:secret atIndex:MIN(index, items.count)];
		}
	}

	return items ?: orig;
}

%end

%end

%group SecretStickerGates

%hook IGGenAIRestyleExperimentHelper

+ (BOOL)isRevealStickerEnabledWithLauncherSet:(id)set {
	return sciPref(@"force_enable_quiz_sticker") ? YES : %orig;
}

+ (BOOL)isRevealStickerConsumptionEnabledWithLauncherSet:(id)set {
	return sciPref(@"force_enable_quiz_sticker") ? YES : %orig;
}

%end

%end

%group SecretBlurBypass

%hook IGStoryFullscreenOverlayView

- (BOOL)isSecretStoryCurrentlyBlurred {
	return sciPref(@"bypass_reveal_sticker") ? NO : %orig;
}

- (void)showSecretStoryBlur:(BOOL)show animated:(BOOL)animated {
	if (show && sciPref(@"bypass_reveal_sticker")) {
		%orig(NO, animated);
		return;
	}
	%orig;
}

%end

%end

%group SecretOverlayBypass

%hook IGSecretStickerOverlayView

- (void)layoutSubviews {
	%orig;

	if (!sciPref(@"bypass_reveal_sticker")) return;

	if ([self respondsToSelector:@selector(setPreviewBlurEnabled:)]) {
		((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setPreviewBlurEnabled:), NO);
	}

	((UIView *)self).hidden = YES;
}

%end

%end

%ctor {
	if (sciRevealAnyEnabled()) {
		%init(StickerReveal);
	}

	if (sciPref(@"force_enable_quiz_sticker")) {
		%init(StickerComposer);
	}

	Class gates = NSClassFromString(@"_TtC25IGMagicModExperimentation30IGGenAIRestyleExperimentHelper");
	if (!gates) gates = NSClassFromString(@"IGGenAIRestyleExperimentHelper");

	if (gates && sciPref(@"force_enable_quiz_sticker")) {
		%init(SecretStickerGates, IGGenAIRestyleExperimentHelper = gates);
	}

	if (sciPref(@"bypass_reveal_sticker")) {
		%init(SecretBlurBypass);

		Class overlay = NSClassFromString(@"_TtC15IGSecretSticker26IGSecretStickerOverlayView");
		if (!overlay) overlay = NSClassFromString(@"IGSecretStickerOverlayView");

		if (overlay) {
			%init(SecretOverlayBypass, IGSecretStickerOverlayView = overlay);
		}
	}
}