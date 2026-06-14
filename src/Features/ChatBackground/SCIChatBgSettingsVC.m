#import "SCIChatBgSettingsVC.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgImporter.h"
#import "SCIChatBgPerImageSheet.h"
#import "SCIChatBgChatsListViewController.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"

static NSString *const kLibraryRowCell = @"SCIChatBgLibraryRow";
static NSString *const kAssetCell = @"SCIChatBgAsset";
static NSString *const kAddCell = @"SCIChatBgAdd";

@interface SCIChatBgSettingsVC () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, weak) UICollectionView *libraryCollection;
@property (nonatomic, copy) NSArray<NSString *> *libraryAssets;
@end

@interface SCIChatBgLibraryCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *iconView;
- (void)configureWithAsset:(NSString *)asset;
- (void)configureAsAdd;
@end

@implementation SCIChatBgLibraryCell

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
	self.iconView.hidden = NO;
	self.contentView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.16];
	self.contentView.layer.borderWidth = 1.5;
	self.contentView.layer.borderColor = [UIColor colorWithWhite:0.65 alpha:0.35].CGColor;
}

- (void)configureWithAsset:(NSString *)asset {
	self.iconView.hidden = YES;
	self.contentView.backgroundColor = UIColor.blackColor;

	NSURL *url = [[SCIChatBackgroundManager shared] urlForRelativeAsset:asset];
	self.imageView.image = url ? [UIImage imageWithContentsOfFile:url.path] : nil;
}

@end

@interface SCIChatBgLibraryRowCell : UITableViewCell
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation SCIChatBgLibraryRowCell

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
		[_collectionView registerClass:SCIChatBgLibraryCell.class forCellWithReuseIdentifier:kAssetCell];
		[_collectionView registerClass:SCIChatBgLibraryCell.class forCellWithReuseIdentifier:kAddCell];
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

@implementation SCIChatBgSettingsVC

- (instancetype)init {
	if ((self = [super initWithTitle:SCILocalized(@"Custom Chat Background")])) {
		_libraryAssets = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	SCIUIKit26ConfigureViewController(self);
	SCIUIKit26ConfigureTableView(self.tableView);

	[self.tableView registerClass:SCIChatBgLibraryRowCell.class forCellReuseIdentifier:kLibraryRowCell];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reload)
												 name:SCIChatBackgroundDidChangeNotification
											   object:nil];

	[self reload];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload {
	self.libraryAssets = [[SCIChatBackgroundManager shared] libraryAssets] ?: @[];
	[self rebuildSections];
	[self.libraryCollection reloadData];
}

#pragma mark - Sections

