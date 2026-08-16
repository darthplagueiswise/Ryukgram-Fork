#import "RYGChatBgSettingsVC.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgImporter.h"
#import "RYGChatBgPerImageSheet.h"
#import "RYGChatBgEditor.h"
#import "RYGChatBgChatsListViewController.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"

static NSString *const kLibraryRowCell = @"RYGChatBgLibraryRow";
static NSString *const kAssetCell = @"RYGChatBgAsset";
static NSString *const kAddCell = @"RYGChatBgAdd";

@interface RYGChatBgSettingsVC () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, weak) UICollectionView *libraryCollection;
@property (nonatomic, copy) NSArray<NSString *> *libraryAssets;
@end

@interface RYGChatBgLibraryCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *iconView;
- (void)configureWithAsset:(NSString *)asset;
- (void)configureAsAdd;
@end

@implementation RYGChatBgLibraryCell

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.contentView.layer.cornerRadius = 14;
		self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
		self.contentView.clipsToBounds = YES;

		_imageView = [UIImageView new];
		_imageView.contentMode = UIViewContentModeScaleAspectFill;
		_imageView.clipsToBounds = YES;
		_imageView.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:_imageView];

		_iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus"]];
		_iconView.tintColor = UIColor.labelColor;
		_iconView.contentMode = UIViewContentModeScaleAspectFit;
		_iconView.translatesAutoresizingMaskIntoConstraints = NO;
		[self.contentView addSubview:_iconView];

		[NSLayoutConstraint activateConstraints:@[
			[_imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[_imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[_imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[_imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
			[_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[_iconView.widthAnchor constraintEqualToConstant:30],
			[_iconView.heightAnchor constraintEqualToConstant:30]
		]];
	}
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.imageView.image = nil;
	self.iconView.hidden = YES;
	self.contentView.backgroundColor = UIColor.blackColor;
	self.contentView.layer.borderWidth = 0;
	self.contentView.layer.borderColor = nil;
}

- (void)configureAsAdd {
	self.imageView.image = nil;
	self.iconView.image = [UIImage systemImageNamed:@"plus"];
	self.iconView.tintColor = UIColor.labelColor;
	self.iconView.hidden = NO;
	self.contentView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.16];
	self.contentView.layer.borderWidth = 1.5;
	self.contentView.layer.borderColor = [UIColor colorWithWhite:0.65 alpha:0.35].CGColor;
}

- (void)configureWithAsset:(NSString *)asset {
	self.contentView.backgroundColor = UIColor.blackColor;
	self.imageView.image = [[RYGChatBackgroundManager shared] imageForAsset:asset];

	BOOL video = [RYGChatBackgroundManager isVideoAsset:asset];
	self.iconView.hidden = !video;
	if (video) {
		self.iconView.image = [UIImage systemImageNamed:@"play.circle.fill"];
		self.iconView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
	}
}

@end

@interface RYGChatBgLibraryRowCell : UITableViewCell
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation RYGChatBgLibraryRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = UIColor.clearColor;
		self.contentView.backgroundColor = UIColor.clearColor;

		UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
		layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
		layout.minimumLineSpacing = 10;
		layout.minimumInteritemSpacing = 10;
		layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);

		_collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
		_collectionView.backgroundColor = UIColor.clearColor;
		_collectionView.showsHorizontalScrollIndicator = NO;
		_collectionView.translatesAutoresizingMaskIntoConstraints = NO;
		[_collectionView registerClass:RYGChatBgLibraryCell.class forCellWithReuseIdentifier:kAssetCell];
		[_collectionView registerClass:RYGChatBgLibraryCell.class forCellWithReuseIdentifier:kAddCell];
		[self.contentView addSubview:_collectionView];

		[NSLayoutConstraint activateConstraints:@[
			[_collectionView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
			[_collectionView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[_collectionView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[_collectionView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
			[_collectionView.heightAnchor constraintEqualToConstant:118]
		]];
	}
	return self;
}

@end

@implementation RYGChatBgSettingsVC

- (instancetype)init {
	if ((self = [super initWithTitle:RYGLocalized(@"Custom Chat Background")])) {
		_libraryAssets = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	[self.tableView registerClass:RYGChatBgLibraryRowCell.class forCellReuseIdentifier:kLibraryRowCell];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reload)
												 name:RYGChatBackgroundDidChangeNotification
											   object:nil];

	[self reload];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload {
	self.libraryAssets = [[RYGChatBackgroundManager shared] libraryAssets] ?: @[];
	[self rebuildSections];
	[self.libraryCollection reloadData];
}

#pragma mark - Sections

- (void)rebuildSections {
	__weak typeof(self) weak = self;

	RYGSetting *enabled = [RYGSetting switchCellWithTitle:RYGLocalized(@"Enable custom backgrounds")
												 subtitle:RYGLocalized(@"Adds your own image backgrounds to Instagram chats")
													value:^BOOL{
		return [[RYGChatBackgroundManager shared] isEnabled];
	} action:^(BOOL on) {
		[weak setEnabled:on];
	}];

	RYGSetting *pickDefault = [RYGSetting buttonCellWithTitle:@"" subtitle:@"" icon:nil action:^{
		[weak importBackgroundSetDefault:YES];
	}];
	pickDefault.dynamicTitle = ^{
		return [[RYGChatBackgroundManager shared] defaultAsset].length ? RYGLocalized(@"Change default") : RYGLocalized(@"Pick default");
	};
	pickDefault.dynamicSubtitle = ^{
		return [[RYGChatBackgroundManager shared] defaultAsset].length ? RYGLocalized(@"Replace the default background image") : RYGLocalized(@"Choose an image used when no chat override exists");
	};

	RYGSetting *clearDefault = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Clear default") subtitle:RYGLocalized(@"Remove the global fallback background") icon:nil action:^{
		[[RYGChatBackgroundManager shared] setDefaultAsset:nil];
	}];
	clearDefault.titleColor = UIColor.systemRedColor;
	clearDefault.hidesDisclosureIndicator = YES;

	RYGSetting *library = [RYGSetting customCellWithHeight:128 provider:^UITableViewCell *(UITableView *tableView, NSIndexPath *indexPath) {
		RYGChatBgLibraryRowCell *cell = [tableView dequeueReusableCellWithIdentifier:kLibraryRowCell forIndexPath:indexPath];
		cell.collectionView.dataSource = weak;
		cell.collectionView.delegate = weak;
		weak.libraryCollection = cell.collectionView;
		[cell.collectionView reloadData];
		return cell;
	}];

	RYGSetting *chats = [RYGSetting buttonCellWithTitle:@"" subtitle:RYGLocalized(@"View and manage chats with custom backgrounds") icon:nil action:^{
		[weak.navigationController pushViewController:[RYGChatBgChatsListViewController new] animated:YES];
	}];
	chats.dynamicTitle = ^{
		NSInteger count = [[RYGChatBackgroundManager shared] allThreadAssets].count;
		return count ? [NSString stringWithFormat:RYGLocalized(@"Browse chats (%ld)"), (long)count] : RYGLocalized(@"Browse chats");
	};

	RYGSetting *reset = [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
												  color:UIColor.systemRedColor
												 action:^{ [weak confirmReset]; }];

	[self applySettingSections:@[
		[RYGSettingsViewController sectionWithHeader:nil
											 footer:RYGLocalized(@"After enabling, open any chat, tap the theme button, then tap the photo icon at the top-right.")
											   rows:@[enabled]],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Default background")
											 footer:RYGLocalized(@"Used only when a chat does not have its own custom background.")
											   rows:@[pickDefault, clearDefault]],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Library")
											 footer:RYGLocalized(@"Tap plus to add. Tap a background to edit, set as default, or delete.")
											   rows:@[library]],
		[RYGSettingsViewController sectionWithHeader:RYGLocalized(@"Chats")
											 footer:nil
											   rows:@[chats]],
		[RYGSettingsViewController sectionWithHeader:nil
											 footer:nil
											   rows:@[reset]]
	]];
}

