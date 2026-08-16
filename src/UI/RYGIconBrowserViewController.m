#import "RYGIconBrowserViewController.h"
#import "RYGIcon.h"
#import "RYGIGIconCatalog.h"
#import "../Localization/RYGLocalization.h"
#import "../ActionButton/RYGActionIcon.h"
#import "../Features/Feed/RYGHomeShortcutCatalog.h"

#pragma mark - Cell

@interface RYGIconBrowserCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *checkBadge;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) NSLayoutConstraint *iconCenterY;
- (void)setImage:(UIImage *)image selected:(BOOL)selected;
- (void)setImage:(UIImage *)image caption:(NSString *)caption selected:(BOOL)selected;
@end

@implementation RYGIconBrowserCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.contentView.layer.cornerRadius = 16;
	self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
	self.contentView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
	self.contentView.layer.borderColor = UIColor.separatorColor.CGColor;
	self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

	_iconView = [UIImageView new];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.tintColor = UIColor.labelColor;
	[self.contentView addSubview:_iconView];

	_caption = [UILabel new];
	_caption.translatesAutoresizingMaskIntoConstraints = NO;
	_caption.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
	_caption.textColor = UIColor.secondaryLabelColor;
	_caption.hidden = YES;
	[self.contentView addSubview:_caption];

	UIImageSymbolConfiguration *checkCfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
	_checkBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:checkCfg]];
	_checkBadge.translatesAutoresizingMaskIntoConstraints = NO;
	_checkBadge.tintColor = UIColor.systemBlueColor;
	_checkBadge.backgroundColor = UIColor.whiteColor;
	_checkBadge.layer.cornerRadius = 9;
	_checkBadge.layer.masksToBounds = YES;
	_checkBadge.hidden = YES;
	[self.contentView addSubview:_checkBadge];

	_iconCenterY = [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor];

	[NSLayoutConstraint activateConstraints:@[
		[_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
		_iconCenterY,
		[_iconView.widthAnchor constraintEqualToConstant:30],
		[_iconView.heightAnchor constraintEqualToConstant:30],
		[_caption.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
		[_caption.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:4],
		[_checkBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
		[_checkBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
		[_checkBadge.widthAnchor constraintEqualToConstant:18],
		[_checkBadge.heightAnchor constraintEqualToConstant:18],
	]];

	return self;
}

- (void)setImage:(UIImage *)image caption:(NSString *)caption selected:(BOOL)selected {
	self.caption.text = caption;
	self.caption.hidden = caption.length == 0;
	self.iconCenterY.constant = caption.length ? -7 : 0;
	[self setImage:image selected:selected];
}

- (void)setImage:(UIImage *)image selected:(BOOL)selected {
	self.iconView.image = image;
	self.checkBadge.hidden = !selected;
	self.caption.textColor = selected ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
	if (selected) {
		self.contentView.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.16];
		self.contentView.layer.borderColor = UIColor.systemBlueColor.CGColor;
		self.contentView.layer.borderWidth = 2.0;
		self.iconView.tintColor = UIColor.systemBlueColor;
	} else {
		self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
		self.contentView.layer.borderColor = UIColor.separatorColor.CGColor;
		self.contentView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
		self.iconView.tintColor = UIColor.labelColor;
	}
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.iconView.contentMode = UIViewContentModeScaleAspectFit;
	[self setImage:nil caption:nil selected:NO];
}

@end


#pragma mark - VC

@interface RYGIconBrowserViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchResultsUpdating>
@property (nonatomic, copy) NSString *currentName;
@property (nonatomic, copy) NSString *specialTitle;
@property (nonatomic, copy) NSString *specialIcon;
@property (nonatomic, copy) NSString *specialValue;
@property (nonatomic, copy) void (^completion)(NSString *);

@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) NSArray<NSString *> *systemAll;
@property (nonatomic, strong) NSArray<NSString *> *igAll;
@property (nonatomic, strong) NSArray<NSString *> *filtered;
@property (nonatomic, assign) BOOL igReady;
@property (nonatomic, copy) NSString *query;
@end

@implementation RYGIconBrowserViewController

- (instancetype)initWithTitle:(NSString *)title
                  currentName:(NSString *)currentName
                 specialTitle:(NSString *)specialTitle
                  specialIcon:(NSString *)specialIcon
                 specialValue:(NSString *)specialValue
                   completion:(void (^)(NSString *))completion {
	self = [super init];
	if (self) {
		self.title = title ?: RYGLocalized(@"Icon");
		_currentName = [currentName copy];
		_specialTitle = [specialTitle copy];
		_specialIcon = [specialIcon copy];
		_specialValue = [specialValue copy];
		_completion = [completion copy];
		_query = @"";
	}
	return self;
}

#pragma mark Catalogs

+ (NSArray<NSString *> *)systemIconNames {
	static NSArray *names;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// Union of every SF set the tweak uses (action-button trigger + home
		// shortcut) plus the extras below, so one list covers them all.
		NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
		[set addObjectsFromArray:[RYGActionIcon availableSystemIcons]];
		[set addObjectsFromArray:[RYGHomeShortcutCatalog availableIcons]];
		[set addObjectsFromArray:@[
			@"ellipsis", @"ellipsis.circle", @"ellipsis.circle.fill", @"ellipsis.rectangle",
			@"circle.grid.2x2", @"circle.grid.3x3", @"square.grid.2x2", @"square.grid.3x3",
			@"line.3.horizontal", @"line.3.horizontal.circle", @"list.bullet", @"list.dash",
			@"plus", @"plus.circle", @"plus.circle.fill", @"plus.app", @"plus.square",
			@"minus", @"minus.circle", @"xmark", @"xmark.circle", @"xmark.circle.fill",
			@"checkmark", @"checkmark.circle", @"checkmark.circle.fill", @"checkmark.seal", @"checkmark.seal.fill",
			@"arrow.up", @"arrow.down", @"arrow.left", @"arrow.right", @"arrow.up.left.and.arrow.down.right",
			@"arrow.down.circle", @"arrow.down.circle.fill", @"arrow.up.circle", @"arrow.up.right.circle",
			@"arrow.up.forward.app", @"arrow.uturn.left", @"arrow.uturn.right", @"arrow.2.squarepath",
			@"arrow.triangle.2.circlepath", @"arrow.clockwise", @"arrow.counterclockwise",
			@"square.and.arrow.down", @"square.and.arrow.down.fill", @"square.and.arrow.up", @"square.and.arrow.up.fill",
			@"square.and.arrow.up.on.square", @"square.and.arrow.down.on.square",
			@"tray.and.arrow.down", @"tray.and.arrow.up", @"tray.full", @"icloud.and.arrow.down", @"icloud.and.arrow.up",
			@"square.stack", @"square.stack.3d.up", @"square.stack.3d.down.right", @"rectangle.stack", @"rectangle.on.rectangle",
			@"doc", @"doc.on.doc", @"doc.text", @"doc.plaintext", @"folder", @"folder.fill", @"archivebox",
			@"link", @"paperclip", @"text.quote", @"text.cursor", @"textformat", @"character.cursor.ibeam",
			@"photo", @"photo.fill", @"photo.on.rectangle", @"photo.on.rectangle.angled", @"photo.stack", @"photo.badge.arrow.down",
			@"camera", @"camera.fill", @"video", @"video.fill", @"play", @"play.fill", @"play.circle", @"play.circle.fill",
			@"pause", @"pause.circle", @"stop", @"stop.circle", @"speaker.wave.2", @"speaker.slash", @"music.note", @"music.note.list",
			@"waveform", @"mic", @"mic.fill", @"mic.slash",
			@"heart", @"heart.fill", @"heart.slash", @"star", @"star.fill", @"bookmark", @"bookmark.fill",
			@"bell", @"bell.fill", @"bell.slash", @"flag", @"flag.fill", @"tag", @"tag.fill",
			@"person", @"person.fill", @"person.circle", @"person.crop.circle", @"person.2", @"person.2.fill",
			@"person.badge.plus", @"person.badge.minus", @"person.crop.circle.badge.plus", @"at", @"at.circle",
			@"bubble.left", @"bubble.right", @"bubble.left.and.bubble.right", @"envelope", @"envelope.fill", @"paperplane", @"paperplane.fill",
			@"eye", @"eye.fill", @"eye.slash", @"eye.slash.fill", @"lock", @"lock.fill", @"lock.open", @"lock.shield",
			@"gearshape", @"gearshape.fill", @"gearshape.2", @"slider.horizontal.3", @"slider.vertical.3",
			@"wrench", @"wrench.and.screwdriver", @"hammer", @"wand.and.stars", @"sparkles", @"sparkle",
			@"bolt", @"bolt.fill", @"bolt.circle", @"flame", @"flame.fill", @"crown", @"crown.fill",
			@"moon", @"moon.fill", @"sun.max", @"sun.max.fill", @"gift", @"gift.fill",
			@"number", @"number.circle", @"grid", @"square.on.square", @"rectangle.grid.2x2",
			@"info.circle", @"questionmark.circle", @"exclamationmark.circle", @"exclamationmark.triangle",
			@"trash", @"trash.fill", @"pencil", @"square.and.pencil", @"scissors", @"square.on.circle",
			@"globe", @"map", @"location", @"location.fill", @"house", @"house.fill", @"magnifyingglass",
			@"clock", @"clock.arrow.circlepath", @"calendar", @"hourglass", @"timer",
		]];
		names = set.array;
	});
	return names;
}

