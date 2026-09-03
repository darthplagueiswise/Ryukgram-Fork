#import "RYGGridFeedInfoViewController.h"
#import "RYGGridFeedInfo.h"
#import "RYGGridFeedOverlayView.h"
#import "RYGGridFeedService.h"
#import "../../../UI/RYGPopupChrome.h"
#import "../../../UI/RYGIcon.h"
#import "../../../Utils.h"

typedef NS_ENUM(NSInteger, RYGGridInfoSection) {
	RYGGridInfoSectionBehavior = 0,
	RYGGridInfoSectionElements,
	RYGGridInfoSectionReset,
};

static UIImage *rygSampleAvatar(void) {
	CGSize size = CGSizeMake(40, 40);
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
	return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[[UIColor colorWithRed:0.55 green:0.35 blue:0.95 alpha:1] setFill];
		[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 40, 40)] fill];
		UIImage *glyph = [[UIImage systemImageNamed:@"person.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		[[UIColor whiteColor] set];
		[glyph drawInRect:CGRectMake(11, 11, 18, 18)];
	}];
}

static UIImage *rygLoadRowIcon(NSString *name) {
	if (!name.length) return nil;
	return [RYGIcon imageNamed:name pointSize:20] ?: [UIImage systemImageNamed:name];
}

@interface RYGGridFeedInfoViewController ()
@property (nonatomic, copy) NSArray<NSString *> *order;
@property (nonatomic, strong) RYGGridFeedOverlayView *previewOverlay;
@property (nonatomic, strong) RYGGridFeedPost *samplePost;
@property (nonatomic, strong) UIImage *sampleAvatar;
@end

@implementation RYGGridFeedInfoViewController

- (instancetype)init {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	self.title = RYGLocalized(@"Post info");
	_order = [RYGGridFeedInfo orderedElementIDs];
	_sampleAvatar = rygSampleAvatar();

	RYGGridFeedPost *p = [RYGGridFeedPost new];
	p.code = @"preview";
	p.username = @"ryukgram";
	p.likeCount = 12300;
	p.commentCount = 341;
	p.viewCount = 88200;
	p.mediaType = RYGGridFeedMediaTypeVideo;
	p.takenAt = [[NSDate date] timeIntervalSince1970] - 7200;
	_samplePost = p;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
	[self buildPreviewHeader];
}

#pragma mark - Preview

