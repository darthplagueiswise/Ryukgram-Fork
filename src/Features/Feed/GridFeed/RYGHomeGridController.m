#import "RYGHomeGridController.h"
#import "RYGGridFeedService.h"
#import "RYGGridFeedCell.h"
#import "RYGGridFeedInfo.h"
#import "RYGGridButtonLayout.h"
#import "RYGGridFeedSettingsViewController.h"
#import "../../../UI/RYGPopupChrome.h"
#import "../../../RYGChrome.h"
#import "../../../RYGURLOpener.h"
#import "../../../RYGImageCache.h"
#import "../../../ActionButton/RYGMediaViewer.h"
#import "../../../Networking/RYGInstagramAPI.h"
#import "../../../Observers/RYGObservers.h"
#import "../../../Observers/RYGAccountObserver.h"
#import "../../../InstagramHeaders.h"
#import "../../../Utils.h"
#import "../../../UI/RYGIcon.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

static void rygPauseVideos(UIView *v) {
	for (CALayer *l in v.layer.sublayers) {
		if ([l isKindOfClass:[AVPlayerLayer class]]) [[(AVPlayerLayer *)l player] pause];
	}
	for (UIView *sub in v.subviews) rygPauseVideos(sub);
}

static NSString *const kCellID = @"RYGHomeGridCell";
static CGFloat const kSpacing = 2.0;
// IG's tab bar sits outside this view's safe area, so bottom-pinned views clear it by hand.
static CGFloat const kTabBarChrome = 64.0;
static CGFloat const kStoryTraySideInset = 16.0;
static CGFloat const kStoryTrayTopInset = 8.0;

static id rygIvar(id obj, const char *name) {
	if (!obj) return nil;
	Class c = object_getClass(obj);
	while (c) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (iv) return object_getIvar(obj, iv);
		c = class_getSuperclass(c);
	}
	return nil;
}

static void rygCollectCollections(UIView *v, NSMutableArray<UICollectionView *> *out) {
	if ([v isKindOfClass:[UICollectionView class]]) [out addObject:(UICollectionView *)v];
	for (UIView *sub in v.subviews) rygCollectCollections(sub, out);
}

static void rygCollectTrayCandidates(UIView *v, UIView *ig, NSMutableArray<UICollectionView *> *out) {
	if ([v isKindOfClass:[UICollectionView class]] && v != ig) {
		CGFloat h = v.bounds.size.height, w = v.bounds.size.width;
		CGRect f = [v convertRect:v.bounds toView:ig];
		if (h >= 40 && h <= 190 && w > 200 && f.origin.y < 320)
			[out addObject:(UICollectionView *)v];
	}
	for (UIView *sub in v.subviews) rygCollectTrayCandidates(sub, ig, out);
}

static const CGFloat kPreviewStatIconPt = 12;

static void rygAppendStat(NSMutableAttributedString *out, UIImage *icon, NSString *value) {
	static UIFont *font; static UIColor *color;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
		color = [UIColor secondaryLabelColor];
	});
	if (!value.length || !icon) return;
	if (out.length) [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"   "]];
	NSTextAttachment *att = [NSTextAttachment new];
	att.image = [icon imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
	att.bounds = CGRectMake(0, -2, kPreviewStatIconPt, kPreviewStatIconPt);
	[out appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
	[out appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:value]
	                                                           attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}]];
}

static UIImage *rygPreviewTypeIcon(RYGGridFeedPost *post) {
	if (post.mediaType == RYGGridFeedMediaTypeCarousel)
		return [RYGGridFeedInfo iconNamed:@"ig_icon_carousel_prism_filled_16" symbol:@"square.stack.fill" pointSize:16];
	if (post.mediaType == RYGGridFeedMediaTypeVideo)
		return [RYGGridFeedInfo iconNamed:@"ig_icon_reels_prism_filled_16" symbol:@"play.fill" pointSize:16];
	return [RYGGridFeedInfo iconNamed:@"ig_icon_photo_filled_24" symbol:@"photo.fill" pointSize:16];
}

static NSAttributedString *rygPreviewName(RYGGridFeedPost *post, BOOL following) {
	NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],
	                         NSForegroundColorAttributeName: [UIColor labelColor] };
	NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:(post.username ?: @"") attributes:attrs];
	if (!following) return out;
	NSDictionary *tag = @{ NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium],
	                       NSForegroundColorAttributeName: [UIColor secondaryLabelColor] };
	[out appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:RYGLocalized(@"Following")] attributes:tag]];
	return out;
}

static NSAttributedString *rygPreviewStats(RYGGridFeedPost *post) {
	BOOL shorten = [RYGGridFeedInfo shortenedNumbers];
	NSMutableAttributedString *out = [NSMutableAttributedString new];
	if (!post.countsHidden)
		rygAppendStat(out, [RYGGridFeedInfo iconForElement:kRYGGridInfoLikes pointSize:kPreviewStatIconPt], [RYGUtils formatCount:post.likeCount shortened:shorten]);
	rygAppendStat(out, [RYGGridFeedInfo iconForElement:kRYGGridInfoComments pointSize:kPreviewStatIconPt], [RYGUtils formatCount:post.commentCount shortened:shorten]);
	if (post.mediaType == RYGGridFeedMediaTypeVideo && post.viewCount > 0)
		rygAppendStat(out, [RYGGridFeedInfo iconForElement:kRYGGridInfoViews pointSize:kPreviewStatIconPt], [RYGUtils formatCount:post.viewCount shortened:shorten]);
	if (post.shareCount > 0)
		rygAppendStat(out, [RYGGridFeedInfo iconForElement:kRYGGridInfoShares pointSize:kPreviewStatIconPt], [RYGUtils formatCount:post.shareCount shortened:shorten]);
	rygAppendStat(out, [RYGGridFeedInfo iconForElement:kRYGGridInfoDate pointSize:kPreviewStatIconPt],
	              [RYGGridFeedInfo dateStringsForTimestamp:post.takenAt].firstObject);
	NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
	ps.lineSpacing = 5;
	ps.lineBreakMode = NSLineBreakByWordWrapping;
	[out addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, out.length)];
	return out;
}

static BOOL rygPreviewTouchedInfoBar = NO;

// Previews aren't interactive, so a passive recognizer on the menu window records where
// the commit tap landed; hit-testing backs it up.
@interface RYGGridPreviewView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic) CGFloat infoBarTop;
@property (nonatomic, weak) UITapGestureRecognizer *probe;
@end

@implementation RYGGridPreviewView

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (!self.window) { [self.probe.view removeGestureRecognizer:self.probe]; return; }
	if (self.probe) return;
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rygProbeTap:)];
	tap.delegate = self;
	tap.cancelsTouchesInView = NO;
	tap.delaysTouchesBegan = NO;
	tap.delaysTouchesEnded = NO;
	[self.window addGestureRecognizer:tap];
	self.probe = tap;
}

- (void)rygProbeTap:(UITapGestureRecognizer *)g {
	rygPreviewTouchedInfoBar = ([g locationInView:self].y >= self.infoBarTop);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)b { return NO; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)b { return NO; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	rygPreviewTouchedInfoBar = (point.y >= self.infoBarTop);
	return [super hitTest:point withEvent:event];
}

@end