+ (NSArray<NSString *> *)instagramIconNames {
	return RYGGeneratedIGIconNames() ?: @[];
}

#pragma mark Lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	NSMutableArray *sys = [NSMutableArray array];
	for (NSString *name in [RYGIconBrowserViewController systemIconNames]) {
		if ([UIImage systemImageNamed:name]) [sys addObject:name];
	}
	self.systemAll = sys;

	BOOL currentIsIG = [RYGIcon isIGAssetName:self.currentName];

	self.tabs = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"System"), RYGLocalized(@"Instagram")]];
	self.tabs.selectedSegmentIndex = currentIsIG ? 1 : 0;
	[self.tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
	self.navigationItem.titleView = self.tabs;

	UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
	search.searchResultsUpdater = self;
	search.obscuresBackgroundDuringPresentation = NO;
	search.searchBar.placeholder = RYGLocalized(@"Search");
	self.navigationItem.searchController = search;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

	UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
	layout.minimumInteritemSpacing = 10;
	layout.minimumLineSpacing = 10;
	layout.sectionInset = UIEdgeInsetsMake(16, 16, 24, 16);

	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.backgroundColor = UIColor.clearColor;
	self.collectionView.alwaysBounceVertical = YES;
	self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	self.collectionView.delegate = self;
	self.collectionView.dataSource = self;
	[self.collectionView registerClass:RYGIconBrowserCell.class forCellWithReuseIdentifier:@"cell"];
	[self.view addSubview:self.collectionView];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	[self loadInstagramCatalog];
	[self recomputeFiltered];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self scrollToSelected];
}