- (void)buildPreviewHeader {
	CGFloat tile = 168;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, tile + 54)];

	UILabel *caption = [UILabel new];
	caption.translatesAutoresizingMaskIntoConstraints = NO;
	caption.text = RYGLocalized(@"Live preview");
	caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	caption.textColor = UIColor.secondaryLabelColor;
	caption.textAlignment = NSTextAlignmentCenter;
	[header addSubview:caption];

	UIView *card = [[UIView alloc] init];
	card.translatesAutoresizingMaskIntoConstraints = NO;
	card.backgroundColor = UIColor.secondarySystemBackgroundColor;
	card.layer.cornerRadius = 14;
	card.layer.cornerCurve = kCACornerCurveContinuous;
	card.clipsToBounds = YES;
	[header addSubview:card];

	CAGradientLayer *photo = [CAGradientLayer layer];
	photo.colors = @[(id)[UIColor colorWithRed:0.15 green:0.22 blue:0.38 alpha:1].CGColor,
	                 (id)[UIColor colorWithRed:0.38 green:0.20 blue:0.42 alpha:1].CGColor];
	photo.startPoint = CGPointMake(0, 0);
	photo.endPoint = CGPointMake(1, 1);
	photo.frame = CGRectMake(0, 0, tile, tile);
	[card.layer addSublayer:photo];

	self.previewOverlay = [[RYGGridFeedOverlayView alloc] initWithFrame:CGRectMake(0, 0, tile, tile)];
	[card addSubview:self.previewOverlay];

	[NSLayoutConstraint activateConstraints:@[
		[caption.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
		[caption.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
		[card.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:12],
		[card.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
		[card.widthAnchor constraintEqualToConstant:tile],
		[card.heightAnchor constraintEqualToConstant:tile],
	]];

	self.tableView.tableHeaderView = header;
	[self refreshPreview];
}

- (void)refreshPreview {
	self.previewOverlay.avatarImage = self.sampleAvatar;
	[self.previewOverlay configureWithPost:self.samplePost];
}

#pragma mark - Data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	switch (s) {
		case RYGGridInfoSectionBehavior: return 4;
		case RYGGridInfoSectionElements: return self.order.count;
		default: return 1;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if (s == RYGGridInfoSectionElements) return RYGLocalized(@"Info on each post");
	return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == RYGGridInfoSectionElements)
		return RYGLocalized(@"Toggle each item on or off. Drag the ≡ handle to reorder how they stack on the tile.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == RYGGridInfoSectionBehavior) return [self behaviorCellForRow:ip.row];
	if (ip.section == RYGGridInfoSectionElements) return [self elementCellForRow:ip.row];
	return [self resetCell];
}

- (UISwitch *)switchOn:(BOOL)on action:(SEL)action id:(NSString *)ident {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [RYGUtils RYGColor_Primary];
	sw.accessibilityIdentifier = ident;
	[sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

- (UITableViewCell *)behaviorCellForRow:(NSInteger)row {
	if (row == 3) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
		cfg.text = RYGLocalized(@"Date format");
		cfg.image = rygLoadRowIcon(@"ig_icon_clock_dotted_pano_outline_24");
		cfg.imageProperties.tintColor = UIColor.labelColor;
		cfg.imageProperties.maximumSize = CGSizeMake(24, 24);
		cfg.imageProperties.reservedLayoutSize = CGSizeMake(24, 24);
		cfg.imageToTextPadding = 14;
		cfg.secondaryText = [RYGGridFeedInfo nameForDateFormat:[RYGGridFeedInfo dateFormat]];
		cell.contentConfiguration = cfg;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	NSString *title, *key, *sf;
	switch (row) {
		case 0: title = RYGLocalized(@"Show avatar"); key = @"grid_feed_show_avatar"; sf = @"ig_icon_user_circle_pano_outline_24"; break;
		case 1: title = RYGLocalized(@"Media type badge"); key = @"grid_feed_show_type_badge"; sf = @"ig_icon_photo_outline_24"; break;
		default: title = RYGLocalized(@"Short numbers"); key = @"grid_feed_shortened_numbers"; sf = @"ig_icon_info_outline_24"; break;
	}
	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = title;
	cfg.image = rygLoadRowIcon(sf);
	cfg.imageProperties.tintColor = UIColor.labelColor;
	cfg.imageProperties.maximumSize = CGSizeMake(24, 24);
	cfg.imageProperties.reservedLayoutSize = CGSizeMake(24, 24);
	cfg.imageToTextPadding = 14;
	cell.contentConfiguration = cfg;

	UISwitch *sw = [self switchOn:[RYGUtils getBoolPref:key] action:@selector(behaviorToggleChanged:) id:key];
	cell.accessoryView = sw;
	cell.editingAccessoryView = sw;
	return cell;
}

- (UITableViewCell *)elementCellForRow:(NSInteger)row {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	if (row < 0 || row >= (NSInteger)self.order.count) return cell;
	NSString *el = self.order[row];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UIImageView *icon = [[UIImageView alloc] initWithImage:rygLoadRowIcon([RYGGridFeedInfo rowIconForElement:el])];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.tintColor = UIColor.labelColor;
	icon.contentMode = UIViewContentModeScaleAspectFit;

	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = [RYGGridFeedInfo titleForElement:el];
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;

	UISwitch *sw = [self switchOn:[RYGGridFeedInfo isElementEnabled:el] action:@selector(elementToggleChanged:) id:el];
	sw.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *cv = cell.contentView;
	[cv addSubview:icon];
	[cv addSubview:label];
	[cv addSubview:sw];
	UILayoutGuide *m = cv.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[icon.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:24],
		[icon.heightAnchor constraintEqualToConstant:24],
		[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
		[label.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[sw.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
		[sw.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-12],
	]];
	return cell;
}

- (UITableViewCell *)resetCell {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = RYGLocalized(@"Reset to defaults");
	cfg.textProperties.color = UIColor.systemRedColor;
	cfg.textProperties.alignment = UIListContentTextAlignmentCenter;
	cell.contentConfiguration = cfg;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == RYGGridInfoSectionReset) { [self confirmReset]; return; }
	if (ip.section == RYGGridInfoSectionBehavior && ip.row == 3) [self pickDateFormat];
}

- (void)pickDateFormat {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Date format") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSNumber *n in @[@(RYGGridDateFormatRelative), @(RYGGridDateFormatDate), @(RYGGridDateFormatDateTime), @(RYGGridDateFormatTime)]) {
		RYGGridDateFormat f = (RYGGridDateFormat)n.integerValue;
		[sheet addAction:[UIAlertAction actionWithTitle:[RYGGridFeedInfo nameForDateFormat:f] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			[RYGGridFeedInfo setDateFormat:f];
			// Picking a format with the chip hidden would change nothing visible.
			[RYGGridFeedInfo setElement:kRYGGridInfoDate enabled:YES];
			[self.tableView reloadData];
			[self refreshPreview];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.tableView;
	sheet.popoverPresentationController.sourceRect = CGRectMake(self.tableView.bounds.size.width/2, 200, 1, 1);
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmReset {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
	                                                              message:RYGLocalized(@"Restores the default post info, order and options for the grid feed.")
	                                                       preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		[RYGGridFeedInfo resetToDefaults];
		self.order = [RYGGridFeedInfo orderedElementIDs];
		[self.tableView reloadData];
		[self refreshPreview];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)behaviorToggleChanged:(UISwitch *)sender {
	if (sender.accessibilityIdentifier.length) [RYGUtils setPref:@(sender.isOn) forKey:sender.accessibilityIdentifier];
	[self refreshPreview];
}

- (void)elementToggleChanged:(UISwitch *)sender {
	if (sender.accessibilityIdentifier.length) [RYGGridFeedInfo setElement:sender.accessibilityIdentifier enabled:sender.isOn];
	[self refreshPreview];
}

#pragma mark - Reorder

- (BOOL)isReorderableSection:(NSInteger)section { return section == RYGGridInfoSectionElements; }

- (void)didMoveRowFromIndexPath:(NSIndexPath *)src toIndexPath:(NSIndexPath *)dst {
	NSInteger from = src.row, to = dst.row;
	if (from < 0 || from >= (NSInteger)self.order.count) return;
	NSMutableArray *m = [self.order mutableCopy];
	NSString *moved = m[from];
	[m removeObjectAtIndex:from];
	[m insertObject:moved atIndex:MIN(to, (NSInteger)m.count)];
	self.order = m;
	[RYGGridFeedInfo setOrder:m];
	[self refreshPreview];
}

@end
