#import "RYGGridFeedSettingsViewController.h"
#import "RYGGridFeedInfoViewController.h"
#import "RYGGridToggleSettingsViewController.h"
#import "RYGGridFeedInfo.h"
#import "RYGGridFeedOverlayView.h"
#import "RYGGridFeedService.h"
#import "../../../UI/RYGPopupChrome.h"
#import "../../../UI/RYGIcon.h"
#import "../../../Utils.h"

static UIImage *rygRowIcon(NSString *name) {
	return [RYGIcon imageNamed:name pointSize:22] ?: [UIImage systemImageNamed:name];
}

typedef NS_ENUM(NSInteger, RYGGridSettingsSection) {
	RYGGridSettingsSectionMaster = 0,
	RYGGridSettingsSectionConfig,
};

@interface RYGGridFeedSettingsViewController ()
@property (nonatomic, strong) UIView *previewContainer;
@property (nonatomic, strong) UISegmentedControl *columnsControl;
@property (nonatomic, strong) NSArray<RYGGridFeedPost *> *samplePosts;
@property (nonatomic, strong) NSArray<UIImage *> *sampleAvatars;
@property (nonatomic) CGFloat lastPreviewWidth;
@end

@implementation RYGGridFeedSettingsViewController

- (instancetype)init {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	self.title = RYGLocalized(@"Grid feed");
	[self buildSamples];
	return self;
}

- (void)buildSamples {
	NSArray *specs = @[
		@[@"ava.styles", @(842000), @(5100), @(1240000), @(RYGGridFeedMediaTypeVideo)],
		@[@"m.khaled", @(12300), @(341), @(0), @(RYGGridFeedMediaTypePhoto)],
		@[@"trips.daily", @(48200), @(903), @(0), @(RYGGridFeedMediaTypeCarousel)],
		@[@"chef.leo", @(2100), @(88), @(0), @(RYGGridFeedMediaTypePhoto)],
		@[@"n.arch", @(377000), @(2400), @(4900000), @(RYGGridFeedMediaTypeVideo)],
		@[@"sara.k", @(9400), @(210), @(0), @(RYGGridFeedMediaTypeCarousel)],
	];
	NSMutableArray *posts = [NSMutableArray array];
	NSMutableArray *avatars = [NSMutableArray array];
	NSArray *colors = @[[UIColor systemPurpleColor], [UIColor systemTealColor], [UIColor systemPinkColor],
	                    [UIColor systemOrangeColor], [UIColor systemBlueColor], [UIColor systemGreenColor]];
	NSInteger i = 0;
	for (NSArray *s in specs) {
		RYGGridFeedPost *p = [RYGGridFeedPost new];
		p.code = [NSString stringWithFormat:@"preview%ld", (long)i];
		p.username = s[0];
		p.likeCount = [s[1] integerValue];
		p.commentCount = [s[2] integerValue];
		p.viewCount = [s[3] integerValue];
		p.mediaType = [s[4] integerValue];
		// Spread across hours, days and past a year so every date format shows its real shape.
		static const double kAges[] = { 1800, 25200, 194400, 1900800, 9500000, 41000000 };
		p.takenAt = [[NSDate date] timeIntervalSince1970] - kAges[i % 6];
		[posts addObject:p];
		[avatars addObject:[self avatarWithColor:colors[i % colors.count]]];
		i++;
	}
	self.samplePosts = posts;
	self.sampleAvatars = avatars;
}

- (UIImage *)avatarWithColor:(UIColor *)color {
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
	return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[color setFill];
		[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 40, 40)] fill];
		[[UIColor whiteColor] set];
		[[[UIImage systemImageNamed:@"person.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] drawInRect:CGRectMake(11, 11, 18, 18)];
	}];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
	[self buildPreviewHeader];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuildPreviewTiles];
	[self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat w = self.previewContainer.bounds.size.width;
	if (w > 0 && w != self.lastPreviewWidth) {
		self.lastPreviewWidth = w;
		[self rebuildPreviewTiles];
	}
}

#pragma mark - Preview header

