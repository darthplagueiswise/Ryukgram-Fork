#import "RYGGalleryFilterViewController.h"
#import "RYGGalleryChip.h"
#import "RYGGalleryCoreDataStack.h"
#import "RYGGalleryFile.h"
#import "RYGAssetUtils.h"
#import "../Utils.h"
#import "RYGGalleryShim.h"
#import <CoreData/CoreData.h>

static CGFloat const kRYGRowHeight = 50.0;
static CGFloat const kRYGRowRadius = 14.0;
static CGFloat const kRYGChipHeight = 44.0;
static CGFloat const kRYGGridSpacing = 8.0;

@interface RYGGalleryFilterViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UIControl *favoritesRow;
@property (nonatomic, strong) UIImageView *favoritesIcon;
@property (nonatomic, strong) UISwitch *favoritesSwitch;
@property (nonatomic, strong) UIControl *clearRow;
@property (nonatomic, strong) UIImageView *clearIcon;
@property (nonatomic, strong) UILabel *clearLabel;
@property (nonatomic, strong) NSMutableArray<RYGGalleryChip *> *typeChips;
@property (nonatomic, strong) NSMutableArray<RYGGalleryChip *> *sourceChips;
@property (nonatomic, strong) NSMutableArray<RYGGalleryChip *> *usernameChips;
@property (nonatomic, strong) NSMutableArray<RYGGalleryChip *> *dateChips;
@property (nonatomic, copy) NSArray<NSString *> *allUsernames;
@property (nonatomic, strong) UISearchBar *usernameSearchBar;
@property (nonatomic, strong) UIScrollView *usernameScrollView;
@property (nonatomic, strong) UIStackView *usernameStrip;
@end

@implementation RYGGalleryFilterViewController

#pragma mark - Predicate

