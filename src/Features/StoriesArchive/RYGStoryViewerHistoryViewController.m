#import "RYGStoryViewerHistoryViewController.h"
#import "RYGStoryAudienceStats.h"
#import "RYGStoriesArchiveStore.h"
#import "RYGStoriesArchiveCell.h"
#import "RYGArchivedStory.h"
#import "RYGArchivedStoryViewer.h"
#import "RYGStoryMediaViewer.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../RYGImageCache.h"
#import "../../RYGProfileOpener.h"
#import "../StoriesAndMessages/RYGStoryViewerPins.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Settings/RYGSymbol.h"
#import "../../Utils.h"

static NSString *const kCell = @"RYGStoriesArchiveCell";

@interface RYGStoryViewerHistoryViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) RYGAudienceMember *member;
@property (nonatomic, strong) RYGStoriesArchiveStore *store;
@property (nonatomic, copy) NSArray<RYGArchivedStoryViewer *> *rows;
@property (nonatomic, copy) NSArray<RYGArchivedStory *> *stories;
@property (nonatomic, assign) NSInteger reactionCount;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation RYGStoryViewerHistoryViewController

+ (void)showMember:(RYGAudienceMember *)member from:(UIViewController *)presenter {
	RYGStoryViewerHistoryViewController *vc = [RYGStoryViewerHistoryViewController new];
	vc.member = member;
	if (presenter.navigationController) [presenter.navigationController pushViewController:vc animated:YES];
	else [RYGPopupChrome presentVC:vc from:presenter];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.member.username.length ? self.member.username : RYGLocalized(@"Viewer");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.store = [RYGStoriesArchiveStore storeForCurrentUser];

	[self loadStories];
	[self setupCollectionView];

	[self updateMenu];
}

- (BOOL)pinsEnabled { return [RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]; }

- (void)updateMenu {
	__weak typeof(self) w = self;
	UIAction *profile = [UIAction actionWithTitle:RYGLocalized(@"Open profile")
	                                        image:[RYGSymbol symbolWithIGName:@"ig_icon_user_follow_outline_24" fallback:@"person.crop.circle"].image
	                                   identifier:nil handler:^(UIAction *a) {
		[RYGProfileOpener openProfileForPK:w.member.pk username:w.member.username from:w];
	}];
	NSMutableArray<UIAction *> *actions = [NSMutableArray array];
	if ([self pinsEnabled]) {
		BOOL isPinned = self.member.pk.length && [RYGStoryViewerPins isPinned:self.member.pk];
		[actions addObject:[UIAction actionWithTitle:isPinned ? RYGLocalized(@"Unpin") : RYGLocalized(@"Pin")
		                                       image:[UIImage systemImageNamed:isPinned ? @"pin.slash" : @"pin"]
		                                  identifier:nil handler:^(UIAction *a) { [w togglePin]; }]];
	}
	[actions addObject:profile];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[RYGSymbol symbolWithIGName:@"fb_ic_dots_3_horizontal_filled_24" fallback:@"ellipsis" color:UIColor.labelColor size:20].image
		         menu:[UIMenu menuWithTitle:@"" children:actions]];
}

- (void)togglePin {
	if (!self.member.pk.length) return;
	BOOL nowPinned = [RYGStoryViewerPins togglePK:self.member.pk entry:@{
		@"pk": self.member.pk, @"username": self.member.username ?: @"",
		@"fullName": self.member.fullName ?: @"", @"avatarURL": self.member.profilePicURL ?: @""
	}];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	RYGNotifySuccess(RYG_NOTIF_PIN_STORY_VIEWER,
		nowPinned ? RYGLocalized(@"Viewer pinned") : RYGLocalized(@"Viewer unpinned"),
		self.member.username.length ? [@"@" stringByAppendingString:self.member.username] : nil);
	[self updateMenu];
}

- (void)loadStories {
	NSMutableArray<RYGArchivedStoryViewer *> *rows = [NSMutableArray array];
	NSMutableArray<RYGArchivedStory *> *stories = [NSMutableArray array];
	NSInteger reactions = 0;
	for (RYGArchivedStoryViewer *v in [self.store viewerRowsForUserPK:self.member.pk]) {
		if (!v.story) continue;
		[rows addObject:v];
		[stories addObject:v.story];
		if (v.liked || v.reactionEmoji.length) reactions++;
	}
	self.rows = rows;
	self.stories = stories;
	self.reactionCount = reactions;
}

