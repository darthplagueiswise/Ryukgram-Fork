#import "SCIChatBgThreadPickerVC.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgImporter.h"
#import "SCIChatBgPerImageSheet.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>

@interface SCIChatBgThreadPickerVC () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy, nullable) NSString *threadID;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<NSString *> *assets;
@end

static NSString *const kCellID = @"SCIChatBgCell";
static NSString *const kAddCellID = @"SCIChatBgAddCell";
static NSString *const kDefaultCellID = @"SCIChatBgDefaultCell";

static NSString *sActiveThreadID = nil;

@implementation SCIChatBgThreadPickerVC

+ (NSString *)activeThreadID { return sActiveThreadID; }
+ (void)setActiveThreadID:(NSString *)threadID { sActiveThreadID = [threadID copy]; }

- (instancetype)initWithThreadID:(NSString *)threadID {
	if ((self = [super init])) {
		_threadID = [threadID copy];
		_assets = @[];
		self.title = threadID.length ? SCILocalized(@"This Chat Background") : SCILocalized(@"Default background");
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.navigationItem.prompt = SCILocalized(@"Tap to apply · hold to edit");

	UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
	layout.minimumInteritemSpacing = 12;
	layout.minimumLineSpacing = 14;
	layout.sectionInset = UIEdgeInsetsMake(20, 20, 20, 20);

	_collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
	_collectionView.dataSource = self;
	_collectionView.delegate = self;
	_collectionView.backgroundColor = [SCIPopupChrome backgroundColor];
	_collectionView.alwaysBounceVertical = YES;
	_collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	[_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:kCellID];
	[_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:kAddCellID];
	[_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:kDefaultCellID];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
	[_collectionView addGestureRecognizer:hold];

	[self.view addSubview:_collectionView];
	[NSLayoutConstraint activateConstraints:@[
		[_collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reload)
												 name:SCIChatBackgroundDidChangeNotification
											   object:nil];
	[self reload];
}

- (void)reload {
	self.assets = [[SCIChatBackgroundManager shared] libraryAssets];
	[self.collectionView reloadData];
}

#pragma mark - DataSource

// Layout: index 0 = clear-override tile, 1..N = library, last = add tile.
- (NSInteger)collectionView:(__unused UICollectionView *)collectionView numberOfItemsInSection:(__unused NSInteger)section {
	return 1 + (NSInteger)self.assets.count + 1;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	NSInteger i = ip.item;
	NSInteger addIndex = (NSInteger)self.assets.count + 1;

	if (i == 0) {
		UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kDefaultCellID forIndexPath:ip];
		[self configureDefaultCell:cell];
		return cell;
	} else if (i == addIndex) {
		UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kAddCellID forIndexPath:ip];
		[self configureAddCell:cell];
		return cell;
	} else {
		NSString *asset = self.assets[i - 1];
		UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:ip];
		[self configureLibraryCell:cell withAsset:asset];
		return cell;
	}
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(__unused UICollectionViewLayout *)layout sizeForItemAtIndexPath:(__unused NSIndexPath *)ip {
	CGFloat avail = cv.bounds.size.width - 40 - 24; // insets + 3 gaps
	CGFloat w = floor(avail / 3.0);
	return CGSizeMake(w, w * 1.45);
}

- (void)collectionView:(__unused UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	NSInteger i = ip.item;
	NSInteger addIndex = (NSInteger)self.assets.count + 1;

	if (i == 0) {
		if (self.threadID.length) [[SCIChatBackgroundManager shared] clearAssetForThreadID:self.threadID];
		else					  [[SCIChatBackgroundManager shared] setDefaultAsset:nil];
		[self dismiss];
		return;
	}
	if (i == addIndex) {
		NSString *capturedTid = self.threadID;
		[SCIChatBgImporter presentFrom:self completion:^(NSString * _Nullable rel) {
			if (!rel.length) return;
			if (capturedTid.length) [[SCIChatBackgroundManager shared] setAsset:rel forThreadID:capturedTid];
			else					[[SCIChatBackgroundManager shared] setDefaultAsset:rel];
			// Sequence dismisses (self → IG picker) before presenting the
			// settings sheet — concurrent dismiss + present drops the sheet.
			UIViewController *igPicker = self.presentingViewController;
			UIViewController *chat = igPicker.presentingViewController ?: igPicker;
			[self dismissViewControllerAnimated:YES completion:^{
				void (^presentSheet)(void) = ^{
					SCIChatBgPerImageSheet *editVC = [[SCIChatBgPerImageSheet alloc] initWithAsset:rel];
					[SCIPopupChrome presentVC:editVC from:chat];
				};
				if (igPicker && igPicker != chat) {
					[igPicker dismissViewControllerAnimated:YES completion:presentSheet];
				} else {
					presentSheet();
				}
			}];
		}];
		return;
	}
	NSString *asset = self.assets[i - 1];
	if (self.threadID.length) [[SCIChatBackgroundManager shared] setAsset:asset forThreadID:self.threadID];
	else					  [[SCIChatBackgroundManager shared] setDefaultAsset:asset];
	[self dismiss];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateBegan) return;

	NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:[gr locationInView:self.collectionView]];
	NSInteger addIndex = (NSInteger)self.assets.count + 1;
	if (!ip || ip.item <= 0 || ip.item >= addIndex) return;

	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];

	NSString *asset = self.assets[ip.item - 1];
	[SCIPopupChrome presentVC:[[SCIChatBgPerImageSheet alloc] initWithAsset:asset] from:self];
}

