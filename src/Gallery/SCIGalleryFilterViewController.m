#import "SCIGalleryFilterViewController.h"
#import "SCIGalleryChip.h"
#import "SCIGalleryCoreDataStack.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"
#import <CoreData/CoreData.h>

static CGFloat const kSCIRowHeight = 50.0;
static CGFloat const kSCIRowRadius = 14.0;
static CGFloat const kSCIChipHeight = 44.0;
static CGFloat const kSCIGridSpacing = 8.0;

@interface SCIGalleryFilterViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UIControl *favoritesRow;
@property (nonatomic, strong) UIImageView *favoritesIcon;
@property (nonatomic, strong) UISwitch *favoritesSwitch;
@property (nonatomic, strong) UIControl *clearRow;
@property (nonatomic, strong) UIImageView *clearIcon;
@property (nonatomic, strong) UILabel *clearLabel;
@property (nonatomic, strong) NSMutableArray<SCIGalleryChip *> *typeChips;
@property (nonatomic, strong) NSMutableArray<SCIGalleryChip *> *sourceChips;
@property (nonatomic, strong) NSMutableArray<SCIGalleryChip *> *usernameChips;
@property (nonatomic, copy) NSArray<NSString *> *allUsernames;
@property (nonatomic, strong) UISearchBar *usernameSearchBar;
@property (nonatomic, strong) UIScrollView *usernameScrollView;
@property (nonatomic, strong) UIStackView *usernameStrip;
@end

@implementation SCIGalleryFilterViewController

#pragma mark - Predicate

