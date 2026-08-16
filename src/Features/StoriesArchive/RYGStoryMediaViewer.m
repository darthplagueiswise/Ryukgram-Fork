#import "RYGStoryMediaViewer.h"
#import "RYGStoryMediaCell.h"
#import "RYGStoryViewersSheet.h"
#import "RYGStoriesArchiveStore.h"
#import "RYGStoriesArchiveManager.h"
#import "RYGArchivedStory.h"
#import "RYGArchivedStoryViewer.h"
#import "../../RYGImageCache.h"
#import "../../UI/RYGLiquidGlass.h"

extern NSString *const RYGStoriesArchiveDidChangeNotification;

static NSString *const kMediaCell = @"RYGStoryMediaCell";
static const NSInteger kAvatarCount = 3;

@interface RYGStoryMediaViewer () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSArray<RYGArchivedStory *> *stories;
@property (nonatomic, strong) RYGStoriesArchiveStore *store;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, strong) UIView *mediaContainer;
@property (nonatomic, strong) UICollectionView *collectionView;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *counterLabel;

@property (nonatomic, strong) UIControl *viewerBar;
@property (nonatomic, strong) UIView *avatarStack;
@property (nonatomic, strong) NSLayoutConstraint *avatarStackWidth;
@property (nonatomic, strong) NSArray<UIImageView *> *avatarViews;
@property (nonatomic, strong) UILabel *viewerLabel;
@property (nonatomic, strong) UIImageView *chevron;

@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, strong) NSMutableSet<NSString *> *refreshedMediaIDs;
@end

@implementation RYGStoryMediaViewer

+ (void)presentStories:(NSArray<RYGArchivedStory *> *)stories
                 store:(RYGStoriesArchiveStore *)store
            startIndex:(NSInteger)startIndex
                  from:(UIViewController *)presenter {
	if (!stories.count) return;
	RYGStoryMediaViewer *vc = [RYGStoryMediaViewer new];
	vc.stories = stories;
	vc.store = store;
	vc.index = MAX(0, MIN(startIndex, (NSInteger)stories.count - 1));
	vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
	vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
	[(presenter ?: [self topPresenter]) presentViewController:vc animated:YES completion:nil];
}