@interface RYGHomeGridController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) UICollectionViewFlowLayout *layout;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIActivityIndicatorView *footer;
@property (nonatomic, strong) UILabel *endLabel;
@property (nonatomic, strong) RYGGridFeedService *service;
@property (nonatomic) CGFloat headerInset;
@property (nonatomic, strong) NSLayoutConstraint *gridTop;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL loadingMore;
@property (nonatomic) BOOL didFirstFill;
@property (nonatomic) BOOL showSkeleton;
@property (nonatomic) NSInteger columns;
@property (nonatomic, weak) UICollectionView *cachedIG;
@property (nonatomic, strong) UICollectionView *storyTray;
@property (nonatomic, weak) UIView *storyTrayOrigSuper;
@property (nonatomic) CGRect storyTrayOrigFrame;
@property (nonatomic) CGFloat storyTrayHeight;
@property (nonatomic) CGFloat storyTrayTopInset;
@property (nonatomic) NSInteger storyCaptureAttempts;
@property (nonatomic) BOOL storyGaveUp;
@property (nonatomic) BOOL pendingScrollTop;
@property (nonatomic) BOOL gotResponse;
@property (nonatomic) BOOL isRefreshing;
@property (nonatomic) NSTimeInterval lastRefreshAt;
@property (nonatomic) NSInteger displayedCount;
@property (nonatomic, strong) id accountToken;
@property (nonatomic, copy) NSString *pendingAccountPK;
@property (nonatomic, weak) UIViewController *storyOwnerVC;
@property (nonatomic) CGSize lastLaidSize;
@property (nonatomic) BOOL storiesHidden;
@property (nonatomic) BOOL didNukeFeed;
@property (nonatomic, strong) RYGChromeButton *toggleButton;
@property (nonatomic, copy) NSString *toggleIcon;
@property (nonatomic) RYGGridTogglePlacement installedPlacement;
@property (nonatomic, weak) UIView *heartButton;
@property (nonatomic, strong) UILongPressGestureRecognizer *heartPress;
@property (nonatomic, strong) NSHashTable<UICollectionView *> *suppressedFeeds;
@property (nonatomic, weak) UIView *chromeHeader;
@property (nonatomic, weak) UIView *chromePill;
@property (nonatomic) BOOL returningFromNativeFeed;
+ (BOOL)effectiveLiked:(RYGGridFeedPost *)post;
+ (BOOL)effectiveFollowing:(RYGGridFeedPost *)post;
- (void)maybeAutoFill;
@end

static __weak RYGHomeGridController *gActiveGrid = nil;

@implementation RYGHomeGridController

+ (BOOL)handleHomeButtonTap {
	RYGHomeGridController *g = gActiveGrid;
	if (!g.active || !g.grid) return NO;
	UICollectionView *cv = g.grid;
	[cv setContentOffset:CGPointMake(0, -cv.adjustedContentInset.top) animated:YES];
	return YES;
}

- (instancetype)initWithHost:(UIViewController *)host {
	if ((self = [super init])) {
		_host = host;
		_columns = [RYGGridFeedInfo columns];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResponseNote:)
		                                             name:RYGGridFeedResponseNote object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncActive)
		                                             name:RYGGridFeedVisibilityDidChange object:nil];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (self.accountToken) [[RYGObservers account] removeChangeHandler:self.accountToken];
}

- (void)markGridReloaded { self.displayedCount = [self.grid numberOfItemsInSection:0]; }

- (void)updateEndFooter {
	BOOL end = !self.service.moreAvailable && !self.showSkeleton && self.service.posts.count > 0;
	self.endLabel.hidden = !end;
	if (!end) return;
	CGFloat y = self.grid.collectionViewLayout.collectionViewContentSize.height + 12;
	self.endLabel.frame = CGRectMake(0, y, self.grid.bounds.size.width, 24);
}

// Reconcile against the real post count using what the grid currently shows, not a
// caller snapshot that goes stale when loadMore and the feed stream mutate concurrently.
- (void)applyGridDeltaFrom:(NSInteger)ignored {
	NSInteger data = self.service.posts.count;
	NSInteger shown = self.displayedCount;
	NSIndexSet *updated = [self.service takePendingUpdated];

	if (self.showSkeleton && data > 0) {
		self.showSkeleton = NO; self.didFirstFill = YES;
		[self.grid reloadData]; [self markGridReloaded];
		return;
	}
	if (!self.showSkeleton && data > shown) {
		NSMutableArray *ins = [NSMutableArray array];
		for (NSInteger i = shown; i < data; i++) [ins addObject:[NSIndexPath indexPathForItem:i inSection:0]];
		@try { [self.grid performBatchUpdates:^{ [self.grid insertItemsAtIndexPaths:ins]; } completion:nil]; self.displayedCount = data; }
		@catch (__unused NSException *e) { [self.grid reloadData]; [self markGridReloaded]; }
	} else if (data < shown) {
		[self.grid reloadData]; [self markGridReloaded];
	}
	[updated enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		if ((NSInteger)idx >= self.displayedCount) return;
		RYGGridFeedCell *cell = (RYGGridFeedCell *)[self.grid cellForItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0]];
		if ([cell isKindOfClass:[RYGGridFeedCell class]]) [cell refreshOverlayWithPost:self.service.posts[idx]];
	}];
	[self updateEndFooter];
}

- (void)onResponseNote:(NSNotification *)note {
	if (!self.active || !self.grid || !self.service) return;
	NSArray<RYGGridFeedPost *> *posts = note.userInfo[@"posts"];
	if (![posts isKindOfClass:[NSArray class]] || !posts.count) return;
	self.gotResponse = YES;
	BOOL replacing = [note.userInfo[@"replacing"] boolValue];
	NSString *next = note.userInfo[@"next"];
	[self ingestPosts:posts replacing:replacing next:next];
}

- (void)ingestPosts:(NSArray<RYGGridFeedPost *> *)posts replacing:(BOOL)replacing next:(NSString *)next {
	// Merge in place; never wipe what's on screen.
	NSInteger before = self.service.posts.count;
	[self.service ingestNextPage:posts nextMaxID:next];
	[self applyGridDeltaFrom:before];
	[self maybeAutoFill];
}

- (void)accountSwitchedTo:(NSString *)curr {
	NSString *cur = curr.length ? curr : nil;
	NSString *have = self.service.accountPK.length ? self.service.accountPK : nil;
	if ((cur == have) || [cur isEqualToString:have]) return;
	// Debounce the observer's first-resolution and duplicate fires.
	self.pendingAccountPK = cur;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commitAccountSwitch) object:nil];
	[self performSelector:@selector(commitAccountSwitch) withObject:nil afterDelay:0.35];
}

- (void)commitAccountSwitch {
	if (!self.active || !self.grid || !self.service) return;
	NSString *curr = self.pendingAccountPK;
	NSString *have = self.service.accountPK.length ? self.service.accountPK : nil;
	if ((curr == have) || [curr isEqualToString:have]) return;
	[self.service clear];
	self.didNukeFeed = NO;
	self.service.accountPK = curr;
	self.service.following = [[RYGUtils getStringPref:@"main_feed_mode"] isEqualToString:@"following"];
	[self.service loadCache];
	self.loadingMore = NO;
	self.gotResponse = NO;
	self.didFirstFill = self.service.posts.count > 0;
	self.showSkeleton = self.service.posts.count == 0;
	[self.grid reloadData];
	[self markGridReloaded];
	[self maybeAutoFill];
}

- (UICollectionView *)igCollectionView {
	if (self.cachedIG && self.cachedIG.superview && self.cachedIG != self.grid) return self.cachedIG;
	UICollectionView *ivar = rygIvar(self.host, "_collectionView");
	if ([ivar isKindOfClass:[UICollectionView class]] && ivar != self.grid) { self.cachedIG = ivar; return ivar; }
	if (!self.host.isViewLoaded) return nil;
	NSMutableArray<UICollectionView *> *all = [NSMutableArray array];
	rygCollectCollections(self.host.view, all);
	UICollectionView *best = nil; CGFloat bestArea = 0;
	for (UICollectionView *cv in all) {
		if (cv == self.grid) continue;
		CGFloat area = cv.bounds.size.width * cv.bounds.size.height;
		if (area > bestArea) { bestArea = area; best = cv; }
	}
	self.cachedIG = best;
	return best;
}

#pragma mark - Activate / deactivate

- (void)syncActive {
	if (![RYGGridFeedInfo active]) return;
	[self installToggleAffordance];
	BOOL want = [RYGGridFeedInfo visible];
	if (want && !self.active) {
		[self install];
	} else if (!want && self.active) {
		[self uninstall];
	} else if (want) {
		[self applyStoriesMode];
		[self recoverStoryTray];
		[self applyItemSize];
		[self.grid reloadData];
		[self markGridReloaded];
	}
	[self updateToggleButton];
}