- (void)scrollToSelected {
	if (self.query.length) return;
	NSInteger item = NSNotFound;
	if (self.showsSpecialRow && [self.currentName isEqualToString:self.specialValue]) {
		item = 0;
	} else {
		NSUInteger idx = [self.filtered indexOfObject:self.currentName];
		if (idx != NSNotFound) item = (NSInteger)idx + (self.showsSpecialRow ? 1 : 0);
	}
	if (item == NSNotFound || item >= [self.collectionView numberOfItemsInSection:0]) return;
	[self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:0]
								atScrollPosition:UICollectionViewScrollPositionCenteredVertically
										animated:NO];
}

- (void)loadInstagramCatalog {
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray<NSString *> *raw = [RYGIconBrowserViewController instagramIconNames];
		NSMutableArray *ok = [NSMutableArray arrayWithCapacity:raw.count];
		for (NSString *name in raw) {
			if ([RYGIcon fbImageNamed:name]) [ok addObject:name];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) s = weakSelf;
			if (!s) return;
			s.igAll = ok;
			s.igReady = YES;
			if (s.tabs.selectedSegmentIndex == 1) {
				[s recomputeFiltered];
				[s scrollToSelected];
			}
		});
	});
}

#pragma mark Data

- (BOOL)isInstagramTab { return self.tabs.selectedSegmentIndex == 1; }