+ (UIViewController *)topPresenter {
	UIViewController *top = nil;
	for (UIWindow *w in UIApplication.sharedApplication.windows) if (w.isKeyWindow) { top = w.rootViewController; break; }
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;
	[self setupChrome];
	[self setupMedia];
	[self setupGestures];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateViewerBar)
	                                           name:RYGStoriesArchiveDidChangeNotification object:nil];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.index inSection:0]
									atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
		[self pageChanged];
	});
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)setupMedia {
	_mediaContainer = [UIView new];
	_mediaContainer.translatesAutoresizingMaskIntoConstraints = NO;
	_mediaContainer.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
	_mediaContainer.layer.cornerRadius = 16;
	_mediaContainer.layer.cornerCurve = kCACornerCurveContinuous;
	_mediaContainer.clipsToBounds = YES;
	[self.view addSubview:_mediaContainer];

	UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
	layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
	layout.minimumLineSpacing = 0;
	layout.minimumInteritemSpacing = 0;

	_collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	_collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	_collectionView.backgroundColor = UIColor.clearColor;
	_collectionView.pagingEnabled = YES;
	_collectionView.showsHorizontalScrollIndicator = NO;
	_collectionView.dataSource = self;
	_collectionView.delegate = self;
	_collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	[_collectionView registerClass:RYGStoryMediaCell.class forCellWithReuseIdentifier:kMediaCell];
	[_mediaContainer addSubview:_collectionView];

	[NSLayoutConstraint activateConstraints:@[
		[_mediaContainer.topAnchor constraintEqualToAnchor:_topBar.bottomAnchor constant:4],
		[_mediaContainer.bottomAnchor constraintEqualToAnchor:_viewerBar.topAnchor constant:-10],
		[_mediaContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
		[_mediaContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
		[_collectionView.topAnchor constraintEqualToAnchor:_mediaContainer.topAnchor],
		[_collectionView.bottomAnchor constraintEqualToAnchor:_mediaContainer.bottomAnchor],
		[_collectionView.leadingAnchor constraintEqualToAnchor:_mediaContainer.leadingAnchor],
		[_collectionView.trailingAnchor constraintEqualToAnchor:_mediaContainer.trailingAnchor],
	]];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	// Keep the current page filling the resized container without animating.
	[self.collectionView.collectionViewLayout invalidateLayout];
	if (self.collectionView.bounds.size.width > 0) {
		CGPoint off = CGPointMake(self.index * self.collectionView.bounds.size.width, 0);
		if (fabs(self.collectionView.contentOffset.x - off.x) > 0.5) self.collectionView.contentOffset = off;
	}
}

- (void)setupChrome {
	_topBar = [UIView new];
	_topBar.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	[close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
	close.tintColor = UIColor.whiteColor;
	close.translatesAutoresizingMaskIntoConstraints = NO;
	[close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

	_dateLabel = [self chromeLabel:13 weight:UIFontWeightSemibold alpha:1.0];
	_counterLabel = [self chromeLabel:13 weight:UIFontWeightSemibold alpha:0.7];

	[_topBar addSubview:close];
	[_topBar addSubview:_dateLabel];
	[_topBar addSubview:_counterLabel];
	[self.view addSubview:_topBar];

	[self setupViewerBar];

	[NSLayoutConstraint activateConstraints:@[
		[_topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[_topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_topBar.heightAnchor constraintEqualToConstant:44],
		[close.leadingAnchor constraintEqualToAnchor:_topBar.leadingAnchor constant:16],
		[close.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
		[_dateLabel.leadingAnchor constraintEqualToAnchor:close.trailingAnchor constant:14],
		[_dateLabel.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
		[_counterLabel.trailingAnchor constraintEqualToAnchor:_topBar.trailingAnchor constant:-16],
		[_counterLabel.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
	]];
}

- (UILabel *)chromeLabel:(CGFloat)size weight:(UIFontWeight)weight alpha:(CGFloat)alpha {
	UILabel *l = [UILabel new];
	l.font = [UIFont systemFontOfSize:size weight:weight];
	l.textColor = [UIColor.whiteColor colorWithAlphaComponent:alpha];
	l.translatesAutoresizingMaskIntoConstraints = NO;
	l.layer.shadowColor = UIColor.blackColor.CGColor;
	l.layer.shadowOpacity = 0.4;
	l.layer.shadowRadius = 3;
	l.layer.shadowOffset = CGSizeZero;
	return l;
}

- (void)setupViewerBar {
	_viewerBar = [UIControl new];
	_viewerBar.translatesAutoresizingMaskIntoConstraints = NO;
	[_viewerBar addTarget:self action:@selector(openViewers) forControlEvents:UIControlEventTouchUpInside];

	UIView *avatarStack = [UIView new];
	avatarStack.translatesAutoresizingMaskIntoConstraints = NO;
	self.avatarStack = avatarStack;
	NSMutableArray *avatars = [NSMutableArray array];
	for (NSInteger i = kAvatarCount - 1; i >= 0; i--) {
		UIImageView *iv = [UIImageView new];
		iv.translatesAutoresizingMaskIntoConstraints = NO;
		iv.contentMode = UIViewContentModeScaleAspectFill;
		iv.clipsToBounds = YES;
		iv.layer.cornerRadius = 13;
		iv.layer.borderWidth = 1.5;
		iv.layer.borderColor = UIColor.blackColor.CGColor;
		iv.backgroundColor = UIColor.darkGrayColor;
		iv.hidden = YES;
		[avatarStack addSubview:iv];
		[NSLayoutConstraint activateConstraints:@[
			[iv.widthAnchor constraintEqualToConstant:26],
			[iv.heightAnchor constraintEqualToConstant:26],
			[iv.centerYAnchor constraintEqualToAnchor:avatarStack.centerYAnchor],
			[iv.leadingAnchor constraintEqualToAnchor:avatarStack.leadingAnchor constant:i * 16],
		]];
		[avatars insertObject:iv atIndex:0];
	}
	_avatarViews = avatars;

	UIVisualEffectView *blur = RYGLiquidGlassView(YES, YES, [UIColor colorWithWhite:0.0 alpha:0.18]);
	blur.translatesAutoresizingMaskIntoConstraints = NO;
	blur.userInteractionEnabled = NO;
	blur.layer.cornerRadius = 19;
	blur.layer.cornerCurve = kCACornerCurveContinuous;
	blur.clipsToBounds = YES;
	[_viewerBar addSubview:blur];
	[NSLayoutConstraint activateConstraints:@[
		[blur.leadingAnchor constraintEqualToAnchor:_viewerBar.leadingAnchor],
		[blur.trailingAnchor constraintEqualToAnchor:_viewerBar.trailingAnchor],
		[blur.topAnchor constraintEqualToAnchor:_viewerBar.topAnchor],
		[blur.bottomAnchor constraintEqualToAnchor:_viewerBar.bottomAnchor],
	]];
	_viewerBar.layer.cornerRadius = 19;
	_viewerBar.layer.cornerCurve = kCACornerCurveContinuous;
	_viewerBar.layer.borderWidth = 0.5;
	_viewerBar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;

	_viewerLabel = [self chromeLabel:14 weight:UIFontWeightBold alpha:1.0];
	_chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.compact.up"]];
	_chevron.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.75];
	_chevron.contentMode = UIViewContentModeScaleAspectFit;
	_chevron.translatesAutoresizingMaskIntoConstraints = NO;
	[_chevron.widthAnchor constraintEqualToConstant:18].active = YES;
	[_chevron.heightAnchor constraintEqualToConstant:10].active = YES;

	[_viewerBar addSubview:avatarStack];
	[_viewerBar addSubview:_viewerLabel];
	[_viewerBar addSubview:_chevron];
	[self.view addSubview:_viewerBar];

	[NSLayoutConstraint activateConstraints:@[
		[_viewerBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
		[_viewerBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-14],
		[_viewerBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
		[_viewerBar.heightAnchor constraintEqualToConstant:38],

		[avatarStack.leadingAnchor constraintEqualToAnchor:_viewerBar.leadingAnchor constant:6],
		[avatarStack.centerYAnchor constraintEqualToAnchor:_viewerBar.centerYAnchor],
		[avatarStack.heightAnchor constraintEqualToConstant:26],
		(self.avatarStackWidth = [avatarStack.widthAnchor constraintEqualToConstant:26 + (kAvatarCount - 1) * 16]),

		[_viewerLabel.leadingAnchor constraintEqualToAnchor:avatarStack.trailingAnchor constant:8],
		[_viewerLabel.centerYAnchor constraintEqualToAnchor:_viewerBar.centerYAnchor],
		[_chevron.leadingAnchor constraintEqualToAnchor:_viewerLabel.trailingAnchor constant:7],
		[_chevron.trailingAnchor constraintEqualToAnchor:_viewerBar.trailingAnchor constant:-13],
		[_chevron.centerYAnchor constraintEqualToAnchor:_viewerBar.centerYAnchor],
	]];
}

- (void)setupGestures {
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
	pan.delegate = self;
	[self.view addGestureRecognizer:pan];

	UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(openViewers)];
	swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
	[self.view addGestureRecognizer:swipeUp];
}

#pragma mark - Current story / chrome

- (RYGArchivedStory *)currentStory {
	return self.index < self.stories.count ? self.stories[self.index] : nil;
}

- (void)pageChanged {
	RYGArchivedStory *s = [self currentStory];
	if (!s) return;

	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fmt = [NSDateFormatter new]; fmt.dateFormat = @"MMM d, yyyy · HH:mm"; });
	self.dateLabel.text = s.takenAt ? [fmt stringFromDate:s.takenAt] : @"";
	self.counterLabel.text = [NSString stringWithFormat:@"%ld / %lu", (long)self.index + 1, (unsigned long)self.stories.count];

	for (RYGStoryMediaCell *cell in self.collectionView.visibleCells) {
		NSIndexPath *ip = [self.collectionView indexPathForCell:cell];
		[cell setActive:ip.item == self.index];
	}
	[self updateViewerBar];
	// Refetch a story's viewers once when you land on it, not on every re-swipe.
	if (!self.refreshedMediaIDs) self.refreshedMediaIDs = [NSMutableSet set];
	if (s.mediaID.length && ![self.refreshedMediaIDs containsObject:s.mediaID]) {
		[self.refreshedMediaIDs addObject:s.mediaID];
		[[RYGStoriesArchiveManager shared] refreshViewersForMediaID:s.mediaID completion:nil];
	}
}

- (void)updateViewerBar {
	RYGArchivedStory *s = [self currentStory];
	if (!s) return;
	NSArray<RYGArchivedStoryViewer *> *viewers = [self.store sortedViewersForStoryPK:s.pk];
	NSInteger likes = 0;
	for (RYGArchivedStoryViewer *v in viewers) if (v.liked) likes++;

	NSInteger shownAvatars = MIN((NSInteger)viewers.count, (NSInteger)self.avatarViews.count);
	self.avatarStackWidth.constant = shownAvatars > 0 ? 26 + (shownAvatars - 1) * 16 : 0;
	self.avatarStack.hidden = shownAvatars == 0;

	if (viewers.count == 0) {
		self.viewerLabel.text = RYGLocalized(@"0 views");
		for (UIImageView *iv in self.avatarViews) iv.hidden = YES;
	} else {
		NSString *viewsStr = viewers.count == 1 ? RYGLocalized(@"1 view") : [NSString stringWithFormat:RYGLocalized(@"%lu views"), (unsigned long)viewers.count];
		NSString *likesStr = likes == 1 ? RYGLocalized(@"1 like") : [NSString stringWithFormat:RYGLocalized(@"%ld likes"), (long)likes];
		self.viewerLabel.text = likes > 0 ? [NSString stringWithFormat:@"%@ · %@", viewsStr, likesStr] : viewsStr;
		for (NSInteger i = 0; i < self.avatarViews.count; i++) {
			UIImageView *iv = self.avatarViews[i];
			if (i < viewers.count) {
				iv.hidden = NO;
				iv.image = nil;
				RYGArchivedStoryViewer *v = viewers[i];
				if (v.profilePicURL.length) {
					NSString *token = v.pk;
					iv.accessibilityIdentifier = token;
					[RYGImageCache loadImageFromURL:[NSURL URLWithString:v.profilePicURL] cacheKey:v.pk completion:^(UIImage *img) {
						if (img && [iv.accessibilityIdentifier isEqualToString:token]) iv.image = img;
					}];
				}
			} else {
				iv.hidden = YES;
			}
		}
	}
}

#pragma mark - Actions

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)openViewers {
	RYGArchivedStory *s = [self currentStory];
	if (s) [RYGStoryViewersSheet presentForStory:s from:self];
}

#pragma mark - Pull to dismiss

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }

- (void)handlePan:(UIPanGestureRecognizer *)pan {
	CGPoint t = [pan translationInView:self.view];
	CGPoint v = [pan velocityInView:self.view];

	switch (pan.state) {
		case UIGestureRecognizerStateChanged: {
			if (!self.dismissing) {
				RYGStoryMediaCell *cell = (RYGStoryMediaCell *)[self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:self.index inSection:0]];
				if (t.y > 0 && fabs(t.y) > fabs(t.x) + 8 && ![cell isZoomed]) {
					self.dismissing = YES;
					self.collectionView.scrollEnabled = NO;
				}
			}
			if (self.dismissing) {
				CGFloat dy = MAX(0, t.y);
				CGFloat p = MIN(dy / 400.0, 1.0);
				self.mediaContainer.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(t.x * 0.4, dy), 1.0 - p * 0.08, 1.0 - p * 0.08);
				self.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:1.0 - p * 0.9];
				CGFloat chromeAlpha = 1.0 - MIN(p * 2.0, 1.0);
				self.topBar.alpha = chromeAlpha;
				self.viewerBar.alpha = chromeAlpha;
			}
			break;
		}
		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled: {
			if (!self.dismissing) break;
			BOOL dismiss = (t.y > 140 || v.y > 900);
			if (dismiss) {
				[UIView animateWithDuration:0.2 animations:^{
					self.mediaContainer.transform = CGAffineTransformMakeTranslation(0, self.view.bounds.size.height);
					self.view.backgroundColor = UIColor.clearColor;
				} completion:^(BOOL done) { [self dismissViewControllerAnimated:NO completion:nil]; }];
			} else {
				[UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
					self.mediaContainer.transform = CGAffineTransformIdentity;
					self.view.backgroundColor = UIColor.blackColor;
					self.topBar.alpha = 1;
					self.viewerBar.alpha = 1;
				} completion:^(BOOL done) {
					self.dismissing = NO;
					self.collectionView.scrollEnabled = YES;
				}];
			}
			break;
		}
		default: break;
	}
}

#pragma mark - Collection view

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return self.stories.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	RYGStoryMediaCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kMediaCell forIndexPath:ip];
	RYGArchivedStory *s = self.stories[ip.item];
	[cell configureWithMediaPath:[self.store absoluteMediaPathForStory:s] isVideo:s.mediaType == 2];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
	return cv.bounds.size;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	if (self.dismissing) return;
	NSInteger idx = (NSInteger)round(scrollView.contentOffset.x / scrollView.bounds.size.width);
	idx = MAX(0, MIN(idx, (NSInteger)self.stories.count - 1));
	if (idx == self.index) return;
	self.index = idx;
	[self pageChanged];
}

- (void)collectionView:(UICollectionView *)cv didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)ip {
	[(RYGStoryMediaCell *)cell setActive:NO];
}

@end