- (void)install {
	UIViewController *host = self.host;
	UICollectionView *ig = [self igCollectionView];
	if (!host.isViewLoaded || !ig) return;
	self.active = YES;
	self.suppressedFeeds = [NSHashTable weakObjectsHashTable];

	[self suppressFeed:ig];
	rygPauseVideos(ig);
	gActiveGrid = self;

	[[RYGObservers account] start];
	[[RYGObservers account] refreshNow];
	self.service = [RYGGridFeedService new];
	self.service.accountPK = [RYGObservers account].currentPK;
	self.service.following = [[RYGUtils getStringPref:@"main_feed_mode"] isEqualToString:@"following"];
	[self.service loadCache];
	self.gotResponse = NO;
	self.didFirstFill = self.service.posts.count > 0;
	self.showSkeleton = self.service.posts.count == 0;
	if (!self.accountToken) {
		__weak typeof(self) weakSelf = self;
		self.accountToken = [[RYGObservers account] addChangeHandler:^(NSString *prev, NSString *curr) { [weakSelf accountSwitchedTo:curr]; }];
	}

	self.layout = [UICollectionViewFlowLayout new];
	self.layout.minimumInteritemSpacing = kSpacing;
	self.layout.minimumLineSpacing = kSpacing;
	self.layout.sectionInset = UIEdgeInsetsZero;

	self.grid = [[UICollectionView alloc] initWithFrame:ig.bounds collectionViewLayout:self.layout];
	self.grid.translatesAutoresizingMaskIntoConstraints = NO;
	self.grid.backgroundColor = [UIColor systemBackgroundColor];
	self.grid.alwaysBounceVertical = YES;
	self.grid.dataSource = self;
	self.grid.delegate = self;
	self.grid.prefetchDataSource = self;
	self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	[self.grid registerClass:[RYGGridFeedCell class] forCellWithReuseIdentifier:kCellID];

	self.refresh = [UIRefreshControl new];
	[self.refresh addTarget:self action:@selector(pulledRefresh) forControlEvents:UIControlEventValueChanged];
	self.grid.refreshControl = self.refresh;

	UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
	[self.grid addGestureRecognizer:pinch];

	CGFloat headerTop = ig.adjustedContentInset.top;
	if (headerTop < 1) headerTop = host.view.safeAreaInsets.top + 44;
	self.headerInset = headerTop;
	self.grid.contentInset = UIEdgeInsetsMake(0, 0, 40, 0);

	[ig.superview insertSubview:self.grid aboveSubview:ig];
	self.gridTop = [self.grid.topAnchor constraintEqualToAnchor:ig.topAnchor constant:headerTop];
	[NSLayoutConstraint activateConstraints:@[
		self.gridTop,
		[self.grid.leadingAnchor constraintEqualToAnchor:ig.leadingAnchor],
		[self.grid.trailingAnchor constraintEqualToAnchor:ig.trailingAnchor],
		[self.grid.bottomAnchor constraintEqualToAnchor:ig.bottomAnchor],
	]];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	[self.grid addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.grid.centerXAnchor],
		[self.spinner.topAnchor constraintEqualToAnchor:self.grid.topAnchor constant:60],
	]];

	self.footer = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.footer.translatesAutoresizingMaskIntoConstraints = NO;
	self.footer.hidesWhenStopped = YES;
	[host.view addSubview:self.footer];
	[NSLayoutConstraint activateConstraints:@[
		[self.footer.centerXAnchor constraintEqualToAnchor:self.grid.centerXAnchor],
		[self.footer.bottomAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
	]];

	self.endLabel = [[UILabel alloc] init];
	self.endLabel.text = RYGLocalized(@"You're all caught up");
	self.endLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
	self.endLabel.textColor = [UIColor tertiaryLabelColor];
	self.endLabel.textAlignment = NSTextAlignmentCenter;
	self.endLabel.hidden = YES;
	[self.grid addSubview:self.endLabel];

	self.storyCaptureAttempts = 0;
	self.storyGaveUp = NO;
	[self applyStoriesMode];
	[self applyItemSize];
	[self.grid reloadData];
	[self markGridReloaded];
	// The transport already delivered a page before we installed — take it now. Further
	// pages arrive live via RYGGridFeedResponseNote; pagination is the API from the cursor.
	NSArray<RYGGridFeedPost *> *latest = RYGLatestFeedPosts();
	if (latest.count) { self.gotResponse = YES; [self ingestPosts:latest replacing:RYGLatestFeedReplacing() next:RYGLatestFeedNextMaxID()]; }
	[self maybeAutoFill];
	if (![RYGGridFeedInfo hideStories]) [self tryCaptureLoop];

	[host.view bringSubviewToFront:self.toggleButton];
	self.grid.alpha = 0;
	[UIView animateWithDuration:0.2 animations:^{ self.grid.alpha = 1; }];

	// Inheriting IG's scroll offset would drop you into the middle of the grid.
	[self.grid layoutIfNeeded];
	[self.grid setContentOffset:CGPointMake(0, -self.grid.adjustedContentInset.top) animated:NO];
	if (self.returningFromNativeFeed) {
		self.returningFromNativeFeed = NO;
		[self pulledRefresh];
	}
}

- (void)uninstall {
	self.active = NO;
	self.returningFromNativeFeed = YES;
	if (gActiveGrid == self) gActiveGrid = nil;
	[self restoreStoryTray];
	[self revealIGFeed];

	UICollectionView *leaving = self.grid;
	[UIView animateWithDuration:0.2 animations:^{ leaving.alpha = 0; } completion:^(BOOL done) { [leaving removeFromSuperview]; }];
	[self.footer removeFromSuperview];

	self.grid = nil;
	self.layout = nil;
	self.gridTop = nil;
	self.refresh = nil;
	self.spinner = nil;
	self.footer = nil;
	self.endLabel = nil;
	self.service = nil;
	self.displayedCount = 0;
	self.didFirstFill = NO;
	self.showSkeleton = NO;
	self.loadingMore = NO;
	self.isRefreshing = NO;
	self.gotResponse = NO;
	self.didNukeFeed = NO;
	self.storyGaveUp = NO;
	self.storyCaptureAttempts = 0;
	self.lastLaidSize = CGSizeZero;

	[self requestIGFeedRefresh];
}

// Only what we suppressed — IG hides collections of its own for its own reasons.
- (void)revealIGFeed {
	self.cachedIG = nil;
	for (UICollectionView *cv in self.suppressedFeeds) {
		cv.hidden = NO;
		cv.scrollEnabled = YES;
		cv.prefetchingEnabled = YES;
		[cv setContentOffset:CGPointMake(0, -cv.adjustedContentInset.top) animated:NO];
	}
	[self.suppressedFeeds removeAllObjects];
}

- (void)collectFeedVCsFrom:(UIViewController *)vc into:(NSMutableArray<UIResponder *> *)out {
	if (!vc) return;
	[out addObject:vc];
	for (UIViewController *child in vc.childViewControllers) [self collectFeedVCsFrom:child into:out];
}

// IGMainFeedViewController_objc owns the view model, not the VC we hook.
- (IGMainFeedViewModel *)feedViewModel {
	NSMutableArray<UIResponder *> *candidates = [NSMutableArray array];
	if (self.host) [self collectFeedVCsFrom:self.host into:candidates];
	if (self.storyOwnerVC) [candidates addObject:self.storyOwnerVC];
	for (UIResponder *r = [self igCollectionView]; r; r = r.nextResponder)
		if ([r isKindOfClass:[UIViewController class]]) [candidates addObject:r];

	for (UIResponder *c in candidates) {
		if (![c respondsToSelector:@selector(viewModel)]) continue;
		id vm = ((id (*)(id, SEL))objc_msgSend)(c, @selector(viewModel));
		if ([vm respondsToSelector:@selector(fetchDataWithMainFeedFetchReason:hoistedMediaID:hoistedMediaShortcode:deeplinkURL:isAppStartNonFeedSurface:requestCancellationBlock:cachedMediaIDs:)])
			return (IGMainFeedViewModel *)vm;
	}
	return nil;
}