- (void)buildPreviewHeader {
	CGFloat previewH = round(UIScreen.mainScreen.bounds.size.height * 0.40);
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, previewH + 96)];

	UILabel *caption = [UILabel new];
	caption.translatesAutoresizingMaskIntoConstraints = NO;
	caption.text = RYGLocalized(@"Live preview");
	caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	caption.textColor = UIColor.secondaryLabelColor;
	[header addSubview:caption];

	self.previewContainer = [UIView new];
	self.previewContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.previewContainer.clipsToBounds = YES;
	[header addSubview:self.previewContainer];

	self.columnsControl = [[UISegmentedControl alloc] initWithItems:@[@"2", @"3", @"4", @"5", @"6"]];
	self.columnsControl.translatesAutoresizingMaskIntoConstraints = NO;
	self.columnsControl.selectedSegmentIndex = [RYGGridFeedInfo columns] - 2;
	[self.columnsControl addTarget:self action:@selector(columnsChanged:) forControlEvents:UIControlEventValueChanged];
	[header addSubview:self.columnsControl];

	UILabel *colLabel = [UILabel new];
	colLabel.translatesAutoresizingMaskIntoConstraints = NO;
	colLabel.text = RYGLocalized(@"Columns");
	colLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	colLabel.textColor = UIColor.secondaryLabelColor;
	[header addSubview:colLabel];

	[NSLayoutConstraint activateConstraints:@[
		[caption.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
		[caption.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],

		[self.previewContainer.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:8],
		[self.previewContainer.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
		[self.previewContainer.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
		[self.previewContainer.heightAnchor constraintEqualToConstant:previewH],

		[colLabel.topAnchor constraintEqualToAnchor:self.previewContainer.bottomAnchor constant:16],
		[colLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
		[colLabel.centerYAnchor constraintEqualToAnchor:self.columnsControl.centerYAnchor],

		[self.columnsControl.topAnchor constraintEqualToAnchor:self.previewContainer.bottomAnchor constant:10],
		[self.columnsControl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
		[self.columnsControl.leadingAnchor constraintGreaterThanOrEqualToAnchor:colLabel.trailingAnchor constant:12],
	]];

	self.tableView.tableHeaderView = header;
	[header layoutIfNeeded];
	[self rebuildPreviewTiles];
}

- (void)rebuildPreviewTiles {
	if (!self.previewContainer) return;
	[self.previewContainer layoutIfNeeded];
	for (UIView *v in self.previewContainer.subviews) [v removeFromSuperview];

	CGFloat W = self.previewContainer.bounds.size.width;
	if (W <= 0) return;
	NSInteger cols = [RYGGridFeedInfo columns];
	CGFloat gap = 2;
	CGFloat tile = floor((W - gap * (cols - 1)) / cols);
	CGFloat tileH = [RYGUtils getBoolPref:@"grid_feed_tall_cells"] ? round(tile * 1.34) : tile;
	CGFloat H = self.previewContainer.bounds.size.height;
	NSInteger rows = (NSInteger)ceil(H / (tileH + gap));

	NSArray *grads = @[
		@[[UIColor colorWithRed:0.15 green:0.22 blue:0.38 alpha:1], [UIColor colorWithRed:0.38 green:0.20 blue:0.42 alpha:1]],
		@[[UIColor colorWithRed:0.32 green:0.18 blue:0.30 alpha:1], [UIColor colorWithRed:0.10 green:0.28 blue:0.34 alpha:1]],
		@[[UIColor colorWithRed:0.20 green:0.30 blue:0.20 alpha:1], [UIColor colorWithRed:0.30 green:0.28 blue:0.12 alpha:1]],
	];

	NSInteger idx = 0;
	for (NSInteger r = 0; r < rows; r++) {
		for (NSInteger c = 0; c < cols; c++) {
			CGRect frame = CGRectMake(c * (tile + gap), r * (tileH + gap), tile, tileH);
			UIView *t = [[UIView alloc] initWithFrame:frame];
			t.clipsToBounds = YES;
			CAGradientLayer *g = [CAGradientLayer layer];
			NSArray *pair = grads[idx % grads.count];
			g.colors = @[(id)[pair[0] CGColor], (id)[pair[1] CGColor]];
			g.startPoint = CGPointMake(0, 0);
			g.endPoint = CGPointMake(1, 1);
			g.frame = t.bounds;
			[t.layer addSublayer:g];

			RYGGridFeedOverlayView *ov = [[RYGGridFeedOverlayView alloc] initWithFrame:t.bounds];
			ov.avatarImage = self.sampleAvatars[idx % self.sampleAvatars.count];
			[ov configureWithPost:self.samplePosts[idx % self.samplePosts.count]];
			[t addSubview:ov];
			[self.previewContainer addSubview:t];
			idx++;
		}
	}
}

- (void)columnsChanged:(UISegmentedControl *)sc {
	[RYGUtils setPref:@(sc.selectedSegmentIndex + 2) forKey:@"grid_feed_columns"];
	[self rebuildPreviewTiles];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	return s == RYGGridSettingsSectionMaster ? 1 : 4;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == RYGGridSettingsSectionMaster)
		return RYGLocalized(@"Replaces the home feed with a grid of posts. Switching to Instagram's own feed keeps the feature on and hands the feed straight back. Pinch to change columns, tap a post to open it. The For You / Following switch stays in sync with Main feed.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	if (ip.section == RYGGridSettingsSectionMaster) {
		UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
		cfg.text = RYGLocalized(@"Grid feed");
		cfg.image = rygRowIcon(@"ig_icon_photo_grid_tall_filled_24");
		cfg.imageProperties.tintColor = UIColor.labelColor;
		cell.contentConfiguration = cfg;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *sw = UISwitch.new;
		sw.on = [RYGGridFeedInfo active];
		sw.onTintColor = [RYGUtils RYGColor_Primary];
		[sw addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		return cell;
	}
	if (ip.row == 0) {
		UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
		cfg.text = RYGLocalized(@"Post info");
		cfg.secondaryText = RYGLocalized(@"Reorder and toggle stats on each tile");
		cfg.image = rygRowIcon(@"ig_icon_sliders_outline_24");
		cfg.imageProperties.tintColor = UIColor.labelColor;
		cell.contentConfiguration = cfg;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	if (ip.row == 1) {
		UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
		cfg.text = RYGLocalized(@"Hide stories in grid");
		cfg.image = rygRowIcon(@"ig_icon_story_outline_24");
		cfg.imageProperties.tintColor = UIColor.labelColor;
		cell.contentConfiguration = cfg;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *sw = UISwitch.new;
		sw.on = [RYGUtils getBoolPref:@"grid_feed_hide_stories"];
		sw.onTintColor = [RYGUtils RYGColor_Primary];
		[sw addTarget:self action:@selector(hideStoriesChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		return cell;
	}
	if (ip.row == 2) {
		UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
		cfg.text = RYGLocalized(@"Taller cells");
		cfg.secondaryText = RYGLocalized(@"Portrait tiles instead of squares");
		cfg.image = rygRowIcon(@"ig_icon_layout_outline_24");
		cfg.imageProperties.tintColor = UIColor.labelColor;
		cell.contentConfiguration = cfg;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *sw = UISwitch.new;
		sw.on = [RYGUtils getBoolPref:@"grid_feed_tall_cells"];
		sw.onTintColor = [RYGUtils RYGColor_Primary];
		[sw addTarget:self action:@selector(tallChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		return cell;
	}
	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = RYGLocalized(@"Switch button");
	cfg.secondaryText = [RYGGridFeedInfo nameForTogglePlacement:[RYGGridFeedInfo togglePlacement]];
	cfg.image = rygRowIcon(@"ig_icon_hand_point_outline_24");
	cfg.imageProperties.tintColor = UIColor.labelColor;
	cell.contentConfiguration = cfg;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section != RYGGridSettingsSectionConfig) return;
	if (ip.row == 0) [self.navigationController pushViewController:[RYGGridFeedInfoViewController new] animated:YES];
	else if (ip.row == 3) [self.navigationController pushViewController:[RYGGridToggleSettingsViewController new] animated:YES];
}

- (void)masterChanged:(UISwitch *)sw {
	[RYGGridFeedInfo setActive:sw.isOn];
	[RYGUtils showRestartConfirmation];
}

- (void)hideStoriesChanged:(UISwitch *)sw {
	[RYGUtils setPref:@(sw.isOn) forKey:@"grid_feed_hide_stories"];
}

- (void)tallChanged:(UISwitch *)sw {
	[RYGUtils setPref:@(sw.isOn) forKey:@"grid_feed_tall_cells"];
	[self rebuildPreviewTiles];
}

@end
