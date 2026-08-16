#import "RYGGallerySortViewController.h"
#import "RYGGalleryChip.h"
#import "../Utils.h"
#import "RYGGalleryShim.h"

static NSString *const kSortOrderKey = @"gallery_sort_order";
static NSString *const kSortAscKey = @"gallery_sort_ascending";
static NSString *const kSortTypeFirstKey = @"gallery_sort_type_first";
static NSString *const kFavoritesAtTopKey = @"show_favorites_at_top";

@interface RYGGallerySortViewController ()
@property (nonatomic, strong) NSMutableArray<RYGGalleryChip *> *orderChips;
@property (nonatomic, strong) NSMutableArray<RYGGalleryChip *> *groupChips;
@end

@implementation RYGGallerySortViewController

#pragma mark - Persisted axes

+ (RYGGallerySortOrder)currentOrder {
	return (RYGGallerySortOrder)(NSInteger)[RYGUtils getDoublePref:kSortOrderKey];
}

+ (BOOL)currentAscending {
	return [RYGUtils getBoolPref:kSortAscKey];
}

+ (RYGGallerySortTypeFirst)currentTypeFirst {
	return (RYGGallerySortTypeFirst)(NSInteger)[RYGUtils getDoublePref:kSortTypeFirstKey];
}

+ (BOOL)favoritesFirst {
	return [RYGUtils getBoolPref:kFavoritesAtTopKey];
}

+ (NSArray<NSSortDescriptor *> *)fileSortDescriptors {
	NSMutableArray<NSSortDescriptor *> *sorts = [NSMutableArray array];

	if ([self favoritesFirst]) {
		[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:@"isFavorite" ascending:NO]];
	}

	switch ([self currentTypeFirst]) {
		case RYGGallerySortTypeFirstImages:
			[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:@"mediaType" ascending:YES]];
			break;
		case RYGGallerySortTypeFirstVideos:
			[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:@"mediaType" ascending:NO]];
			break;
		case RYGGallerySortTypeFirstNone:
			break;
	}

	BOOL asc = [self currentAscending];
	switch ([self currentOrder]) {
		case RYGGallerySortOrderName:
			[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:@"relativePath" ascending:asc selector:@selector(localizedCaseInsensitiveCompare:)]];
			break;
		case RYGGallerySortOrderSize:
			[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:@"fileSize" ascending:asc]];
			break;
		case RYGGallerySortOrderDate:
		default:
			[sorts addObject:[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:asc]];
			break;
	}

	return sorts;
}

#pragma mark - Lifecycle