// IG ingested nothing while the grid owned the feed, so it comes back empty until a fetch.
- (void)requestIGFeedRefresh {
	UIViewController *host = self.host;
	IGMainFeedViewModel *vm = [self feedViewModel];

	SEL fetch = @selector(fetchDataWithMainFeedFetchReason:hoistedMediaID:hoistedMediaShortcode:deeplinkURL:isAppStartNonFeedSurface:requestCancellationBlock:cachedMediaIDs:);
	if ([vm respondsToSelector:fetch]) {
		RYGProbeOnce(@"gridfeed.handback.viewmodel", @"fetchDataWithMainFeedFetchReason");
		long long reason = [vm respondsToSelector:@selector(lastFetchReasonForRefresh)] ? [vm lastFetchReasonForRefresh] : 0;
		[vm fetchDataWithMainFeedFetchReason:reason hoistedMediaID:nil hoistedMediaShortcode:nil deeplinkURL:nil
		            isAppStartNonFeedSurface:NO requestCancellationBlock:nil cachedMediaIDs:nil];
		return;
	}
	if ([host respondsToSelector:@selector(pullToRefreshIfPossible)]) {
		RYGProbeOnce(@"gridfeed.handback.pulltorefresh", @"viewModel fetch missing");
		((void (*)(id, SEL))objc_msgSend)(host, @selector(pullToRefreshIfPossible));
		return;
	}
	RYGProbeOnce(@"gridfeed.handback.refreshcontrol", @"no IG fetch selector resolved");
	[[self igCollectionView].refreshControl sendActionsForControlEvents:UIControlEventValueChanged];
}

#pragma mark - Live toggle

- (void)installToggleAffordance {
	RYGGridTogglePlacement want = [RYGGridFeedInfo togglePlacement];
	if (want != self.installedPlacement) [self teardownToggleAffordance];
	self.installedPlacement = want;
	switch (want) {
		case RYGGridTogglePlacementOff: return;
		case RYGGridTogglePlacementHeartLongPress: [self installHeartGesture]; return;
		default: [self installToggleButton]; [self layoutToggleButton]; return;
	}
}

- (void)teardownToggleAffordance {
	[self.toggleButton removeFromSuperview];
	self.toggleButton = nil;
	self.toggleIcon = nil;
	if (self.heartPress) [self.heartButton removeGestureRecognizer:self.heartPress];
	self.heartPress = nil;
	self.heartButton = nil;
}

- (void)installToggleButton {
	UIViewController *host = self.host;
	if (!host.isViewLoaded) return;
	if (self.toggleButton.superview == host.view) { [host.view bringSubviewToFront:self.toggleButton]; return; }

	CGFloat d = [RYGGridButtonLayout diameterForID:RYGGridBtnToggle];
	RYGChromeButton *btn = [[RYGChromeButton alloc] initWithSymbol:@"square.grid.2x2.fill" pointSize:18 diameter:d];
	btn.bubbleColor = [UIColor colorWithWhite:0 alpha:0.55];
	btn.iconTint = [UIColor whiteColor];
	btn.accessibilityLabel = RYGLocalized(@"Grid feed");
	btn.layer.shadowColor = [UIColor blackColor].CGColor;
	btn.layer.shadowOpacity = 0.25;
	btn.layer.shadowRadius = 8;
	btn.layer.shadowOffset = CGSizeMake(0, 2);
	[btn addTarget:self action:@selector(toggleButtonTapped) forControlEvents:UIControlEventTouchUpInside];
	[btn addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(toggleButtonHeld:)]];
	[host.view addSubview:btn];
	self.toggleButton = btn;
	[self updateToggleButton];
}

- (void)layoutToggleButton {
	RYGChromeButton *btn = self.toggleButton;
	UIViewController *host = self.host;
	if (!btn || !host.isViewLoaded) return;
	// Not via the window: a settings modal detaches our view, and a position saved in the
	// editor then wouldn't land until something else moved the button.
	UIEdgeInsets hostInsets = host.view.safeAreaInsets;
	// Early passes run before the insets resolve.
	if (!host.view.window && UIEdgeInsetsEqualToEdgeInsets(hostInsets, UIEdgeInsetsZero)) return;
	CGRect safe = UIEdgeInsetsInsetRect(host.view.bounds, hostInsets);
	if (safe.size.width <= 0 || safe.size.height <= 0) return;

	UIEdgeInsets ins = [RYGGridButtonLayout placeableInsetsNormalized];
	CGRect area = CGRectMake(safe.origin.x + ins.left * safe.size.width,
	                         safe.origin.y + ins.top * safe.size.height,
	                         safe.size.width * (1.0 - ins.left - ins.right),
	                         safe.size.height * (1.0 - ins.top - ins.bottom));

	CGFloat d = [RYGGridButtonLayout diameterForID:RYGGridBtnToggle], half = d / 2.0;
	CGPoint norm = [RYGGridButtonLayout positionForID:RYGGridBtnToggle];
	CGFloat cx = safe.origin.x + norm.x * safe.size.width;
	CGFloat cy = safe.origin.y + norm.y * safe.size.height;
	cx = MIN(MAX(cx, CGRectGetMinX(area) + half), CGRectGetMaxX(area) - half);
	cy = MIN(MAX(cy, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half);

	btn.bounds = CGRectMake(0, 0, d, d);
	btn.center = CGPointMake(cx, cy);
}

// IGHomeFeedHeaderView owns the heart; find it by the accessor rather than the Swift name.
- (UIView *)headerViewWithActivityButton:(UIView *)root {
	if ([root respondsToSelector:@selector(activityButton)]) return root;
	for (UIView *sub in root.subviews) {
		UIView *hit = [self headerViewWithActivityButton:sub];
		if (hit) return hit;
	}
	return nil;
}

- (void)installHeartGesture {
	if (self.heartPress.view) return;
	UIViewController *host = self.host;
	if (!host.isViewLoaded) return;
	UIView *header = [self headerViewWithActivityButton:host.view];
	if (!header && host.view.window) header = [self headerViewWithActivityButton:host.view.window];
	UIView *heart = header ? ((id (*)(id, SEL))objc_msgSend)(header, @selector(activityButton)) : nil;
	if (![heart isKindOfClass:[UIView class]]) return;
	RYGProbeOnce(@"gridfeed.toggle.heart", @"activityButton long-press attached");

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(heartLongPressed:)];
	lp.minimumPressDuration = 0.4;
	[heart addGestureRecognizer:lp];
	self.heartButton = heart;
	self.heartPress = lp;
}

- (void)heartLongPressed:(UILongPressGestureRecognizer *)g {
	if (g.state != UIGestureRecognizerStateBegan) return;
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	[RYGGridFeedInfo toggleVisible];
}

// The glyph shows what a tap switches to, matching how IG's own layout switchers read.
- (void)updateToggleButton {
	RYGChromeButton *btn = self.toggleButton;
	if (!btn) return;
	NSString *want = [RYGGridFeedInfo visible] ? @"ig_icon_photo_list_outline_24" : @"ig_icon_photo_grid_filled_24";
	if ([want isEqualToString:self.toggleIcon]) return;
	self.toggleIcon = want;
	[UIView transitionWithView:btn.iconView duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
	                animations:^{ [btn setIconResource:want pointSize:20]; } completion:nil];
}

- (void)toggleButtonTapped {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	RYGChromeButton *btn = self.toggleButton;
	[UIView animateWithDuration:0.12 animations:^{ btn.transform = CGAffineTransformMakeScale(0.88, 0.88); } completion:^(BOOL done) {
		[UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:0
		                 animations:^{ btn.transform = CGAffineTransformIdentity; } completion:nil];
	}];
	[RYGGridFeedInfo toggleVisible];
}

- (void)toggleButtonHeld:(UILongPressGestureRecognizer *)press {
	if (press.state != UIGestureRecognizerStateBegan) return;
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	[RYGPopupChrome presentVC:[RYGGridFeedSettingsViewController new] from:nil];
}

- (void)captureStoryTray {
	if (self.storyTray) return;
	UICollectionView *ig = [self igCollectionView];
	if (!ig) return;
	NSMutableArray<UICollectionView *> *trays = [NSMutableArray array];
	rygCollectTrayCandidates(ig, ig, trays);
	UICollectionView *tray = nil;
	CGFloat bestY = CGFLOAT_MAX;
	for (UICollectionView *t in trays) {
		CGRect f = [t convertRect:t.bounds toView:ig];
		if (f.origin.y < bestY) { bestY = f.origin.y; tray = t; }
	}
	if (!tray) return;

	self.storyTray = tray;
	self.didNukeFeed = NO;
	// Grab the feed VC before reparenting severs the link — it's the only handle that can
	// re-fetch story data on pull-to-refresh.
	for (UIResponder *r = tray; r; r = r.nextResponder) {
		if ([r isKindOfClass:[UIViewController class]] && [r respondsToSelector:@selector(reloadStoryTray)]) {
			self.storyOwnerVC = (UIViewController *)r; break;
		}
	}
	self.storyTrayOrigSuper = tray.superview;
	self.storyTrayOrigFrame = tray.frame;
	// A mid-layout capture can report oversized bounds; trim to the real content height.
	CGFloat h = tray.bounds.size.height;
	CGFloat contentH = tray.contentSize.height;
	if (contentH > 40 && contentH + 28 < h) h = contentH + 28;
	self.storyTrayHeight = h;
	tray.translatesAutoresizingMaskIntoConstraints = YES;
	tray.frame = CGRectMake(0, -self.storyTrayHeight, self.grid.bounds.size.width, self.storyTrayHeight);
	tray.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.grid addSubview:tray];
	self.storyTrayTopInset = [self measureStoryTrayTopInsetForTray:tray content:contentH];
	[self normalizeStoryTrayInsets];
}