- (BOOL)showsSpecialRow {
	return !self.isInstagramTab && self.specialValue.length > 0 && self.query.length == 0;
}

- (void)recomputeFiltered {
	NSArray<NSString *> *source = self.isInstagramTab ? (self.igAll ?: @[]) : self.systemAll;
	NSString *q = self.query.lowercaseString;

	if (q.length == 0) {
		self.filtered = source;
	} else {
		NSMutableArray *out = [NSMutableArray array];
		for (NSString *name in source) {
			if ([name.lowercaseString containsString:q]) [out addObject:name];
		}
		self.filtered = out;
	}

	BOOL loadingIG = self.isInstagramTab && !self.igReady;
	loadingIG ? [self.spinner startAnimating] : [self.spinner stopAnimating];

	[self.collectionView reloadData];
}

- (void)tabChanged {
	[self recomputeFiltered];
	if (self.filtered.count) {
		[self.collectionView setContentOffset:CGPointMake(0, -self.collectionView.adjustedContentInset.top) animated:NO];
	}
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	self.query = searchController.searchBar.text ?: @"";
	[self recomputeFiltered];
}

#pragma mark Layout

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
	CGFloat available = self.view.bounds.size.width - 32;
	NSInteger cols = MAX(4, (NSInteger)floor(available / 84.0));
	CGFloat side = floor((available - layout.minimumInteritemSpacing * (cols - 1)) / cols);
	layout.itemSize = CGSizeMake(side, side);
}

#pragma mark Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
	return (NSInteger)self.filtered.count + (self.showsSpecialRow ? 1 : 0);
}

- (NSString *)nameForIndexPath:(NSIndexPath *)ip {
	if (self.showsSpecialRow) {
		if (ip.item == 0) return nil;
		return self.filtered[ip.item - 1];
	}
	return self.filtered[ip.item];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	RYGIconBrowserCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:ip];
	NSString *name = [self nameForIndexPath:ip];

	if (!name) {
		NSString *glyph = self.specialIcon.length ? self.specialIcon : @"ellipsis.circle";
		BOOL glyphIsIG = [glyph hasPrefix:@"ig_icon_"] || [glyph hasPrefix:@"bcn_"];
		UIImage *img = glyphIsIG ? [RYGIcon menuImageNamed:glyph pointSize:26]
								 : [RYGIcon sfImageNamed:glyph pointSize:24 weight:UIImageSymbolWeightSemibold];
		cell.iconView.contentMode = glyphIsIG ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
		[cell setImage:img caption:(self.specialTitle ?: RYGLocalized(@"Default")) selected:[self.currentName isEqualToString:self.specialValue]];
		cell.isAccessibilityElement = YES;
		cell.accessibilityLabel = self.specialTitle;
		return cell;
	}

	BOOL isIG = [RYGIcon isIGAssetName:name];
	UIImage *img = isIG ? [RYGIcon menuImageNamed:name pointSize:28]
						: [RYGIcon sfImageNamed:name pointSize:26 weight:UIImageSymbolWeightSemibold];
	cell.iconView.contentMode = isIG ? UIViewContentModeScaleAspectFit : UIViewContentModeCenter;
	[cell setImage:img selected:[name isEqualToString:self.currentName]];
	cell.isAccessibilityElement = YES;
	cell.accessibilityLabel = name;
	return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	[cv deselectItemAtIndexPath:ip animated:NO];
	NSString *name = [self nameForIndexPath:ip];
	NSString *picked = name ?: self.specialValue;

	UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[h impactOccurred];

	if (self.completion) self.completion(picked);
	[self.navigationController popViewControllerAnimated:YES];
}

@end