#pragma mark - Actions

- (void)setEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:RYGPrefChatBackgroundEnabled];
	[[NSNotificationCenter defaultCenter] postNotificationName:RYGChatBackgroundDidChangeNotification object:nil];

	UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Restart required")
															   message:RYGLocalized(@"Quit and reopen Instagram for the change to take effect.")
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)openImageSettings:(NSString *)asset {
	if (asset.length) [RYGPopupChrome presentVC:[[RYGChatBgPerImageSheet alloc] initWithAsset:asset] from:self];
}

- (void)importBackgroundSetDefault:(BOOL)setDefault {
	[RYGChatBgImporter presentFrom:self completion:^(NSString *rel) {
		if (!rel.length) return;
		if (setDefault) [[RYGChatBackgroundManager shared] setDefaultAsset:rel];
		[self openImageSettings:rel];
	}];
}

- (void)confirmReset {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
															   message:RYGLocalized(@"Library, default, and per-chat overrides will be deleted.")
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[[RYGChatBackgroundManager shared] resetAll];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)showAssetMenu:(NSString *)asset source:(UICollectionViewCell *)cell {
	UIAlertController *s = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

	BOOL video = [RYGChatBackgroundManager isVideoAsset:asset];

	[s addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Adjust settings") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[self openImageSettings:asset];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:video ? RYGLocalized(@"Crop & trim") : RYGLocalized(@"Crop & resize") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[RYGChatBgEditor reEditAsset:asset from:self completion:^(NSString *newRel) {
			if (newRel) [[RYGChatBackgroundManager shared] replaceAsset:asset withAsset:newRel];
		}];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Set as default") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[[RYGChatBackgroundManager shared] setDefaultAsset:asset];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[[RYGChatBackgroundManager shared] deleteLibraryAsset:asset];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	s.popoverPresentationController.sourceView = cell ?: self.view;
	s.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:s animated:YES completion:nil];
}

#pragma mark - Collection

- (NSInteger)collectionView:(__unused UICollectionView *)collectionView numberOfItemsInSection:(__unused NSInteger)section {
	return self.libraryAssets.count + 1;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	BOOL isAdd = indexPath.item == (NSInteger)self.libraryAssets.count;
	RYGChatBgLibraryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:isAdd ? kAddCell : kAssetCell forIndexPath:indexPath];

	isAdd ? [cell configureAsAdd] : [cell configureWithAsset:self.libraryAssets[indexPath.item]];
	return cell;
}

- (CGSize)collectionView:(__unused UICollectionView *)collectionView layout:(__unused UICollectionViewLayout *)layout sizeForItemAtIndexPath:(__unused NSIndexPath *)indexPath {
	return CGSizeMake(82.0, 118.0);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.item == (NSInteger)self.libraryAssets.count) {
		[self importBackgroundSetDefault:NO];
		return;
	}

	[self showAssetMenu:self.libraryAssets[indexPath.item] source:[collectionView cellForItemAtIndexPath:indexPath]];
}

@end