- (void)rebuildSections {
	__weak typeof(self) weak = self;

	SCISetting *enabled = [SCISetting switchCellWithTitle:SCILocalized(@"Enable custom backgrounds")
												 subtitle:SCILocalized(@"Adds your own image backgrounds to Instagram chats")
													value:^BOOL{
		return [[SCIChatBackgroundManager shared] isEnabled];
	} action:^(BOOL on) {
		[weak setEnabled:on];
	}];

	SCISetting *pickDefault = [SCISetting buttonCellWithTitle:@"" subtitle:@"" icon:nil action:^{
		[weak importBackgroundSetDefault:YES];
	}];
	pickDefault.dynamicTitle = ^{
		return [[SCIChatBackgroundManager shared] defaultAsset].length ? SCILocalized(@"Change default") : SCILocalized(@"Pick default");
	};
	pickDefault.dynamicSubtitle = ^{
		return [[SCIChatBackgroundManager shared] defaultAsset].length ? SCILocalized(@"Replace the default background image") : SCILocalized(@"Choose an image used when no chat override exists");
	};

	SCISetting *clearDefault = [SCISetting buttonCellWithTitle:SCILocalized(@"Clear default") subtitle:SCILocalized(@"Remove the global fallback background") icon:nil action:^{
		[[SCIChatBackgroundManager shared] setDefaultAsset:nil];
	}];
	clearDefault.titleColor = UIColor.systemRedColor;
	clearDefault.hidesDisclosureIndicator = YES;

	SCISetting *library = [SCISetting customCellWithHeight:128 provider:^UITableViewCell *(UITableView *tableView, NSIndexPath *indexPath) {
		SCIChatBgLibraryRowCell *cell = [tableView dequeueReusableCellWithIdentifier:kLibraryRowCell forIndexPath:indexPath];
	SCIUIKit26ConfigureTableCell(cell);
		cell.collectionView.dataSource = weak;
		cell.collectionView.delegate = weak;
		weak.libraryCollection = cell.collectionView;
		[cell.collectionView reloadData];
		return cell;
	}];

	SCISetting *chats = [SCISetting buttonCellWithTitle:@"" subtitle:SCILocalized(@"View and manage chats with custom backgrounds") icon:nil action:^{
		[weak.navigationController pushViewController:[SCIChatBgChatsListViewController new] animated:YES];
	}];
	chats.dynamicTitle = ^{
		NSInteger count = [[SCIChatBackgroundManager shared] allThreadAssets].count;
		return count ? [NSString stringWithFormat:SCILocalized(@"Browse chats (%ld)"), (long)count] : SCILocalized(@"Browse chats");
	};

	SCISetting *reset = [SCISetting buttonCellWithTitle:SCILocalized(@"Reset all backgrounds") subtitle:SCILocalized(@"Delete library images, default background, and chat overrides") icon:nil action:^{
		[weak confirmReset];
	}];
	reset.titleColor = UIColor.systemRedColor;
	reset.hidesDisclosureIndicator = YES;

	[self applySettingSections:@[
		[SCISettingsViewController sectionWithHeader:nil
											 footer:SCILocalized(@"After enabling, open any chat, tap the theme button, then tap the photo icon at the top-right.")
											   rows:@[enabled]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Default background")
											 footer:SCILocalized(@"Used only when a chat does not have its own custom background.")
											   rows:@[pickDefault, clearDefault]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Library")
											 footer:SCILocalized(@"Tap plus to add. Tap a background to edit, set as default, or delete.")
											   rows:@[library]],
		[SCISettingsViewController sectionWithHeader:SCILocalized(@"Chats")
											 footer:nil
											   rows:@[chats]],
		[SCISettingsViewController sectionWithHeader:nil
											 footer:nil
											   rows:@[reset]]
	]];
}

#pragma mark - Actions

- (void)setEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:SCIPrefChatBackgroundEnabled];
	[[NSNotificationCenter defaultCenter] postNotificationName:SCIChatBackgroundDidChangeNotification object:nil];

	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Restart required")
															   message:SCILocalized(@"Quit and reopen Instagram for the change to take effect.")
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)openImageSettings:(NSString *)asset {
	if (asset.length) [SCIPopupChrome presentVC:[[SCIChatBgPerImageSheet alloc] initWithAsset:asset] from:self];
}

- (void)importBackgroundSetDefault:(BOOL)setDefault {
	[SCIChatBgImporter presentFrom:self completion:^(NSString *rel) {
		if (!rel.length) return;
		if (setDefault) [[SCIChatBackgroundManager shared] setDefaultAsset:rel];
		[self openImageSettings:rel];
	}];
}

- (void)confirmReset {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Reset all backgrounds?")
															   message:SCILocalized(@"Library, default, and per-chat overrides will be deleted.")
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[[SCIChatBackgroundManager shared] resetAll];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)showAssetMenu:(NSString *)asset source:(UICollectionViewCell *)cell {
	UIAlertController *s = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

	[s addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Edit image settings") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[self openImageSettings:asset];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Set as default") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[[SCIChatBackgroundManager shared] setDefaultAsset:asset];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[[SCIChatBackgroundManager shared] deleteLibraryAsset:asset];
	}]];

	[s addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

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
	SCIChatBgLibraryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:isAdd ? kAddCell : kAssetCell forIndexPath:indexPath];
	SCIStyleCollectionCellForGlass(cell);

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