// Top gap proportional to the measured ring diameter (scales across devices), capped by the
// tray's spare height so the username never clips. Falls back to a centred gap.
- (CGFloat)measureStoryTrayTopInsetForTray:(UICollectionView *)tray content:(CGFloat)contentH {
	CGFloat slack = MAX(0, self.storyTrayHeight - contentH);
	UICollectionViewCell *cell0 = (UICollectionViewCell *)[tray cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
	CGFloat ringSide = 0;
	for (UIView *v = cell0; v; ) {
		UIView *next = nil;
		for (UIView *s in v.subviews) {
			CGFloat side = MIN(s.bounds.size.width, s.bounds.size.height);
			if (s.layer.cornerRadius > side * 0.35 && side > ringSide) ringSide = side;
			if (s.subviews.count) next = s;
		}
		v = next;
	}
	// Ring unmeasurable (cell not laid out) → keep the last good gap, not a smaller fallback.
	CGFloat margin = ringSide > 0 ? ringSide * 0.16 : (self.storyTrayTopInset > 0 ? self.storyTrayTopInset : slack / 2.0);
	return MIN(margin, slack);
}

// iPad centres the tray with big horizontal insets that shove the circles inward once
// reparented to the full-width grid — cap them; the top inset clears the ring from the header.
- (void)normalizeStoryTrayInsets {
	if (!self.storyTray) return;
	UIEdgeInsets ci = self.storyTray.contentInset;
	CGFloat l = MIN(ci.left, kStoryTraySideInset);
	CGFloat r = MIN(ci.right, kStoryTraySideInset);
	CGFloat t = MAX(ci.top, self.storyTrayTopInset > 0 ? self.storyTrayTopInset : kStoryTrayTopInset);
	if (ci.left != l || ci.right != r || ci.top != t) self.storyTray.contentInset = UIEdgeInsetsMake(t, l, ci.bottom, r);
}

- (void)tryCaptureLoop {
	if (!self.active || !self.grid || [RYGGridFeedInfo hideStories]) return;
	UICollectionView *ig = [self igCollectionView];
	if (ig) rygPauseVideos(ig);
	[self captureStoryTray];
	if (self.storyTray) {
		[self applyStoriesMode];
		if (self.pendingScrollTop) {
			self.pendingScrollTop = NO;
			[self.grid setContentOffset:CGPointMake(0, -self.grid.adjustedContentInset.top) animated:NO];
		}
		// Ring size resolves a frame or two after capture; settle across a few frames.
		[self reassertStoryTrayAfterReload];
		return;
	}
	if (self.storyCaptureAttempts++ < 15) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self tryCaptureLoop]; });
	} else {
		self.storyGaveUp = YES;
		[self nukeFeed];
		[self applyStoriesMode];
	}
}

- (void)restoreStoryTray {
	if (!self.storyTray) return;
	self.storyTray.frame = self.storyTrayOrigFrame;
	if (self.storyTrayOrigSuper) [self.storyTrayOrigSuper addSubview:self.storyTray];
	self.storyTray = nil;
	self.storyTrayOrigSuper = nil;
	self.storyTrayHeight = 0;
}

// Hide IG's own feed collections so nothing shows through the grid; keep our grid and tray.
- (void)nukeFeed {
	NSMutableArray<UICollectionView *> *all = [NSMutableArray array];
	rygCollectCollections(self.host.view, all);
	for (UICollectionView *cv in all) {
		if (cv == self.grid || cv == self.storyTray) continue;
		if (cv.bounds.size.height > 200) {
			[self suppressFeed:cv];
			rygPauseVideos(cv);
		}
	}
}

- (void)suppressFeed:(UICollectionView *)cv {
	if (!cv) return;
	[self.suppressedFeeds addObject:cv];
	// IG can't un-collapse its header once the feed is hidden, so bounce to the top first.
	[cv setContentOffset:CGPointMake(0, -cv.adjustedContentInset.top) animated:NO];
	cv.hidden = YES;
	cv.scrollEnabled = NO;
	cv.prefetchingEnabled = NO;
}

- (void)setGridContentInset:(UIEdgeInsets)want {
	if (!UIEdgeInsetsEqualToEdgeInsets(self.grid.contentInset, want)) self.grid.contentInset = want;
}

- (void)nukeFeedOnce {
	if (self.didNukeFeed) return;
	[self nukeFeed];
	self.didNukeFeed = YES;
}

- (void)applyStoriesMode {
	BOOL hide = [RYGGridFeedInfo hideStories];
	self.storiesHidden = hide;
	CGFloat bottom = self.host.view.safeAreaInsets.bottom + kTabBarChrome;
	if (hide) {
		[self restoreStoryTray];
		[self nukeFeedOnce];
		[self setGridContentInset:UIEdgeInsetsMake(0, 0, bottom, 0)];
		return;
	}
	CGFloat reserved = [self storyReservedTop];
	if (self.storyTray) [self nukeFeedOnce];
	[self setGridContentInset:UIEdgeInsetsMake(reserved, 0, bottom, 0)];
	if (self.storyTray) {
		CGRect want = CGRectMake(0, -reserved, self.grid.bounds.size.width, self.storyTrayHeight);
		if (!CGRectEqualToRect(self.storyTray.frame, want)) self.storyTray.frame = want;
	}
}

// Reserved band above the grid: tray height plus a gap so the usernames clear the cards.
- (CGFloat)storyTrayGridGap { return round(self.storyTrayHeight * 0.10); }
- (CGFloat)storyReservedTop {
	if (!self.storyTray) return self.storyGaveUp ? 0 : 126;
	return self.storyTrayHeight + [self storyTrayGridGap];
}

// IG hides the tray for its story transition and restores it in its own hierarchy, not
// ours — so it can strand hidden (black in dark mode).
- (void)recoverStoryTray {
	if (!self.storyTray || self.storiesHidden) return;
	BOOL drifted = (self.storyTray.superview != self.grid) || self.storyTray.hidden || self.storyTray.alpha < 0.99;
	if (self.storyTray.superview != self.grid) {
		self.storyTray.translatesAutoresizingMaskIntoConstraints = YES;
		[self.grid addSubview:self.storyTray];
	}
	self.storyTray.hidden = NO;
	self.storyTray.alpha = 1;
	[self pinStoryTray];
	if (drifted && [self.storyTray respondsToSelector:@selector(reloadData)]) [self.storyTray reloadData];
}

// IG still owns the reparented tray and re-lays it out on reloads; re-assert our frame.
- (void)pinStoryTray {
	if (!self.storyTray || self.storyTray.superview != self.grid || self.storiesHidden) return;
	if (self.storyTray.hidden) self.storyTray.hidden = NO;
	if (self.storyTray.alpha < 0.99) self.storyTray.alpha = 1;
	[self normalizeStoryTrayInsets];
	CGFloat reserved = [self storyReservedTop];
	CGRect want = CGRectMake(0, -reserved, self.grid.bounds.size.width, self.storyTrayHeight);
	if (!CGRectEqualToRect(self.storyTray.frame, want)) self.storyTray.frame = want;
	// Pull-to-refresh inflates the top inset; restore it after so the tray isn't under the
	// IG header. No-op mid-scroll (inset already == reserved).
	if (!self.isRefreshing && self.grid.contentInset.top != reserved) {
		UIEdgeInsets ci = self.grid.contentInset; ci.top = reserved; self.grid.contentInset = ci;
	}
}

