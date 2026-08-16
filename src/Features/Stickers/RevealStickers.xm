// Reveal poll/quiz/slider results on story/reel stickers, force the
// legacy Quiz + Reveal stickers back into the composer tray, and bypass
// the Reveal sticker blur on the consumer side.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../StoriesAndMessages/StoryHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern "C" __weak UIViewController *rygActiveStoryViewerVC;

#pragma mark - Prefs

static inline BOOL rygPref(NSString *key) {
	return [RYGUtils getBoolPref:key];
}

static inline BOOL rygRevealAnyEnabled(void) {
	return rygPref(@"stories_show_poll_votes_count") ||
		   rygPref(@"stories_show_quiz_answer") ||
		   rygPref(@"reels_show_poll_votes_count") ||
		   rygPref(@"reels_show_quiz_answer");
}

static inline BOOL rygSecretAnyEnabled(void) {
	return rygPref(@"force_enable_quiz_sticker") ||
		   rygPref(@"bypass_reveal_sticker");
}

#pragma mark - Runtime helpers

static id rygSend0(id obj, NSString *name) {
	if (!obj) return nil;
	SEL sel = NSSelectorFromString(name);
	if (![obj respondsToSelector:sel]) return nil;
	@try {
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id rygSend1(id obj, SEL sel, id arg) {
	if (!obj || ![obj respondsToSelector:sel]) return nil;
	@try {
		return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
	} @catch (__unused id e) {
		return nil;
	}
}

static Ivar rygIvar(Class cls, const char *name) {
	for (Class c = cls; c && c != NSObject.class; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (iv) return iv;
	}
	return nil;
}

static id rygObjectIvar(id obj, const char *name) {
	Ivar iv = obj ? rygIvar([obj class], name) : nil;
	return iv ? object_getIvar(obj, iv) : nil;
}

static BOOL rygBoolIvar(id obj, const char *name) {
	Ivar iv = obj ? rygIvar([obj class], name) : nil;
	if (!iv) return NO;

	BOOL value = NO;
	memcpy(&value, (uint8_t *)(__bridge void *)obj + ivar_getOffset(iv), sizeof(value));
	return value;
}

static NSUInteger rygNSUIntegerIvar(id obj, const char *name) {
	Ivar iv = obj ? rygIvar([obj class], name) : nil;
	if (!iv) return 0;

	NSUInteger value = 0;
	memcpy(&value, (uint8_t *)(__bridge void *)obj + ivar_getOffset(iv), sizeof(value));
	return value;
}

static NSArray *rygArrayIvar(id obj, const char *name) {
	id value = rygObjectIvar(obj, name);
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

static UICollectionView *rygCollectionIvar(id obj, const char *name) {
	id value = rygObjectIvar(obj, name);
	return [value isKindOfClass:UICollectionView.class] ? value : nil;
}

#pragma mark - Context / media lookup

static BOOL rygIsReelsContext(UIResponder *anchor) {
	Class reels = NSClassFromString(@"IGSundialFeedViewController");

	for (UIResponder *r = anchor; r; r = r.nextResponder) {
		if (reels && [r isKindOfClass:reels]) return YES;
		if ([NSStringFromClass([r class]) hasPrefix:@"IGSundial"]) return YES;
	}
	return NO;
}

static BOOL rygShowCounts(UIView *anchor) {
	return rygPref(rygIsReelsContext(anchor) ? @"reels_show_poll_votes_count" : @"stories_show_poll_votes_count");
}

static BOOL rygShowAnswer(UIView *anchor) {
	return rygPref(rygIsReelsContext(anchor) ? @"reels_show_quiz_answer" : @"stories_show_quiz_answer");
}

static IGMedia *rygMediaFromResponderChain(UIResponder *anchor) {
	Class mediaCls = NSClassFromString(@"IGMedia");
	Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
	Class managerCls = NSClassFromString(@"IGStoryStickerManager");
	Class storyVCCls = NSClassFromString(@"IGStoryViewerViewController");
	Class reelsVCCls = NSClassFromString(@"IGSundialFeedViewController");

	for (UIResponder *r = anchor; r; r = r.nextResponder) {
		if (overlayCls && [r isKindOfClass:overlayCls]) {
			id media = rygObjectIvar(r, "_media") ?: rygSend0(r, @"media");
			if ([media isKindOfClass:mediaCls]) return media;

			id manager = rygObjectIvar(r, "_stickerManager") ?: rygSend0(r, @"stickerManager");
			id item = rygSend0(manager, @"currentStoryItem");
			IGMedia *nested = rygExtractMediaFromItem(item);
			if (nested) return nested;
		}

		if (managerCls && [r isKindOfClass:managerCls]) {
			IGMedia *media = rygExtractMediaFromItem(rygSend0(r, @"currentStoryItem"));
			if (media) return media;
		}

		if (storyVCCls && [r isKindOfClass:storyVCCls]) {
			id item = rygSend0(r, @"currentStoryItem");
			IGMedia *media = [item isKindOfClass:mediaCls] ? item : rygExtractMediaFromItem(item);
			if (media) return media;

			id vm = rygSend0(r, @"currentViewModel");
			item = rygSend1(r, @selector(currentStoryItemForViewModel:), vm);
			media = [item isKindOfClass:mediaCls] ? item : rygExtractMediaFromItem(item);
			if (media) return media;
		}

		if (reelsVCCls && [r isKindOfClass:reelsVCCls]) {
			id media = rygSend0(r, @"currentPlaybackMedia");
			if ([media isKindOfClass:mediaCls]) return media;
		}
	}

	if (rygActiveStoryViewerVC) {
		id item = rygSend0(rygActiveStoryViewerVC, @"currentStoryItem");
		IGMedia *media = [item isKindOfClass:mediaCls] ? item : rygExtractMediaFromItem(item);
		if (media) return media;

		id vm = rygSend0(rygActiveStoryViewerVC, @"currentViewModel");
		item = rygSend1(rygActiveStoryViewerVC, @selector(currentStoryItemForViewModel:), vm);
		media = [item isKindOfClass:mediaCls] ? item : rygExtractMediaFromItem(item);
		if (media) return media;
	}

	return nil;
}

static id rygAuthoritativeSticker(UIView *anchor, NSString *mediaArraySel, NSString *entryStickerSel, id viewModel, NSString *idSel) {
	IGMedia *media = rygMediaFromResponderChain(anchor);
	id raw = rygSend0(media, mediaArraySel);
	NSArray *array = [raw isKindOfClass:NSArray.class] ? (NSArray *)raw : nil;
	if (!array.count) return nil;

	NSString *viewId = [[rygSend0(viewModel, idSel) description] copy];

	for (id entry in array) {
		id sticker = rygSend0(entry, entryStickerSel);
		if (!sticker) continue;

		if (viewId.length) {
			NSString *stickerId = [[rygSend0(sticker, idSel) description] copy];
			if ([stickerId isEqualToString:viewId]) return sticker;
		}
	}

	return rygSend0(array.firstObject, entryStickerSel) ?: array.firstObject;
}

#pragma mark - Editing / relayout

static BOOL rygIsEditingSticker(UIView *view) {
	if (rygBoolIvar(view, "_isEditing") ||
		rygBoolIvar(view, "_editing") ||
		rygBoolIvar(view, "_editingQuestion")) {
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

static void rygForceStickerRelayout(UIView *root) {
	if (!root || !rygRevealAnyEnabled()) return;

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

static void rygRetryApply(UIView *view, SEL action) {
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

static char kRygCountBadgeKey;
static char kRygSliderBadgeKey;
static char kRygQuizHighlightKey;
static char kRygQuizShapeKey;

// Capture-aware badge — label + pill inside an RYGChromeCanvas so Hide UI on
// Capture redacts it. Frame driven externally.
@interface RYGStickerBadge : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong, readonly) UILabel *label;
@property (nonatomic, strong, readonly) UIView *bg;
@end

@implementation RYGStickerBadge

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		RYGChromeCanvas *canvas = [RYGChromeCanvas new];
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

static RYGStickerBadge *rygBadge(void) {
	RYGStickerBadge *badge = [[RYGStickerBadge alloc] initWithFrame:CGRectZero];
	badge.label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
	badge.label.textColor = UIColor.whiteColor;
	badge.bg.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.95 alpha:0.92];
	badge.bg.layer.cornerRadius = 10.0;
	badge.userInteractionEnabled = NO;
	return badge;
}

static RYGStickerBadge *rygBadgeForView(UIView *view, const void *key) {
	RYGStickerBadge *badge = objc_getAssociatedObject(view, key);
	if (!badge) {
		badge = rygBadge();
		[view addSubview:badge];
		objc_setAssociatedObject(view, key, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return badge;
}

static void rygRemoveAssociatedView(UIView *view, const void *key) {
	UIView *old = objc_getAssociatedObject(view, key);
	if (old) {
		[old removeFromSuperview];
		objc_setAssociatedObject(view, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

static void rygSetCountBadge(UIView *view, NSInteger count, double total) {
	RYGStickerBadge *badge = rygBadgeForView(view, &kRygCountBadgeKey);

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

static void rygSetSliderBadge(UIView *view, NSUInteger count, double average) {
	RYGStickerBadge *badge = rygBadgeForView(view, &kRygSliderBadgeKey);

	badge.text = [NSString stringWithFormat:RYGLocalized(@"  %lu votes · avg %.0f%%  "),
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

static void rygSetHighlight(UIView *view, CGFloat radius) {
	// Shape lives in a chrome-canvas overlay so Hide UI on Capture redacts it.
	RYGChromeCanvas *canvas = objc_getAssociatedObject(view, &kRygQuizHighlightKey);
	CAShapeLayer *layer;

	if (!canvas) {
		canvas = [RYGChromeCanvas new];
		canvas.userInteractionEnabled = NO;
		canvas.translatesAutoresizingMaskIntoConstraints = YES;

		layer = [CAShapeLayer layer];
		UIColor *green = [UIColor colorWithRed:0.24 green:0.76 blue:0.38 alpha:1.0];
		layer.fillColor = [green colorWithAlphaComponent:0.35].CGColor;
		layer.strokeColor = green.CGColor;
		layer.lineWidth = 2.0;

		[canvas.contentContainer.layer addSublayer:layer];
		[view addSubview:canvas];

		objc_setAssociatedObject(view, &kRygQuizHighlightKey, canvas, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(canvas, &kRygQuizShapeKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	} else {
		layer = objc_getAssociatedObject(canvas, &kRygQuizShapeKey);
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

static NSInteger rygBestTallyIndex(NSArray *tallies) {
	NSInteger bestIndex = -1;
	NSInteger bestCount = 0;

	for (NSUInteger i = 0; i < tallies.count; i++) {
		NSInteger count = [(NSNumber *)rygSend0(tallies[i], @"totalCount") integerValue];
		if (count > bestCount) {
			bestIndex = (NSInteger)i;
			bestCount = count;
		}
	}

	return bestIndex;
}

static void rygApplyPoll(UIView *pollView, NSArray *options) {
	BOOL showCounts = rygShowCounts(pollView);
	BOOL showWinner = rygShowAnswer(pollView);

	if ((!showCounts && !showWinner) || rygIsEditingSticker(pollView)) {
		for (UIView *option in options) {
			rygRemoveAssociatedView(option, &kRygCountBadgeKey);
			rygRemoveAssociatedView(option, &kRygQuizHighlightKey);
		}
		return;
	}

	id viewModel = rygSend0(pollView, @"igapiStickerModel") ?: rygSend0(pollView, @"exportModel");
	id model = rygAuthoritativeSticker(pollView, @"storyPolls", @"pollSticker", viewModel, @"pollId") ?: viewModel;
	NSArray *tallies = [rygSend0(model, @"tallies") isKindOfClass:NSArray.class] ? rygSend0(model, @"tallies") : nil;

	if (!tallies.count) {
		for (UIView *option in options) {
			rygRemoveAssociatedView(option, &kRygCountBadgeKey);
			rygRemoveAssociatedView(option, &kRygQuizHighlightKey);
		}
		return;
	}

	double total = [(NSNumber *)rygSend0(model, @"totalVotes") doubleValue];
	NSNumber *correct = rygSend0(model, @"correctAnswer");
	NSInteger winner = correct ? correct.integerValue : rygBestTallyIndex(tallies);

	for (NSUInteger i = 0; i < options.count; i++) {
		UIView *option = options[i];

		if (![option isKindOfClass:UIView.class] || i >= tallies.count) {
			rygRemoveAssociatedView(option, &kRygCountBadgeKey);
			rygRemoveAssociatedView(option, &kRygQuizHighlightKey);
			continue;
		}

		if (showCounts) {
			NSInteger count = [(NSNumber *)rygSend0(tallies[i], @"totalCount") integerValue];
			rygSetCountBadge(option, count, total);
		} else {
			rygRemoveAssociatedView(option, &kRygCountBadgeKey);
		}

		if (showWinner && winner >= 0 && (NSInteger)i == winner) {
			rygSetHighlight(option, 0.0);
		} else {
			rygRemoveAssociatedView(option, &kRygQuizHighlightKey);
		}
	}
}

static void rygApplySlider(UIView *sliderView) {
	if (!rygShowCounts(sliderView) || rygIsEditingSticker(sliderView)) {
		rygRemoveAssociatedView(sliderView, &kRygSliderBadgeKey);
		return;
	}

	id model = rygSend0(sliderView, @"igapiStickerModel") ?: rygSend0(sliderView, @"exportModel");

	NSUInteger count = [(NSNumber *)rygSend0(model, @"sliderVoteCount") unsignedIntegerValue];
	double average = [(NSNumber *)rygSend0(model, @"sliderVoteAverage") doubleValue];

	if (count == 0 && average == 0.0) {
		count = rygNSUIntegerIvar(sliderView, "_voteCount");

		id averageVote = rygObjectIvar(sliderView, "_averageVote");
		if ([averageVote respondsToSelector:@selector(doubleValue)]) {
			average = [averageVote doubleValue];
		}
	}

	if (count == 0 && average == 0.0) {
		rygRemoveAssociatedView(sliderView, &kRygSliderBadgeKey);
		return;
	}

	rygSetSliderBadge(sliderView, count, average);
}

static void rygApplyQuiz(UIView *quizView) {
	UICollectionView *collectionView = rygCollectionIvar(quizView, "_optionsCollectionView");

	if (collectionView) {
		[collectionView setNeedsLayout];
		[collectionView layoutIfNeeded];
		collectionView.userInteractionEnabled = YES;
	}
	quizView.userInteractionEnabled = YES;

	NSArray *cells = collectionView.visibleCells ?: @[];

	if (!rygShowAnswer(quizView) || rygIsEditingSticker(quizView)) {
		for (UIView *cell in cells) {
			rygRemoveAssociatedView(cell, &kRygQuizHighlightKey);
		}
		return;
	}

	id viewModel = rygSend0(quizView, @"igapiStickerModel") ?: rygSend0(quizView, @"exportModel");
	id model = rygAuthoritativeSticker(quizView, @"storyQuizs", @"quizSticker", viewModel, @"quizId") ?: viewModel;

	NSNumber *correct = rygSend0(model, @"correctAnswer");
	NSInteger winner;
	if (correct) {
		winner = correct.integerValue;
	} else if (rygIvar([quizView class], "_correctOption")) {
		// ivar exists → trust its value (including 0); ivar missing → no fallback signal
		winner = (NSInteger)rygNSUIntegerIvar(quizView, "_correctOption");
	} else {
		winner = -1;
	}

	if (winner < 0) return;

	for (UICollectionViewCell *cell in cells) {
		if (![cell isKindOfClass:UICollectionViewCell.class]) continue;

		NSIndexPath *indexPath = [collectionView indexPathForCell:cell];
		if (!indexPath) continue;

		if ((NSInteger)indexPath.row == winner) {
			rygSetHighlight(cell, 18.0);
		} else {
			rygRemoveAssociatedView(cell, &kRygQuizHighlightKey);
		}
	}
}

#pragma mark - Tray injection helpers

static id rygStickerSection(id neighbor) {
	return rygSend0(neighbor, @"stickerSection");
}

static void rygSetStickerSection(id model, id section) {
	if (model && section && [model respondsToSelector:@selector(setStickerSection:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(model, @selector(setStickerSection:), section);
	}
}

static id rygMakeTrayModel(NSString *className, id neighbor) {
	Class cls = NSClassFromString(className);
	if (!cls) return nil;

	id model = [[cls alloc] init];
	if (!model) return nil;

	rygSetStickerSection(model, rygStickerSection(neighbor));

	if ([model respondsToSelector:@selector(setPrompts:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(model, @selector(setPrompts:), @[]);
	}

	return model;
}

static BOOL rygArrayHasClassName(NSArray *items, NSString *className) {
	for (id item in items) {
		if ([NSStringFromClass([item class]) isEqualToString:className]) return YES;
	}
	return NO;
}

static BOOL rygArrayHasQuiz(NSArray *items) {
	for (id item in items) {
		if ([NSStringFromClass([item class]) rangeOfString:@"Quiz" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			return YES;
		}
	}
	return NO;
}

static NSUInteger rygInteractiveInsertIndex(NSArray *items, id *neighborOut) {
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
	rygForceStickerRelayout(((UIViewController *)self).view);
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygForceStickerRelayout(((UIViewController *)self).view);
}

%end

%hook IGSundialFeedViewController

- (void)viewDidLayoutSubviews {
	%orig;
	rygForceStickerRelayout(((UIViewController *)self).view);
}

%end

%hook IGPollStickerV2View

%new
- (void)ryg_applyStickerReveal {
	rygApplyPoll((UIView *)self, rygArrayIvar(self, "_optionViews") ?: @[]);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(ryg_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) rygRetryApply((UIView *)self, @selector(ryg_applyStickerReveal));
}

%end

%hook IGPollStickerView

%new
- (void)ryg_applyStickerReveal {
	UIView *voteView = rygObjectIvar(self, "_voteView");
	NSArray *options = rygArrayIvar(voteView, "_optionViews")
					?: rygArrayIvar(voteView, "_voteOptionViews")
					?: rygArrayIvar(voteView, "_options")
					?: rygArrayIvar(self, "_optionViews")
					?: rygArrayIvar(self, "_voteOptionViews")
					?: rygArrayIvar(self, "_options");

	rygApplyPoll((UIView *)self, options ?: @[]);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(ryg_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) rygRetryApply((UIView *)self, @selector(ryg_applyStickerReveal));
}

%end

%hook IGSliderStickerView

%new
- (void)ryg_applyStickerReveal {
	rygApplySlider((UIView *)self);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(ryg_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) rygRetryApply((UIView *)self, @selector(ryg_applyStickerReveal));
}

- (void)_sliderValueChanged:(id)arg {
	%orig;
	rygRetryApply((UIView *)self, @selector(ryg_applyStickerReveal));
}

%end

%hook IGQuizStickerView

%new
- (void)ryg_applyStickerReveal {
	rygApplyQuiz((UIView *)self);
}

- (void)layoutSubviews {
	%orig;
	((void (*)(id, SEL))objc_msgSend)(self, @selector(ryg_applyStickerReveal));
}

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) rygRetryApply((UIView *)self, @selector(ryg_applyStickerReveal));
}

%end

%end

%group StickerComposer

%hook IGStoryStickerDataSourceImpl

- (NSArray *)items {
	NSArray *orig = %orig;
	if (!orig.count || !rygPref(@"force_enable_quiz_sticker")) return orig;

	NSMutableArray *items = nil;

	if (!rygArrayHasQuiz(orig)) {
		id neighbor = nil;
		NSUInteger index = rygInteractiveInsertIndex(orig, &neighbor);
		id quiz = rygMakeTrayModel(@"IGQuizStickerTrayModel", neighbor);

		if (quiz) {
			items = [orig mutableCopy];
			[items insertObject:quiz atIndex:MIN(index, items.count)];
		}
	}

	NSArray *base = items ?: orig;

	if (!rygArrayHasClassName(base, @"IGSecretStickerTrayModel")) {
		id neighbor = nil;
		NSUInteger index = rygInteractiveInsertIndex(base, &neighbor);
		id secret = rygMakeTrayModel(@"IGSecretStickerTrayModel", neighbor);

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
	return rygPref(@"force_enable_quiz_sticker") ? YES : %orig;
}

+ (BOOL)isRevealStickerConsumptionEnabledWithLauncherSet:(id)set {
	return rygPref(@"force_enable_quiz_sticker") ? YES : %orig;
}

%end

%end

%group SecretBlurBypass

%hook IGStoryFullscreenOverlayView

- (BOOL)isSecretStoryCurrentlyBlurred {
	return rygPref(@"bypass_reveal_sticker") ? NO : %orig;
}

- (void)showSecretStoryBlur:(BOOL)show animated:(BOOL)animated {
	if (show && rygPref(@"bypass_reveal_sticker")) {
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
	RYGProbeOnce(@"hook.secretsticker.overlay", @"IGSecretStickerOverlayView fired");
	%orig;

	if (!rygPref(@"bypass_reveal_sticker")) return;

	if ([self respondsToSelector:@selector(setPreviewBlurEnabled:)]) {
		((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setPreviewBlurEnabled:), NO);
	}

	((UIView *)self).hidden = YES;
}

%end

%end

%ctor {
	if (rygRevealAnyEnabled()) {
		%init(StickerReveal);
	}

	if (rygPref(@"force_enable_quiz_sticker")) {
		%init(StickerComposer);
	}

	Class gates = NSClassFromString(@"_TtC25IGMagicModExperimentation30IGGenAIRestyleExperimentHelper");
	if (!gates) gates = NSClassFromString(@"IGGenAIRestyleExperimentHelper");

	if (gates && rygPref(@"force_enable_quiz_sticker")) {
		%init(SecretStickerGates, IGGenAIRestyleExperimentHelper = gates);
	}

	if (rygPref(@"bypass_reveal_sticker")) {
		%init(SecretBlurBypass);

		Class overlay = NSClassFromString(@"_TtC15IGSecretSticker26IGSecretStickerOverlayView");
		if (!overlay) overlay = NSClassFromString(@"IGSecretStickerOverlayView");

		if (overlay) {
			%init(SecretOverlayBypass, IGSecretStickerOverlayView = overlay);
		}
	}
}