- (void)dismiss {
	void (^cb)(void) = objc_getAssociatedObject(self, @selector(sci_dismissCallback));
	[self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(); }];
}

#pragma mark - Cell rendering

- (UIView *)tileViewIn:(UICollectionViewCell *)cell {
	UIView *tile = [cell.contentView viewWithTag:101];
	if (tile) return tile;
	tile = [UIView new];
	tile.tag = 101;
	tile.layer.cornerRadius = 14;
	tile.layer.cornerCurve = kCACornerCurveContinuous;
	tile.clipsToBounds = YES;
	tile.translatesAutoresizingMaskIntoConstraints = NO;
	[cell.contentView addSubview:tile];

	UILabel *label = [UILabel new];
	label.tag = 102;
	label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
	label.textColor = [UIColor secondaryLabelColor];
	label.textAlignment = NSTextAlignmentCenter;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[cell.contentView addSubview:label];

	[NSLayoutConstraint activateConstraints:@[
		[tile.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
		[tile.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
		[tile.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
		[tile.bottomAnchor constraintEqualToAnchor:label.topAnchor constant:-6],
		[label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
		[label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
		[label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
	]];
	return tile;
}

- (UILabel *)labelIn:(UICollectionViewCell *)cell { return (UILabel *)[cell.contentView viewWithTag:102]; }

- (void)clearTile:(UIView *)tile {
	for (UIView *sub in [tile.subviews copy]) [sub removeFromSuperview];
}

- (void)configureLibraryCell:(UICollectionViewCell *)cell withAsset:(NSString *)asset {
	UIView *tile = [self tileViewIn:cell];
	[self clearTile:tile];
	tile.backgroundColor = [UIColor blackColor];

	UIImageView *iv = [UIImageView new];
	iv.contentMode = UIViewContentModeScaleAspectFill;
	iv.clipsToBounds = YES;
	iv.translatesAutoresizingMaskIntoConstraints = NO;
	NSURL *url = [[SCIChatBackgroundManager shared] urlForRelativeAsset:asset];
	if (url) iv.image = [UIImage imageWithContentsOfFile:url.path];
	[tile addSubview:iv];
	[NSLayoutConstraint activateConstraints:@[
		[iv.topAnchor constraintEqualToAnchor:tile.topAnchor],
		[iv.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
		[iv.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
		[iv.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor],
	]];

	BOOL selected = NO;
	if (self.threadID.length) {
		selected = [[[SCIChatBackgroundManager shared] assetForThreadID:self.threadID] isEqualToString:asset];
	} else {
		selected = [[[SCIChatBackgroundManager shared] defaultAsset] isEqualToString:asset];
	}
	tile.layer.borderWidth = selected ? 3.0 : 0.0;
	tile.layer.borderColor = [UIColor systemBlueColor].CGColor;

	[self labelIn:cell].text = selected ? SCILocalized(@"Selected") : @"";
}

- (void)configureAddCell:(UICollectionViewCell *)cell {
	UIView *tile = [self tileViewIn:cell];
	[self clearTile:tile];
	tile.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.18];
	tile.layer.borderWidth = 1.5;
	tile.layer.borderColor = [UIColor colorWithWhite:0.6 alpha:0.4].CGColor;

	UIImageView *plus = [UIImageView new];
	plus.image = [UIImage systemImageNamed:@"plus"];
	plus.tintColor = [UIColor labelColor];
	plus.contentMode = UIViewContentModeScaleAspectFit;
	plus.translatesAutoresizingMaskIntoConstraints = NO;
	[tile addSubview:plus];
	[NSLayoutConstraint activateConstraints:@[
		[plus.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
		[plus.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
		[plus.widthAnchor constraintEqualToConstant:30],
		[plus.heightAnchor constraintEqualToConstant:30],
	]];
	[self labelIn:cell].text = SCILocalized(@"Add");
}

- (void)configureDefaultCell:(UICollectionViewCell *)cell {
	UIView *tile = [self tileViewIn:cell];
	[self clearTile:tile];
	tile.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.18];
	tile.layer.borderWidth = 1.5;
	tile.layer.borderColor = [UIColor colorWithWhite:0.6 alpha:0.4].CGColor;

	UIImageView *icon = [UIImageView new];
	icon.image = [UIImage systemImageNamed:@"slash.circle"];
	icon.tintColor = [UIColor labelColor];
	icon.contentMode = UIViewContentModeScaleAspectFit;
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	[tile addSubview:icon];
	[NSLayoutConstraint activateConstraints:@[
		[icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:30],
		[icon.heightAnchor constraintEqualToConstant:30],
	]];
	[self labelIn:cell].text = self.threadID.length ? SCILocalized(@"No Custom") : SCILocalized(@"None");
}

@end