// IG's async relayout can reparent the tray back to its hidden feed; re-adopt, re-measure
// the gap and re-pin across a few frames until it settles.
- (void)reassertStoryTrayAfterReload {
	for (NSNumber *d in @[@0.05, @0.2, @0.5, @0.9, @1.5]) {
		__weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (!weakSelf) return;
			if (weakSelf.storyTray)
				weakSelf.storyTrayTopInset = [weakSelf measureStoryTrayTopInsetForTray:weakSelf.storyTray content:weakSelf.storyTray.contentSize.height];
			[weakSelf recoverStoryTray];
			// The launch offset predates the reserved gap; if still near the top, snap to it.
			CGFloat topY = -weakSelf.grid.adjustedContentInset.top;
			if (!weakSelf.isRefreshing && fabs(weakSelf.grid.contentOffset.y - topY) < weakSelf.storyTrayHeight && weakSelf.grid.contentOffset.y != topY)
				[weakSelf.grid setContentOffset:CGPointMake(0, topY) animated:NO];
		});
	}
}

#pragma mark - Layout

// The visible pill is the tab buttons' shared superview; matching on them avoids IG's Swift names.
static UIView *rygTabBarPill(UIView *root) {
	NSString *cn = NSStringFromClass([root class]);
	if ([cn containsString:@"TabBarButton"] && ![cn containsString:@"Container"]) return root.superview;
	for (UIView *sub in root.subviews) {
		UIView *hit = rygTabBarPill(sub);
		if (hit) return hit;
	}
	return nil;
}

static CGRect rygNormalizedInSafeArea(UIView *v, UIWindow *win, CGRect safe) {
	CGRect r = [v convertRect:v.bounds toView:win];
	return CGRectMake((r.origin.x - safe.origin.x) / safe.size.width,
	                  (r.origin.y - safe.origin.y) / safe.size.height,
	                  r.size.width / safe.size.width,
	                  r.size.height / safe.size.height);
}

- (void)measureChrome {
	UIWindow *win = self.host.view.window;
	if (!win) return;
	CGRect safe = UIEdgeInsetsInsetRect(win.bounds, win.safeAreaInsets);
	if (safe.size.width <= 0 || safe.size.height <= 0) return;

	// Hold onto both views; finding them again is a full hierarchy sweep.
	UIView *header = self.chromeHeader.window == win ? self.chromeHeader : [self headerViewWithActivityButton:win];
	UIView *pill = self.chromePill.window == win ? self.chromePill : rygTabBarPill(win);
	if (!header || !pill) return;
	self.chromeHeader = header;
	self.chromePill = pill;

	[RYGGridButtonLayout recordHeaderRect:rygNormalizedInSafeArea(header, win, safe)
	                           tabBarRect:rygNormalizedInSafeArea(pill, win, safe)];
}

- (void)hostDidLayout {
	[self measureChrome];
	[self layoutToggleButton];
	// The header is built after our first sync, so the heart isn't there to grab yet.
	if (self.installedPlacement == RYGGridTogglePlacementHeartLongPress && !self.heartPress.view)
		[self installHeartGesture];
	if (!self.active || !self.grid) return;
	CGSize sz = self.grid.bounds.size;
	if (CGSizeEqualToSize(sz, self.lastLaidSize)) return;
	self.lastLaidSize = sz;
	[self applyStoriesMode];
	[self applyItemSize];
}

#pragma mark - Context menu (peek)

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
	if (ip.item >= (NSInteger)self.service.posts.count) return nil;
	RYGGridFeedPost *post = self.service.posts[ip.item];
	NSInteger item = ip.item;
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:@(item)
		previewProvider:^UIViewController *{
			UIViewController *vc = [UIViewController new];
			CGFloat W = 320, imgH = 320, pad = 12, avatarSize = 32;
			NSAttributedString *statsText = rygPreviewStats(post);
			CGFloat statsX = pad + 6;
			CGFloat statsW = W - statsX * 2;
			CGFloat statsH = ceil([statsText boundingRectWithSize:CGSizeMake(statsW, 200)
			                                              options:NSStringDrawingUsesLineFragmentOrigin
			                                              context:nil].size.height);
			CGFloat barH = pad + avatarSize + 4 + statsH + pad + 2;

			rygPreviewTouchedInfoBar = NO;
			RYGGridPreviewView *root = [[RYGGridPreviewView alloc] initWithFrame:CGRectMake(0, 0, W, imgH + barH)];
			root.infoBarTop = imgH;
			root.backgroundColor = [UIColor systemBackgroundColor];

			UIView *imageClip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, imgH)];
			imageClip.clipsToBounds = YES;
			imageClip.backgroundColor = [UIColor secondarySystemBackgroundColor];
			[root addSubview:imageClip];

			UIImageView *iv = [[UIImageView alloc] initWithFrame:imageClip.bounds];
			iv.contentMode = UIViewContentModeScaleAspectFill;
			[imageClip addSubview:iv];

			NSString *countText = post.carouselCount > 1 ? [NSString stringWithFormat:@"%ld", (long)post.carouselCount] : nil;
			UIFont *countFont = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
			CGFloat badgeH = 28, iconSize = 16, sidePad = 6, textGap = 4;
			CGFloat countW = countText ? ceil([countText sizeWithAttributes:@{NSFontAttributeName: countFont}].width) : 0;
			CGFloat badgeW = sidePad * 2 + iconSize + (countText ? textGap + countW : 0);

			UIVisualEffectView *typeBadge = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
			typeBadge.frame = CGRectMake(W - pad - badgeW, pad, badgeW, badgeH);
			typeBadge.layer.cornerRadius = badgeH / 2;
			typeBadge.clipsToBounds = YES;
			[root addSubview:typeBadge];

			UIImageView *ti = [[UIImageView alloc] initWithFrame:CGRectMake(sidePad, (badgeH - iconSize) / 2, iconSize, iconSize)];
			ti.image = rygPreviewTypeIcon(post);
			ti.tintColor = [UIColor whiteColor];
			ti.contentMode = UIViewContentModeScaleAspectFit;
			[typeBadge.contentView addSubview:ti];

			if (countText) {
				UILabel *count = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(ti.frame) + textGap, 0, countW, badgeH)];
				count.font = countFont;
				count.textColor = [UIColor whiteColor];
				count.text = countText;
				[typeBadge.contentView addSubview:count];
			}

			UIView *infoBar = [[UIView alloc] initWithFrame:CGRectMake(0, imgH, W, barH)];
			infoBar.backgroundColor = [UIColor secondarySystemBackgroundColor];
			[root addSubview:infoBar];

			UIImageView *av = [[UIImageView alloc] initWithFrame:CGRectMake(pad, imgH + pad, avatarSize, avatarSize)];
			av.contentMode = UIViewContentModeScaleAspectFill;
			av.clipsToBounds = YES;
			av.layer.cornerRadius = avatarSize / 2;
			av.backgroundColor = [UIColor secondarySystemBackgroundColor];
			[root addSubview:av];

			UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(av.frame) + 8, imgH + pad, W - CGRectGetMaxX(av.frame) - 8 - pad, avatarSize)];
			name.lineBreakMode = NSLineBreakByTruncatingTail;
			name.attributedText = rygPreviewName(post, [RYGHomeGridController effectiveFollowing:post]);
			[root addSubview:name];

			UILabel *stats = [[UILabel alloc] initWithFrame:CGRectMake(statsX, CGRectGetMaxY(av.frame) + 4, statsW, statsH)];
			stats.numberOfLines = 0;
			stats.lineBreakMode = NSLineBreakByWordWrapping;
			stats.attributedText = statsText;
			[root addSubview:stats];

			vc.view = root;
			vc.preferredContentSize = CGSizeMake(W, imgH + barH);

			// Same pk key and disk bytes the tile already pulled — no second download.
			if (post.thumbURLString.length)
				[RYGImageCache loadThumbnailFromURL:[NSURL URLWithString:post.thumbURLString]
										   cacheKey:(post.pk.length ? post.pk : post.code)
										   maxPixel:720
										 completion:^(UIImage *img){
											 iv.image = img;
											 if (img.size.width <= 0 || img.size.height <= 0) return;
											 CGFloat h = W * img.size.height / img.size.width;
											 if (h <= imgH) { iv.frame = imageClip.bounds; return; }
											 iv.frame = CGRectMake(0, -(h - imgH) * 0.25, W, h);
										 }];
			if (post.avatarURLString.length)
				[RYGImageCache loadImageFromURL:[NSURL URLWithString:post.avatarURLString] completion:^(UIImage *img){ av.image = img; }];
			return vc;
		}
		actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sugg){
			BOOL liked = [RYGHomeGridController effectiveLiked:post];
			BOOL following = [RYGHomeGridController effectiveFollowing:post];

			UIAction *like = [UIAction actionWithTitle:(liked ? RYGLocalized(@"Unlike") : RYGLocalized(@"Like"))
			                                     image:[UIImage systemImageNamed:(liked ? @"heart.slash" : @"heart")] identifier:nil handler:^(UIAction *a){ [weakSelf toggleLikePost:post item:item]; }];
			if (liked) like.attributes = 0;
			UIAction *follow = [UIAction actionWithTitle:(following ? RYGLocalized(@"Unfollow") : RYGLocalized(@"Follow"))
			                                       image:[RYGIcon menuImageNamed:(following ? @"ig_icon_user_unfollow_prism_outline_24" : @"ig_icon_user_follow_outline_24") pointSize:18] identifier:nil handler:^(UIAction *a){ [weakSelf toggleFollowPost:post item:item]; }];
			follow.attributes = following ? UIMenuElementAttributesDestructive : 0;
			UIMenu *engage = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:(post.userPK.length ? @[like, follow] : @[like])];

			UIAction *open = [UIAction actionWithTitle:RYGLocalized(@"Open post") image:[RYGIcon menuImageNamed:@"ig_icon_crosspost_outline_24" pointSize:18] identifier:nil handler:^(UIAction *a){ [weakSelf openPostAtItem:item]; }];
			UIAction *expand = [UIAction actionWithTitle:RYGLocalized(@"Expand") image:[RYGIcon menuImageNamed:@"bcn_arrow-expand_outline_24" pointSize:18] identifier:nil handler:^(UIAction *a){
				if (post.thumbURLString.length) [RYGMediaViewer showWithVideoURL:nil photoURL:[NSURL URLWithString:post.thumbURLString] caption:nil];
			}];
			UIAction *profile = [UIAction actionWithTitle:RYGLocalized(@"View profile") image:[RYGIcon menuImageNamed:@"bcn_user_outline_24" pointSize:18] identifier:nil handler:^(UIAction *a){
				if (post.username.length) [RYGURLOpener openInstagramProfileForUsername:post.username];
			}];
			UIMenu *nav = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[open, expand, profile]];

			UIAction *share = [UIAction actionWithTitle:RYGLocalized(@"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a){ [weakSelf sharePost:post fromItem:item]; }];
			UIAction *copy = [UIAction actionWithTitle:RYGLocalized(@"Copy link") image:[RYGIcon menuImageNamed:@"bcn_copy_outline_24" pointSize:18] identifier:nil handler:^(UIAction *a){
				if (post.code.length) [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://www.instagram.com/p/%@/", post.code];
			}];
			UIMenu *sharing = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[share, copy]];

			return [UIMenu menuWithTitle:@"" children:@[engage, nav, sharing]];
		}];
}