- (instancetype)init {
	if ((self = [super init])) {
		_orderChips = [NSMutableArray new];
		_groupChips = [NSMutableArray new];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.sheetTitle = RYGLocalized(@"Sort");
	[self buildContent];
}

- (CGFloat)preferredCardHeight {
	CGFloat screen = UIScreen.mainScreen.bounds.size.height;
	return MAX(400.0, MIN(470.0, screen * 0.56));
}

#pragma mark - Content

// tag encodes (order << 1 | ascending) so one chip drives both axes.
- (NSInteger)tagForOrder:(RYGGallerySortOrder)order ascending:(BOOL)asc {
	return (order << 1) | (asc ? 1 : 0);
}

- (void)buildContent {
	[self addSectionTitle:RYGLocalized(@"Order by")];
	[self addContentView:[self orderGrid]];

	[self addSectionTitle:RYGLocalized(@"Group first by")];
	[self addContentView:[self groupGrid]];
}

- (UIStackView *)gridWithRows:(NSArray<NSArray<RYGGalleryChip *> *> *)rows {
	UIStackView *grid = [UIStackView new];
	grid.translatesAutoresizingMaskIntoConstraints = NO;
	grid.axis = UILayoutConstraintAxisVertical;
	grid.spacing = 8;

	for (NSArray<RYGGalleryChip *> *row in rows) {
		UIStackView *line = [UIStackView new];
		line.axis = UILayoutConstraintAxisHorizontal;
		line.spacing = 8;
		line.distribution = UIStackViewDistributionFillEqually;
		for (RYGGalleryChip *chip in row) {
			[chip.heightAnchor constraintEqualToConstant:46].active = YES;
			[line addArrangedSubview:chip];
		}
		[grid addArrangedSubview:line];
	}

	return grid;
}

- (RYGGalleryChip *)orderChipTitle:(NSString *)title symbol:(NSString *)symbol order:(RYGGallerySortOrder)order ascending:(BOOL)asc {
	RYGGalleryChip *chip = [RYGGalleryChip chipWithTitle:title symbol:symbol];
	chip.tag = [self tagForOrder:order ascending:asc];
	chip.onState = (order == [RYGGallerySortViewController currentOrder] && asc == [RYGGallerySortViewController currentAscending]);
	[chip addTarget:self action:@selector(orderChipTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.orderChips addObject:chip];
	return chip;
}

- (UIStackView *)orderGrid {
	return [self gridWithRows:@[
		@[[self orderChipTitle:RYGLocalized(@"Newest first") symbol:@"calendar" order:RYGGallerySortOrderDate ascending:NO],
		  [self orderChipTitle:RYGLocalized(@"Oldest first") symbol:@"clock" order:RYGGallerySortOrderDate ascending:YES]],
		@[[self orderChipTitle:RYGLocalized(@"Name A-Z") symbol:@"text" order:RYGGallerySortOrderName ascending:YES],
		  [self orderChipTitle:RYGLocalized(@"Name Z-A") symbol:@"text" order:RYGGallerySortOrderName ascending:NO]],
		@[[self orderChipTitle:RYGLocalized(@"Largest first") symbol:@"arrow_up" order:RYGGallerySortOrderSize ascending:NO],
		  [self orderChipTitle:RYGLocalized(@"Smallest first") symbol:@"arrow_down" order:RYGGallerySortOrderSize ascending:YES]],
	]];
}

- (RYGGalleryChip *)groupChipTitle:(NSString *)title symbol:(NSString *)symbol tag:(NSInteger)tag on:(BOOL)on {
	RYGGalleryChip *chip = [RYGGalleryChip chipWithTitle:title symbol:symbol];
	chip.tag = tag;
	chip.onState = on;
	[chip addTarget:self action:@selector(groupChipTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.groupChips addObject:chip];
	return chip;
}

- (UIStackView *)groupGrid {
	RYGGallerySortTypeFirst typeFirst = [RYGGallerySortViewController currentTypeFirst];
	return [self gridWithRows:@[
		@[[self groupChipTitle:RYGLocalized(@"Images first") symbol:@"photo" tag:RYGGallerySortTypeFirstImages on:(typeFirst == RYGGallerySortTypeFirstImages)],
		  [self groupChipTitle:RYGLocalized(@"Videos first") symbol:@"video_outline" tag:RYGGallerySortTypeFirstVideos on:(typeFirst == RYGGallerySortTypeFirstVideos)]],
		@[[self groupChipTitle:RYGLocalized(@"Favorites first") symbol:@"heart_filled" tag:100 on:[RYGGallerySortViewController favoritesFirst]]],
	]];
}

#pragma mark - Actions

- (void)orderChipTapped:(RYGGalleryChip *)chip {
	RYGGallerySortOrder order = (RYGGallerySortOrder)(chip.tag >> 1);
	BOOL asc = (chip.tag & 1) != 0;

	[RYGUtils setPref:@(order) forKey:kSortOrderKey];
	[RYGUtils setPref:@(asc) forKey:kSortAscKey];

	for (RYGGalleryChip *c in self.orderChips) [c setOnState:(c.tag == chip.tag) animated:YES];

	[self notify];
}

- (void)groupChipTapped:(RYGGalleryChip *)chip {
	if (chip.tag == 100) {
		BOOL on = ![RYGGallerySortViewController favoritesFirst];
		[RYGUtils setPref:@(on) forKey:kFavoritesAtTopKey];
		[chip setOnState:on animated:YES];
		[self notify];
		return;
	}

	RYGGallerySortTypeFirst next = (chip.isOnState)
		? RYGGallerySortTypeFirstNone
		: (RYGGallerySortTypeFirst)chip.tag;

	[RYGUtils setPref:@(next) forKey:kSortTypeFirstKey];

	for (RYGGalleryChip *c in self.groupChips) {
		if (c.tag == 100) continue;
		[c setOnState:(c.tag == next) animated:YES];
	}

	[self notify];
}

- (void)notify {
	if ([self.delegate respondsToSelector:@selector(sortControllerDidChange:)]) {
		[self.delegate sortControllerDidChange:self];
	}
}

@end