+ (NSPredicate *)filterPredicateForTypes:(NSSet<NSNumber *> *)types
								 sources:(NSSet<NSNumber *> *)sources
							   usernames:(NSSet<NSString *> *)usernames
						   favoritesOnly:(BOOL)favoritesOnly
								dateFrom:(NSDate *)dateFrom
								  dateTo:(NSDate *)dateTo {
	NSMutableArray<NSPredicate *> *parts = NSMutableArray.array;

	if (types.count) {
		NSArray *list = [types.allObjects sortedArrayUsingSelector:@selector(compare:)];
		[parts addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", list]];
	}

	if (sources.count) {
		NSArray *list = [sources.allObjects sortedArrayUsingSelector:@selector(compare:)];
		[parts addObject:[NSPredicate predicateWithFormat:@"source IN %@", list]];
	}

	if (usernames.count) {
		[parts addObject:[NSPredicate predicateWithFormat:@"sourceUsername IN %@", usernames.allObjects]];
	}

	if (favoritesOnly) {
		[parts addObject:[NSPredicate predicateWithFormat:@"isFavorite == YES"]];
	}

	if (dateFrom) {
		[parts addObject:[NSPredicate predicateWithFormat:@"dateAdded >= %@", dateFrom]];
	}

	if (dateTo) {
		[parts addObject:[NSPredicate predicateWithFormat:@"dateAdded <= %@", dateTo]];
	}

	return parts.count ? [NSCompoundPredicate andPredicateWithSubpredicates:parts] : nil;
}

+ (NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
						   sources:(NSSet<NSNumber *> *)sources
						 usernames:(NSSet<NSString *> *)usernames
					 favoritesOnly:(BOOL)favoritesOnly
						  dateFrom:(NSDate *)dateFrom
							dateTo:(NSDate *)dateTo
						folderPath:(NSString *)folderPath {
	NSMutableArray<NSPredicate *> *parts = NSMutableArray.array;
	NSPredicate *filters = [self filterPredicateForTypes:types sources:sources usernames:usernames favoritesOnly:favoritesOnly dateFrom:dateFrom dateTo:dateTo];

	if (filters) {
		[parts addObject:filters];
	}

	if (folderPath.length) {
		[parts addObject:[NSPredicate predicateWithFormat:@"folderPath == %@", folderPath]];
	} else {
		[parts addObject:[NSPredicate predicateWithFormat:@"folderPath == nil OR folderPath == %@", @""]];
	}

	return parts.count ? [NSCompoundPredicate andPredicateWithSubpredicates:parts] : nil;
}

#pragma mark - Init

- (instancetype)init {
	self = [super init];
	if (!self) return nil;

	_filterTypes = NSMutableSet.set;
	_filterSources = NSMutableSet.set;
	_filterUsernames = NSMutableSet.set;
	_typeChips = NSMutableArray.array;
	_sourceChips = NSMutableArray.array;
	_usernameChips = NSMutableArray.array;
	_dateChips = NSMutableArray.array;

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.sheetTitle = RYGLocalized(@"Filter");

	if (!self.filterTypes) self.filterTypes = NSMutableSet.set;
	if (!self.filterSources) self.filterSources = NSMutableSet.set;
	if (!self.filterUsernames) self.filterUsernames = NSMutableSet.set;

	[self buildContent];
	[self updateAllStates];
}

#pragma mark - Content

- (void)buildContent {
	[self addCardRow:[self rowWithTitle:RYGLocalized(@"Favorites only")
								 symbol:(self.filterFavoritesOnly ? @"heart_filled" : @"heart")
							  tintColor:[RYGUtils RYGColor_InstagramFavorite]
							 accessory:[self favoritesSwitchView]
								  action:@selector(favoritesRowTapped)]];
	[self addSectionTitle:RYGLocalized(@"Type")];
	[self addContentView:[self chipGridWithItems:[self mediaTypeItems] selected:self.filterTypes target:self action:@selector(typeChipTapped:) storage:self.typeChips]];

	[self addSectionTitle:RYGLocalized(@"Source")];
	[self addContentView:[self chipGridWithItems:[self sourceItems] selected:self.filterSources target:self action:@selector(sourceChipTapped:) storage:self.sourceChips]];

	self.allUsernames = [self distinctUsernamesFromGallery];
	if (self.allUsernames.count) {
		[self addSectionTitle:RYGLocalized(@"Source user")];
		if (self.allUsernames.count > 8) [self addContentView:[self buildUsernameSearchBar]];
		[self addContentView:[self buildUsernameStrip]];
		[self rebuildUsernameChips:self.allUsernames];
	}

	[self addSectionTitle:RYGLocalized(@"Date")];
	[self addContentView:[self chipGridWithItems:[self dateItems] selected:[NSSet setWithObject:@([self selectedDatePreset])] target:self action:@selector(dateChipTapped:) storage:self.dateChips]];

	[self addSectionTitle:RYGLocalized(@"Options")];
	[self addCardRow:[self clearFiltersRow]];
}

#pragma mark - Date presets

// 0 Any · 1 Today · 2 Last 7 days · 3 Last 30 days · 4 This year.
+ (nullable NSDate *)startDateForPreset:(NSInteger)preset {
	if (preset <= 0) return nil;

	NSCalendar *cal = NSCalendar.currentCalendar;
	NSDate *startOfToday = [cal startOfDayForDate:NSDate.date];

	switch (preset) {
		case 1: return startOfToday;
		case 2: return [cal dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:startOfToday options:0];
		case 3: return [cal dateByAddingUnit:NSCalendarUnitDay value:-29 toDate:startOfToday options:0];
		case 4: {
			NSDateComponents *comps = [cal components:NSCalendarUnitYear fromDate:NSDate.date];
			return [cal dateFromComponents:comps];
		}
		default: return nil;
	}
}

- (NSArray<NSDictionary *> *)dateItems {
	return @[
		@{@"title": RYGLocalized(@"Any time"),	 @"symbol": @"clock",		 @"value": @0},
		@{@"title": RYGLocalized(@"Today"),		@"symbol": @"calendar",	  @"value": @1},
		@{@"title": RYGLocalized(@"Last 7 days"),  @"symbol": @"calendar",	  @"value": @2},
		@{@"title": RYGLocalized(@"Last 30 days"), @"symbol": @"calendar",	  @"value": @3},
		@{@"title": RYGLocalized(@"This year"),	@"symbol": @"calendar_star", @"value": @4},
	];
}

- (NSInteger)selectedDatePreset {
	if (!self.filterDateFrom) return 0;

	for (NSInteger preset = 1; preset <= 4; preset++) {
		NSDate *start = [RYGGalleryFilterViewController startDateForPreset:preset];
		if (start && fabs([start timeIntervalSinceDate:self.filterDateFrom]) < 1.0) return preset;
	}

	return 0;
}

- (void)dateChipTapped:(RYGGalleryChip *)chip {
	NSInteger preset = chip.tag;

	self.filterDateFrom = [RYGGalleryFilterViewController startDateForPreset:preset];
	self.filterDateTo = nil;

	for (RYGGalleryChip *c in self.dateChips) [c setOnState:(c.tag == preset) animated:YES];

	[self notify];
}

#pragma mark - Rows

- (UISwitch *)favoritesSwitchView {
	self.favoritesSwitch = UISwitch.new;
	self.favoritesSwitch.on = self.filterFavoritesOnly;
	self.favoritesSwitch.onTintColor = [RYGUtils RYGColor_Primary];
	[self.favoritesSwitch addTarget:self action:@selector(favoritesSwitchChanged:) forControlEvents:UIControlEventValueChanged];
	return self.favoritesSwitch;
}

- (UIControl *)rowWithTitle:(NSString *)title symbol:(NSString *)symbol tintColor:(UIColor *)tint accessory:(UIView *)accessory action:(SEL)action {
	UIControl *row = UIControl.new;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	row.backgroundColor = UIColor.tertiarySystemFillColor;
	row.layer.cornerRadius = kRYGRowRadius;
	row.layer.cornerCurve = kCACornerCurveContinuous;
	[row.heightAnchor constraintEqualToConstant:kRYGRowHeight].active = YES;
	if (action) [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

	UIImageView *icon = [[UIImageView alloc] initWithImage:[RYGAssetUtils instagramIconNamed:symbol pointSize:19.0]];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.tintColor = tint ?: UIColor.secondaryLabelColor;
	icon.contentMode = UIViewContentModeScaleAspectFit;

	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
	label.textColor = UIColor.labelColor;

	[row addSubview:icon];
	[row addSubview:label];
	if (accessory) {
		accessory.translatesAutoresizingMaskIntoConstraints = NO;
		[row addSubview:accessory];
	}

	NSMutableArray *constraints = [@[
		[icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
		[icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:20.0],
		[icon.heightAnchor constraintEqualToConstant:20.0],

		[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
		[label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:(accessory ?: row).leadingAnchor constant:(accessory ? -10.0 : -12.0)],
	] mutableCopy];

	if (accessory) {
		[constraints addObjectsFromArray:@[
			[accessory.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
			[accessory.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		]];
	}

	[NSLayoutConstraint activateConstraints:constraints];

	if (accessory == self.favoritesSwitch) {
		self.favoritesRow = row;
		self.favoritesIcon = icon;
	}

	return row;
}

- (UIControl *)clearFiltersRow {
	self.clearRow = [self rowWithTitle:RYGLocalized(@"Clear filters")
								symbol:@"circle_xmark"
							 tintColor:UIColor.systemRedColor
							accessory:nil
								action:@selector(clearFilters)];
	for (UIView *view in self.clearRow.subviews) {
		if ([view isKindOfClass:UIImageView.class]) self.clearIcon = (UIImageView *)view;
		if ([view isKindOfClass:UILabel.class]) self.clearLabel = (UILabel *)view;
	}
	return self.clearRow;
}

#pragma mark - Chips

- (NSArray<NSDictionary *> *)mediaTypeItems {
	return @[
		@{@"title": RYGLocalized(@"Images"), @"symbol": @"photo", @"value": @(RYGGalleryMediaTypeImage)},
		@{@"title": RYGLocalized(@"Videos"), @"symbol": @"video_outline", @"value": @(RYGGalleryMediaTypeVideo)},
		@{@"title": RYGLocalized(@"Audio"),  @"symbol": @"audio", @"value": @(RYGGalleryMediaTypeAudio)},
		@{@"title": RYGLocalized(@"GIFs"),   @"symbol": @"gif_outline", @"value": @(RYGGalleryMediaTypeGIF)},
	];
}

- (NSArray<NSDictionary *> *)sourceItems {
	NSArray<NSNumber *> *sources = @[
		@(RYGGallerySourceFeed), @(RYGGallerySourceStories), @(RYGGallerySourceReels),
		@(RYGGallerySourceProfile), @(RYGGallerySourceDMs), @(RYGGallerySourceInstants),
		@(RYGGallerySourceCalls), @(RYGGallerySourceNotes), @(RYGGallerySourceComments),
		@(RYGGallerySourceThumbnail),
	];

	NSMutableArray *items = [NSMutableArray arrayWithCapacity:sources.count];

	for (NSNumber *number in sources) {
		RYGGallerySource source = (RYGGallerySource)number.integerValue;
		[items addObject:@{
			@"title": [RYGGalleryFile labelForSource:source] ?: @"",
			@"symbol": [self symbolForSource:source],
			@"value": number
		}];
	}

	return items.copy;
}

- (UIView *)chipGridWithItems:(NSArray<NSDictionary *> *)items selected:(NSSet<NSNumber *> *)selected target:(id)target action:(SEL)action storage:(NSMutableArray<RYGGalleryChip *> *)storage {
	UIStackView *grid = UIStackView.new;
	grid.translatesAutoresizingMaskIntoConstraints = NO;
	grid.axis = UILayoutConstraintAxisVertical;
	grid.spacing = kRYGGridSpacing;

	UIStackView *row = nil;

	for (NSUInteger i = 0; i < items.count; i++) {
		if (i % 2 == 0) {
			row = UIStackView.new;
			row.axis = UILayoutConstraintAxisHorizontal;
			row.spacing = kRYGGridSpacing;
			row.distribution = UIStackViewDistributionFillEqually;
			[grid addArrangedSubview:row];
		}

		NSDictionary *item = items[i];
		NSNumber *value = item[@"value"];
		RYGGalleryChip *chip = [RYGGalleryChip chipWithTitle:item[@"title"] symbol:item[@"symbol"]];

		chip.tag = value.integerValue;
		chip.onState = [selected containsObject:value];
		[chip addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
		[chip.heightAnchor constraintEqualToConstant:kRYGChipHeight].active = YES;

		[row addArrangedSubview:chip];
		[storage addObject:chip];
	}

	if (row.arrangedSubviews.count % 2) [row addArrangedSubview:UIView.new];

	return grid;
}

- (NSString *)symbolForSource:(RYGGallerySource)source {
	return [RYGGalleryFile symbolNameForSource:source];
}

#pragma mark - Usernames

- (NSArray<NSString *> *)distinctUsernamesFromGallery {
	NSManagedObjectContext *context = [RYGGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];

	request.resultType = NSDictionaryResultType;
	request.propertiesToFetch = @[@"sourceUsername"];
	request.returnsDistinctResults = YES;
	request.predicate = [NSPredicate predicateWithFormat:@"sourceUsername != nil AND sourceUsername != %@", @""];

	NSArray<NSDictionary *> *rows = [context executeFetchRequest:request error:nil] ?: @[];
	NSMutableSet<NSString *> *set = NSMutableSet.set;

	for (NSDictionary *row in rows) {
		NSString *name = row[@"sourceUsername"];
		if ([name isKindOfClass:NSString.class] && name.length) [set addObject:name];
	}

	return [set.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (UISearchBar *)buildUsernameSearchBar {
	self.usernameSearchBar = UISearchBar.new;
	self.usernameSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.usernameSearchBar.placeholder = RYGLocalized(@"Search users");
	self.usernameSearchBar.delegate = self;
	self.usernameSearchBar.searchBarStyle = UISearchBarStyleMinimal;
	self.usernameSearchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.usernameSearchBar.autocorrectionType = UITextAutocorrectionTypeNo;
	self.usernameSearchBar.returnKeyType = UIReturnKeyDone;
	self.usernameSearchBar.enablesReturnKeyAutomatically = NO;
	[self.usernameSearchBar.heightAnchor constraintEqualToConstant:38.0].active = YES;

	if (@available(iOS 13.0, *)) {
		UITextField *field = self.usernameSearchBar.searchTextField;
		field.backgroundColor = UIColor.tertiarySystemFillColor;
		field.textColor = UIColor.labelColor;
		field.tintColor = [RYGUtils RYGColor_Primary];
		field.layer.cornerRadius = 10.0;
		field.clipsToBounds = YES;
	}

	return self.usernameSearchBar;
}

- (UIView *)buildUsernameStrip {
	self.usernameScrollView = UIScrollView.new;
	self.usernameScrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.usernameScrollView.showsHorizontalScrollIndicator = NO;
	self.usernameScrollView.alwaysBounceHorizontal = YES;
	[self.usernameScrollView.heightAnchor constraintEqualToConstant:kRYGChipHeight].active = YES;

	self.usernameStrip = UIStackView.new;
	self.usernameStrip.translatesAutoresizingMaskIntoConstraints = NO;
	self.usernameStrip.axis = UILayoutConstraintAxisHorizontal;
	self.usernameStrip.alignment = UIStackViewAlignmentCenter;
	self.usernameStrip.spacing = kRYGGridSpacing;

	[self.usernameScrollView addSubview:self.usernameStrip];

	[NSLayoutConstraint activateConstraints:@[
		[self.usernameStrip.topAnchor constraintEqualToAnchor:self.usernameScrollView.contentLayoutGuide.topAnchor],
		[self.usernameStrip.bottomAnchor constraintEqualToAnchor:self.usernameScrollView.contentLayoutGuide.bottomAnchor],
		[self.usernameStrip.leadingAnchor constraintEqualToAnchor:self.usernameScrollView.contentLayoutGuide.leadingAnchor],
		[self.usernameStrip.trailingAnchor constraintEqualToAnchor:self.usernameScrollView.contentLayoutGuide.trailingAnchor],
		[self.usernameStrip.heightAnchor constraintEqualToAnchor:self.usernameScrollView.frameLayoutGuide.heightAnchor],
	]];

	return self.usernameScrollView;
}

- (void)rebuildUsernameChips:(NSArray<NSString *> *)usernames {
	for (UIView *view in self.usernameStrip.arrangedSubviews.copy) {
		[self.usernameStrip removeArrangedSubview:view];
		[view removeFromSuperview];
	}

	[self.usernameChips removeAllObjects];

	for (NSString *username in usernames) {
		RYGGalleryChip *chip = [RYGGalleryChip chipWithTitle:[@"@" stringByAppendingString:username] symbol:@"at"];
		chip.accessibilityIdentifier = username;
		chip.onState = [self.filterUsernames containsObject:username];
		[chip addTarget:self action:@selector(usernameChipTapped:) forControlEvents:UIControlEventTouchUpInside];

		[self.usernameStrip addArrangedSubview:chip];
		[self.usernameChips addObject:chip];
	}
}

#pragma mark - Search

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		CGRect frame = [searchBar convertRect:searchBar.bounds toView:self.scrollView];
		[self.scrollView scrollRectToVisible:CGRectInset(frame, 0.0, -48.0) animated:YES];
	});
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	NSString *query = [searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSArray<NSString *> *items = self.allUsernames;

	if (query.length) {
		NSMutableArray *filtered = NSMutableArray.array;
		for (NSString *name in self.allUsernames) {
			if ([name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
				[filtered addObject:name];
			}
		}
		items = filtered;
	}

	[self rebuildUsernameChips:items];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	[self rebuildUsernameChips:self.allUsernames];
	[searchBar resignFirstResponder];
}

#pragma mark - Actions

- (void)toggleNumber:(NSNumber *)value inSet:(NSMutableSet<NSNumber *> *)set chip:(RYGGalleryChip *)chip {
	if ([set containsObject:value]) {
		[set removeObject:value];
	} else {
		[set addObject:value];
	}

	[chip setOnState:[set containsObject:value] animated:YES];
	[self notify];
}

- (void)typeChipTapped:(RYGGalleryChip *)chip {
	[self toggleNumber:@(chip.tag) inSet:self.filterTypes chip:chip];
}

- (void)sourceChipTapped:(RYGGalleryChip *)chip {
	[self toggleNumber:@(chip.tag) inSet:self.filterSources chip:chip];
}

- (void)usernameChipTapped:(RYGGalleryChip *)chip {
	NSString *name = chip.accessibilityIdentifier;
	if (!name.length) return;

	if ([self.filterUsernames containsObject:name]) {
		[self.filterUsernames removeObject:name];
	} else {
		[self.filterUsernames addObject:name];
	}

	[chip setOnState:[self.filterUsernames containsObject:name] animated:YES];
	[self notify];
}

- (void)favoritesRowTapped {
	self.favoritesSwitch.on = !self.favoritesSwitch.isOn;
	[self favoritesSwitchChanged:self.favoritesSwitch];
}

- (void)favoritesSwitchChanged:(UISwitch *)sender {
	self.filterFavoritesOnly = sender.isOn;
	[self updateFavoritesState];
	[self notify];
}

- (void)clearFilters {
	if (![self hasActiveFilters]) return;

	[self.filterTypes removeAllObjects];
	[self.filterSources removeAllObjects];
	[self.filterUsernames removeAllObjects];

	self.filterFavoritesOnly = NO;
	self.filterDateFrom = nil;
	self.filterDateTo = nil;
	self.favoritesSwitch.on = NO;
	self.usernameSearchBar.text = @"";

	for (RYGGalleryChip *chip in self.typeChips) [chip setOnState:NO animated:YES];
	for (RYGGalleryChip *chip in self.sourceChips) [chip setOnState:NO animated:YES];
	for (RYGGalleryChip *chip in self.dateChips) [chip setOnState:(chip.tag == 0) animated:YES];

	[self rebuildUsernameChips:self.allUsernames];
	[self updateAllStates];

	if ([self.delegate respondsToSelector:@selector(filterControllerDidClear:)]) {
		[self.delegate filterControllerDidClear:self];
	} else {
		[self notify];
	}
}

#pragma mark - State

- (BOOL)hasActiveFilters {
	return self.filterTypes.count || self.filterSources.count || self.filterUsernames.count || self.filterFavoritesOnly || self.filterDateFrom != nil;
}

- (void)updateAllStates {
	[self updateFavoritesState];
	[self updateClearState];
}

- (void)updateFavoritesState {
	BOOL on = self.filterFavoritesOnly;
	UIColor *accent = [RYGUtils RYGColor_InstagramFavorite];

	self.favoritesRow.backgroundColor = on ? [accent colorWithAlphaComponent:0.16] : UIColor.tertiarySystemFillColor;
	self.favoritesIcon.image = [RYGAssetUtils instagramIconNamed:(on ? @"heart_filled" : @"heart") pointSize:19.0];
	self.favoritesIcon.tintColor = on ? accent : UIColor.secondaryLabelColor;
}

- (void)updateClearState {
	BOOL active = [self hasActiveFilters];

	self.clearRow.userInteractionEnabled = active;
	self.clearRow.backgroundColor = active ? [UIColor.systemRedColor colorWithAlphaComponent:0.14] : UIColor.tertiarySystemFillColor;
	self.clearIcon.tintColor = active ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
	self.clearLabel.textColor = active ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
}

- (void)notify {
	[self updateAllStates];

	if (![self.delegate respondsToSelector:@selector(filterController:didApplyTypes:sources:usernames:favoritesOnly:dateFrom:dateTo:)]) return;

	[self.delegate filterController:self
					  didApplyTypes:self.filterTypes.copy
							sources:self.filterSources.copy
						  usernames:self.filterUsernames.copy
					  favoritesOnly:self.filterFavoritesOnly
						   dateFrom:self.filterDateFrom
							 dateTo:self.filterDateTo];
}

@end