- (void)collectionView:(UICollectionView *)cv willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)cfg animator:(id<UIContextMenuInteractionCommitAnimating>)animator {
	id ident = cfg.identifier;
	NSNumber *idx = [ident isKindOfClass:[NSNumber class]] ? (NSNumber *)ident : nil;
	if (!idx || idx.integerValue < 0 || idx.integerValue >= (NSInteger)self.service.posts.count) return;
	NSInteger item = idx.integerValue;
	NSString *username = self.service.posts[item].username;
	BOOL toProfile = rygPreviewTouchedInfoBar && username.length;
	__weak typeof(self) weakSelf = self;
	[animator addCompletion:^{
		if (toProfile) [RYGURLOpener openInstagramProfileForUsername:username];
		else [weakSelf openPostAtItem:item];
	}];
}

static NSMutableDictionary *rygLoadStateDict(NSString *key) {
	NSString *json = [RYGUtils getStringPref:key];
	NSData *data = json.length ? [json dataUsingEncoding:NSUTF8StringEncoding] : nil;
	id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	return [obj isKindOfClass:[NSDictionary class]] ? [obj mutableCopy] : [NSMutableDictionary dictionary];
}
static void rygSaveStateDict(NSString *key, NSDictionary *d) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
	if (data) [RYGUtils setPref:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] forKey:key];
}
static NSMutableDictionary *rygLikeState(void) {
	static NSMutableDictionary *d; static dispatch_once_t o; dispatch_once(&o, ^{ d = rygLoadStateDict(@"grid_feed_like_state"); });
	return d;
}
static NSMutableDictionary *rygFollowState(void) {
	static NSMutableDictionary *d; static dispatch_once_t o; dispatch_once(&o, ^{ d = rygLoadStateDict(@"grid_feed_follow_state"); });
	return d;
}

+ (BOOL)effectiveLiked:(RYGGridFeedPost *)post {
	NSNumber *o = post.mediaID.length ? rygLikeState()[post.mediaID] : nil;
	return o ? o.boolValue : post.hasLiked;
}
+ (BOOL)effectiveFollowing:(RYGGridFeedPost *)post {
	NSNumber *o = post.userPK.length ? rygFollowState()[post.userPK] : nil;
	return o ? o.boolValue : post.isFollowing;
}

- (void)reloadItem:(NSInteger)item {
	if (item < 0 || item >= (NSInteger)self.service.posts.count) return;
	@try { [self.grid reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:item inSection:0]]]; }
	@catch (__unused NSException *e) {}
}

- (void)toggleLikePost:(RYGGridFeedPost *)post item:(NSInteger)item {
	if (!post.mediaID.length) return;
	BOOL liked = [RYGHomeGridController effectiveLiked:post];
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *r, NSError *e){
		if ([r[@"status"] isEqualToString:@"ok"]) {
			rygLikeState()[post.mediaID] = @(!liked);
			rygSaveStateDict(@"grid_feed_like_state", rygLikeState());
			post.hasLiked = !liked;
			RYGNotifySuccess(RYG_NOTIF_GENERIC, (liked ? RYGLocalized(@"Unliked") : RYGLocalized(@"Liked")), nil);
			[weakSelf reloadItem:item];
		} else RYGNotifyError(RYG_NOTIF_GENERIC, RYGLocalized(@"Couldn't update like"), nil);
	};
	if (liked) [RYGInstagramAPI unlikeMediaID:post.mediaID completion:done];
	else [RYGInstagramAPI likeMediaID:post.mediaID completion:done];
}

- (void)toggleFollowPost:(RYGGridFeedPost *)post item:(NSInteger)item {
	if (!post.userPK.length) return;
	BOOL following = [RYGHomeGridController effectiveFollowing:post];
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *r, NSError *e){
		if ([r[@"status"] isEqualToString:@"ok"]) {
			rygFollowState()[post.userPK] = @(!following);
			rygSaveStateDict(@"grid_feed_follow_state", rygFollowState());
			post.isFollowing = !following;
			RYGNotifySuccess(RYG_NOTIF_GENERIC, (following ? RYGLocalized(@"Unfollowed") : RYGLocalized(@"Followed")), nil);
			[weakSelf reloadItem:item];
		} else RYGNotifyError(RYG_NOTIF_GENERIC, RYGLocalized(@"Couldn't update follow"), nil);
	};
	if (following) [RYGInstagramAPI unfollowUserPK:post.userPK completion:done];
	else [RYGInstagramAPI followUserPK:post.userPK completion:done];
}

- (void)sharePost:(RYGGridFeedPost *)post fromItem:(NSInteger)item {
	if (!post.code.length) return;
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/p/%@/", post.code]];
	UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	UICollectionViewCell *cell = [self.grid cellForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:0]];
	av.popoverPresentationController.sourceView = cell ?: self.grid;
	av.popoverPresentationController.sourceRect = cell ? cell.bounds : self.grid.bounds;
	[self.host presentViewController:av animated:YES completion:nil];
}

#pragma mark - Prefetch