- (void)setupCollectionView {
	UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
		NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:
			[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0 / 3.0]
			                                heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]]];
		item.contentInsets = NSDirectionalEdgeInsetsMake(3, 3, 3, 3);
		NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:
			[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
			                                heightDimension:[NSCollectionLayoutDimension fractionalWidthDimension:16.0 / 9.0 / 3.0]]
			subitem:item count:3];
		NSCollectionLayoutSection *s = [NSCollectionLayoutSection sectionWithGroup:group];
		s.contentInsets = NSDirectionalEdgeInsetsMake(4, 9, 20, 9);
		return s;
	}];

	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.backgroundColor = UIColor.clearColor;
	self.collectionView.alwaysBounceVertical = YES;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	[self.collectionView registerClass:RYGStoriesArchiveCell.class forCellWithReuseIdentifier:kCell];
	[self.view addSubview:self.collectionView];

	UIView *header = [self buildHeader];
	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

- (UIView *)buildHeader {
	UIImageView *avatar = [UIImageView new];
	avatar.contentMode = UIViewContentModeScaleAspectFill;
	avatar.clipsToBounds = YES;
	avatar.layer.cornerRadius = 28;
	avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
	avatar.tintColor = UIColor.systemGray3Color;
	avatar.translatesAutoresizingMaskIntoConstraints = NO;
	[avatar.widthAnchor constraintEqualToConstant:56].active = YES;
	[avatar.heightAnchor constraintEqualToConstant:56].active = YES;
	if (self.member.profilePicURL.length)
		[RYGImageCache loadImageFromURL:[NSURL URLWithString:self.member.profilePicURL] cacheKey:self.member.pk completion:^(UIImage *image) {
			if (image) avatar.image = image;
		}];

	UILabel *name = [UILabel new];
	name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	name.textColor = UIColor.labelColor;
	name.text = self.member.fullName.length ? self.member.fullName : self.member.username;

	UILabel *summary = [UILabel new];
	summary.font = [UIFont systemFontOfSize:13];
	summary.textColor = UIColor.secondaryLabelColor;
	summary.numberOfLines = 2;
	summary.text = [self summaryText];

	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, summary]];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 3;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[avatar, text]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 14;
	row.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *card = [UIView new];
	card.backgroundColor = UIColor.secondarySystemBackgroundColor;
	card.layer.cornerRadius = 18;
	card.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:row];
	[self.view addSubview:card];
	[NSLayoutConstraint activateConstraints:@[
		[card.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
		[card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
		[card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
		[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
		[row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
		[row.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
		[row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
	]];
	return card;
}

- (NSString *)summaryText {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	[parts addObject:[NSString stringWithFormat:RYGLocalized(@"Watched %ld stories"), (long)self.stories.count]];
	if (self.reactionCount)
		[parts addObject:self.reactionCount == 1 ? RYGLocalized(@"1 reaction")
		                                         : [NSString stringWithFormat:RYGLocalized(@"%ld reactions"), (long)self.reactionCount]];
	NSString *relation = nil;
	if (self.member.following && self.member.followedBy) relation = RYGLocalized(@"Mutual");
	else if (self.member.followedBy) relation = RYGLocalized(@"Follows you");
	else if (self.member.following) relation = RYGLocalized(@"Following");
	if (relation) [parts addObject:relation];
	return [parts componentsJoinedByString:@" · "];
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return self.stories.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	RYGStoriesArchiveCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCell forIndexPath:ip];
	RYGArchivedStory *s = self.stories[ip.item];
	RYGArchivedStoryViewer *row = self.rows[ip.item];
	NSString *thumb = [self.store absoluteThumbPathForStory:s] ?: [self.store absoluteMediaPathForStory:s];
	[cell configureWithThumbnailPath:thumb isVideo:s.mediaType == 2 viewerCount:s.viewersCount likeCount:s.likesCount];
	[cell configureDate:s.takenAt];
	[cell configureReaction:row.reactionEmoji liked:row.liked];
	return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	[cv deselectItemAtIndexPath:ip animated:NO];
	[RYGStoryMediaViewer presentStories:self.stories store:self.store startIndex:ip.item from:self];
}

@end