+ (NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
						   sources:(NSSet<NSNumber *> *)sources
						 usernames:(NSSet<NSString *> *)usernames
					 favoritesOnly:(BOOL)favoritesOnly
						folderPath:(NSString *)folderPath {
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

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.sheetTitle = SCILocalized(@"Filter");

	if (!self.filterTypes) self.filterTypes = NSMutableSet.set;
	if (!self.filterSources) self.filterSources = NSMutableSet.set;
	if (!self.filterUsernames) self.filterUsernames = NSMutableSet.set;

	[self buildContent];
	[self updateAllStates];
}

#pragma mark - Content

- (void)buildContent {
	[self addCardRow:[self rowWithTitle:SCILocalized(@"Favorites only")
								 symbol:(self.filterFavoritesOnly ? @"heart.fill" : @"heart")
							  tintColor:[SCIUtils SCIColor_InstagramFavorite]
							 accessory:[self favoritesSwitchView]
								  action:@selector(favoritesRowTapped)]];
	[self addSectionTitle:SCILocalized(@"Type")];
	[self addContentView:[self chipGridWithItems:[self mediaTypeItems] selected:self.filterTypes target:self action:@selector(typeChipTapped:) storage:self.typeChips]];

	[self addSectionTitle:SCILocalized(@"Source")];
	[self addContentView:[self chipGridWithItems:[self sourceItems] selected:self.filterSources target:self action:@selector(sourceChipTapped:) storage:self.sourceChips]];

	self.allUsernames = [self distinctUsernamesFromGallery];
	if (self.allUsernames.count) {
		[self addSectionTitle:SCILocalized(@"Source user")];
		if (self.allUsernames.count > 8) [self addContentView:[self buildUsernameSearchBar]];
		[self addContentView:[self buildUsernameStrip]];
		[self rebuildUsernameChips:self.allUsernames];
	}

	[self addSectionTitle:SCILocalized(@"Options")];
	[self addCardRow:[self clearFiltersRow]];
}

#pragma mark - Rows

- (UISwitch *)favoritesSwitchView {
	self.favoritesSwitch = UISwitch.new;
	self.favoritesSwitch.on = self.filterFavoritesOnly;
	self.favoritesSwitch.onTintColor = [SCIUtils SCIColor_Primary];
	[self.favoritesSwitch addTarget:self action:@selector(favoritesSwitchChanged:) forControlEvents:UIControlEventValueChanged];
	return self.favoritesSwitch;
}

- (UIControl *)rowWithTitle:(NSString *)title symbol:(NSString *)symbol tintColor:(UIColor *)tint accessory:(UIView *)accessory action:(SEL)action {
	UIControl *row = UIControl.new;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	row.backgroundColor = UIColor.tertiarySystemFillColor;
	row.layer.cornerRadius = kSCIRowRadius;
	row.layer.cornerCurve = kCACornerCurveContinuous;
	[row.heightAnchor constraintEqualToConstant:kSCIRowHeight].active = YES;
	if (action) [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

	UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
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
	self.clearRow = [self rowWithTitle:SCILocalized(@"Clear filters")
								symbol:@"xmark.circle"
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
		@{@"title": SCILocalized(@"Images"), @"symbol": @"photo", @"value": @(SCIGalleryMediaTypeImage)},
		@{@"title": SCILocalized(@"Videos"), @"symbol": @"video", @"value": @(SCIGalleryMediaTypeVideo)},
		@{@"title": SCILocalized(@"Audio"),  @"symbol": @"waveform", @"value": @(SCIGalleryMediaTypeAudio)},
		@{@"title": SCILocalized(@"GIFs"),   @"symbol": @"ig_icon_gif_outline_24", @"value": @(SCIGalleryMediaTypeGIF)},
	];
}

- (NSArray<NSDictionary *> *)sourceItems {
	NSArray<NSNumber *> *sources = @[
		@(SCIGallerySourceFeed), @(SCIGallerySourceStories), @(SCIGallerySourceReels),
		@(SCIGallerySourceProfile), @(SCIGallerySourceDMs), @(SCIGallerySourceInstants),
		@(SCIGallerySourceNotes), @(SCIGallerySourceComments), @(SCIGallerySourceThumbnail),
	];

	NSMutableArray *items = [NSMutableArray arrayWithCapacity:sources.count];

	for (NSNumber *number in sources) {
		SCIGallerySource source = (SCIGallerySource)number.integerValue;
		[items addObject:@{
			@"title": [SCIGalleryFile labelForSource:source] ?: @"",
			@"symbol": [self symbolForSource:source],
			@"value": number
		}];
	}

	return items.copy;
}

- (UIView *)chipGridWithItems:(NSArray<NSDictionary *> *)items selected:(NSSet<NSNumber *> *)selected target:(id)target action:(SEL)action storage:(NSMutableArray<SCIGalleryChip *> *)storage {
	UIStackView *grid = UIStackView.new;
	grid.translatesAutoresizingMaskIntoConstraints = NO;
	grid.axis = UILayoutConstraintAxisVertical;
	grid.spacing = kSCIGridSpacing;

	UIStackView *row = nil;

	for (NSUInteger i = 0; i < items.count; i++) {
		if (i % 2 == 0) {
			row = UIStackView.new;
			row.axis = UILayoutConstraintAxisHorizontal;
			row.spacing = kSCIGridSpacing;
			row.distribution = UIStackViewDistributionFillEqually;
			[grid addArrangedSubview:row];
		}

		NSDictionary *item = items[i];
		NSNumber *value = item[@"value"];
		SCIGalleryChip *chip = [SCIGalleryChip chipWithTitle:item[@"title"] symbol:item[@"symbol"]];

		chip.tag = value.integerValue;
		chip.onState = [selected containsObject:value];
		[chip addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
		[chip.heightAnchor constraintEqualToConstant:kSCIChipHeight].active = YES;

		[row addArrangedSubview:chip];
		[storage addObject:chip];
	}

	if (row.arrangedSubviews.count % 2) [row addArrangedSubview:UIView.new];

	return grid;
}

- (NSString *)symbolForSource:(SCIGallerySource)source {
	switch (source) {
		case SCIGallerySourceFeed:		return @"rectangle.stack";
		case SCIGallerySourceStories:	return @"circle.dashed";
		case SCIGallerySourceReels:		return @"film.stack";
		case SCIGallerySourceProfile:	return @"person.crop.circle";
		case SCIGallerySourceDMs:		return @"bubble.left.and.bubble.right";
		case SCIGallerySourceThumbnail:	return @"photo.on.rectangle.angled";
		case SCIGallerySourceNotes:		return @"note.text";
		case SCIGallerySourceComments:	return @"text.bubble";
		case SCIGallerySourceInstants:	return @"ig_icon_app_instants_outline_24";
		case SCIGallerySourceOther:
		default:						return @"photo.on.rectangle";
	}
}

#pragma mark - Usernames

- (NSArray<NSString *> *)distinctUsernamesFromGallery {
	NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
	NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];

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
	self.usernameSearchBar.placeholder = SCILocalized(@"Search users");
	self.usernameSearchBar.delegate = self;
	self.usernameSearchBar.searchBarStyle = UISearchBarStyleMinimal;
	self.usernameSearchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.usernameSearchBar.autocorrectionType = UITextAutocorrectionTypeNo;
	[self.usernameSearchBar.heightAnchor constraintEqualToConstant:38.0].active = YES;

	if (@available(iOS 13.0, *)) {
		self.usernameSearchBar.searchTextField.backgroundColor = UIColor.tertiarySystemFillColor;
		self.usernameSearchBar.searchTextField.layer.cornerRadius = 10.0;
		self.usernameSearchBar.searchTextField.clipsToBounds = YES;
	}

	return self.usernameSearchBar;
}

- (UIView *)buildUsernameStrip {
	self.usernameScrollView = UIScrollView.new;
	self.usernameScrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.usernameScrollView.showsHorizontalScrollIndicator = NO;
	self.usernameScrollView.alwaysBounceHorizontal = YES;
	[self.usernameScrollView.heightAnchor constraintEqualToConstant:kSCIChipHeight].active = YES;

	self.usernameStrip = UIStackView.new;
	self.usernameStrip.translatesAutoresizingMaskIntoConstraints = NO;
	self.usernameStrip.axis = UILayoutConstraintAxisHorizontal;
	self.usernameStrip.alignment = UIStackViewAlignmentCenter;
	self.usernameStrip.spacing = kSCIGridSpacing;

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
		SCIGalleryChip *chip = [SCIGalleryChip chipWithTitle:[@"@" stringByAppendingString:username] symbol:@"at"];
		chip.accessibilityIdentifier = username;
		chip.onState = [self.filterUsernames containsObject:username];
		[chip addTarget:self action:@selector(usernameChipTapped:) forControlEvents:UIControlEventTouchUpInside];

		[self.usernameStrip addArrangedSubview:chip];
		[self.usernameChips addObject:chip];
	}
}

#pragma mark - Search

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

- (void)toggleNumber:(NSNumber *)value inSet:(NSMutableSet<NSNumber *> *)set chip:(SCIGalleryChip *)chip {
	if ([set containsObject:value]) {
		[set removeObject:value];
	} else {
		[set addObject:value];
	}

	[chip setOnState:[set containsObject:value] animated:YES];
	[self notify];
}

- (void)typeChipTapped:(SCIGalleryChip *)chip {
	[self toggleNumber:@(chip.tag) inSet:self.filterTypes chip:chip];
}

- (void)sourceChipTapped:(SCIGalleryChip *)chip {
	[self toggleNumber:@(chip.tag) inSet:self.filterSources chip:chip];
}

- (void)usernameChipTapped:(SCIGalleryChip *)chip {
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
	self.favoritesSwitch.on = NO;
	self.usernameSearchBar.text = @"";

	for (SCIGalleryChip *chip in self.typeChips) [chip setOnState:NO animated:YES];
	for (SCIGalleryChip *chip in self.sourceChips) [chip setOnState:NO animated:YES];

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
	return self.filterTypes.count || self.filterSources.count || self.filterUsernames.count || self.filterFavoritesOnly;
}

- (void)updateAllStates {
	[self updateFavoritesState];
	[self updateClearState];
}

- (void)updateFavoritesState {
	BOOL on = self.filterFavoritesOnly;
	UIColor *accent = [SCIUtils SCIColor_InstagramFavorite];

	self.favoritesRow.backgroundColor = on ? [accent colorWithAlphaComponent:0.16] : UIColor.tertiarySystemFillColor;
	self.favoritesIcon.image = [UIImage systemImageNamed:(on ? @"heart.fill" : @"heart")];
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

	if (![self.delegate respondsToSelector:@selector(filterController:didApplyTypes:sources:usernames:favoritesOnly:)]) return;

	[self.delegate filterController:self
					  didApplyTypes:self.filterTypes.copy
							sources:self.filterSources.copy
						  usernames:self.filterUsernames.copy
					  favoritesOnly:self.filterFavoritesOnly];
}

@end