- (void)collectionView:(UICollectionView *)cv prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
	CGFloat px = MAX(220.0, self.layout.itemSize.width * UIScreen.mainScreen.scale);
	for (NSIndexPath *ip in indexPaths) {
		if (ip.item >= (NSInteger)self.service.posts.count) continue;
		RYGGridFeedPost *p = self.service.posts[ip.item];
		if (p.thumbURLString.length)
			[RYGImageCache loadThumbnailFromURL:[NSURL URLWithString:p.thumbURLString] cacheKey:(p.pk.length ? p.pk : p.code) maxPixel:px completion:^(UIImage *img){}];
	}
}

- (void)applyItemSize {
	CGFloat W = self.grid.bounds.size.width;
	if (W <= 0) { UICollectionView *ig = [self igCollectionView]; W = ig.bounds.size.width; }
	if (W <= 0) return;
	self.columns = [RYGGridFeedInfo columns];
	CGFloat side = floor((W - kSpacing * (self.columns - 1)) / self.columns);
	CGFloat aspect = [RYGUtils getBoolPref:@"grid_feed_tall_cells"] ? 1.34 : 1.0;
	CGSize target = CGSizeMake(side, round(side * aspect));
	if (!CGSizeEqualToSize(self.layout.itemSize, target)) {
		self.layout.itemSize = target;
		[self.layout invalidateLayout];
	}
}

- (void)handlePinch:(UIPinchGestureRecognizer *)pinch {
	if (pinch.state != UIGestureRecognizerStateEnded) return;
	NSInteger c = self.columns;
	if (pinch.scale > 1.2) c--; else if (pinch.scale < 0.83) c++;
	c = MAX(2, MIN(6, c));
	if (c == self.columns) return;
	[RYGUtils setPref:@(c) forKey:@"grid_feed_columns"];
	[UIView animateWithDuration:0.22 animations:^{
		[self applyItemSize];
		[self.grid layoutIfNeeded];
	}];
}

#pragma mark - Loading

- (void)pulledRefresh {
	NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
	if (self.isRefreshing || (now - self.lastRefreshAt) < 1.5) { [self.refresh endRefreshing]; return; }
	self.isRefreshing = YES;
	self.lastRefreshAt = now;

	// Free the lock if the network hangs.
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (weakSelf.isRefreshing) { weakSelf.isRefreshing = NO; [weakSelf.refresh endRefreshing]; }
	});

	// Re-fetch fresh story data into the tray we already hold; recapturing would leave a gap.
	if (![RYGGridFeedInfo hideStories]) {
		[self refreshStoryData];
		if (self.storyTray) {
			[self applyStoriesMode];
			[self reassertStoryTrayAfterReload];
		} else {
			self.storyCaptureAttempts = 0;
			self.storyGaveUp = NO;
			self.pendingScrollTop = YES;
			[self tryCaptureLoop];
		}
	}

	// Reload the feed from the top. The service keeps current tiles on screen until the
	// fresh page lands, then swaps — no blank flash mid-refresh.
	[self.service refreshWithCompletion:^(NSArray *posts, NSError *err) {
		typeof(self) self = weakSelf;
		if (!self) return;
		self.isRefreshing = NO;
		self.lastRefreshAt = [NSProcessInfo processInfo].systemUptime;
		self.loadingMore = NO;
		self.showSkeleton = (self.service.posts.count == 0);
		self.didNukeFeed = NO;
		[self.grid reloadData];
		[self markGridReloaded];
		if (![RYGGridFeedInfo hideStories]) {
			// Only recapture when the tray went stale (IG swapped it); re-pinning a live one
			// avoids the flicker + scroll jump a full recapture causes.
			BOOL stale = !self.storyTray || self.storyTray.superview != self.grid || [self.storyTray numberOfItemsInSection:0] == 0;
			if (stale) {
				[self restoreStoryTray];
				self.storyCaptureAttempts = 0;
				self.storyGaveUp = NO;
				self.pendingScrollTop = YES;
				[self applyStoriesMode];
				[self tryCaptureLoop];
			} else {
				[self applyStoriesMode];
				[self recoverStoryTray];
				[self.grid setContentOffset:CGPointMake(0, -self.grid.adjustedContentInset.top) animated:NO];
			}
		} else {
			[self applyStoriesMode];
			[self.grid setContentOffset:CGPointMake(0, -self.grid.adjustedContentInset.top) animated:NO];
		}
		[self.refresh endRefreshing];
		[self maybeAutoFill];
	}];
}

// Same path IG's native pull uses: fetch into the view model, then reload the tray.
- (void)refreshStoryData {
	UIViewController *owner = self.storyOwnerVC;
	if (!owner) return;
	IGMainFeedViewModel *vm = nil;
	if ([owner respondsToSelector:@selector(viewModel)])
		vm = (IGMainFeedViewModel *)((id (*)(id, SEL))objc_msgSend)(owner, @selector(viewModel));
	long long reason = [vm respondsToSelector:@selector(lastFetchReasonForRefresh)] ? [vm lastFetchReasonForRefresh] : 0;
	if ([vm respondsToSelector:@selector(fetchDataOnStoryTrayWithMainFeedFetchReason:)]) [vm fetchDataOnStoryTrayWithMainFeedFetchReason:reason];
	if ([owner respondsToSelector:@selector(reloadStoryTray)]) ((void (*)(id, SEL))objc_msgSend)(owner, @selector(reloadStoryTray));
}

- (void)loadMore { [self loadMoreChained:0]; }

// A page can land entirely inside the cache and add nothing; keep advancing the cursor
// a few times until a page brings new posts, or the feed runs out.
- (void)loadMoreChained:(NSInteger)depth {
	if (self.showSkeleton || self.service.posts.count == 0) return;
	if (self.loadingMore || self.service.isLoading) return;
	if (!self.service.moreAvailable) return;
	self.loadingMore = YES;
	[self.footer startAnimating];
	NSInteger before = self.service.posts.count;
	__weak typeof(self) weakSelf = self;
	[self.service loadMoreWithCompletion:^(NSArray *newPosts, NSError *error) {
		typeof(self) self = weakSelf;
		if (!self) return;
		self.loadingMore = NO;
		[self applyGridDeltaFrom:before];
		NSInteger added = (NSInteger)self.service.posts.count - before;
		if (added == 0 && self.service.moreAvailable && depth < 8) { [self loadMoreChained:depth + 1]; return; }
		[self.footer stopAnimating];
		[self updateEndFooter];
		[self maybeAutoFill];
	}];
}

// Fill a couple screens so there's room to scroll; near-bottom paging continues from there.
- (void)maybeAutoFill {
	if (self.loadingMore || !self.service.moreAvailable) return;
	CGFloat content = self.grid.collectionViewLayout.collectionViewContentSize.height;
	if (content < self.grid.bounds.size.height * 2.5) [self loadMore];
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
	if (self.showSkeleton && self.service.posts.count == 0) return self.columns * 5;
	return self.service.posts.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	RYGGridFeedCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:ip];
	if (ip.item < (NSInteger)self.service.posts.count)
		[cell configureWithPost:self.service.posts[ip.item]];
	else
		[cell configureSkeleton];
	return cell;
}

- (void)collectionView:(UICollectionView *)cv willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)ip {
	if (ip.item >= (NSInteger)self.service.posts.count - self.columns * 4) [self loadMore];
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
	if (sv != self.grid) return;
	[self pinStoryTray];
	if (self.showSkeleton) return;
	if (self.endLabel && !self.endLabel.hidden) [self updateEndFooter];
	CGFloat distToBottom = sv.contentSize.height - (sv.contentOffset.y + sv.bounds.size.height);
	if (distToBottom < sv.bounds.size.height * 1.5) [self loadMore];
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	[cv deselectItemAtIndexPath:ip animated:NO];
	[self openPostAtItem:ip.item];
}

- (void)openPostAtItem:(NSInteger)item {
	if (item < 0 || item >= (NSInteger)self.service.posts.count) return;
	RYGGridFeedPost *post = self.service.posts[item];
	if (post.pk.length)
		[RYGURLOpener openURLString:[NSString stringWithFormat:@"instagram://media?id=%@", post.pk]];
	else if (post.code.length)
		[RYGURLOpener openURLString:[NSString stringWithFormat:@"https://www.instagram.com/p/%@/", post.code]];
}

@end
