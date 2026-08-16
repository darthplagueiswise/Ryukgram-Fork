#import "RYGProfileCardDetailsViewController.h"
#import "../UI/RYGIcon.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

static NSString *const kOrderKey = @"reel_card_order";
static NSString *const kDefaultOrder = @"date,reposts,shares,comments,likes,views";

static NSArray<NSString *> *rygCanon(void) {
	return @[@"views", @"likes", @"comments", @"shares", @"reposts", @"date"];
}

static NSString *rygMetricPrefKey(NSString *m) {
	if ([m isEqualToString:@"views"])    return @"reel_card_full_views";
	if ([m isEqualToString:@"likes"])    return @"reel_card_show_likes";
	if ([m isEqualToString:@"comments"]) return @"reel_card_show_comments";
	if ([m isEqualToString:@"shares"])   return @"reel_card_show_shares";
	if ([m isEqualToString:@"reposts"])  return @"reel_card_show_reposts";
	return @"reel_card_show_date";
}

static NSString *rygMetricTitle(NSString *m) {
	if ([m isEqualToString:@"views"])    return RYGLocalized(@"View count");
	if ([m isEqualToString:@"likes"])    return RYGLocalized(@"Like count");
	if ([m isEqualToString:@"comments"]) return RYGLocalized(@"Comment count");
	if ([m isEqualToString:@"shares"])   return RYGLocalized(@"Share count");
	if ([m isEqualToString:@"reposts"])  return RYGLocalized(@"Repost count");
	return RYGLocalized(@"Upload date");
}

static NSString *rygMetricIcon(NSString *m) {
	if ([m isEqualToString:@"views"])    return @"ig_icon_eye_outline_24";
	if ([m isEqualToString:@"likes"])    return @"direct-like";
	if ([m isEqualToString:@"comments"]) return @"ig_icon_comment_outline_24";
	if ([m isEqualToString:@"shares"])   return @"ig_icon_direct_prism_outline_24";
	if ([m isEqualToString:@"reposts"])  return @"ig_icon_reshare_outline_24";
	return @"clock-small";
}

static UIColor *rygBackground(void) {
	return [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
}

static UIImage *rygLoadIcon(NSString *name) {
	if (!name.length) return nil;
	return [RYGIcon imageNamed:name pointSize:20] ?: [UIImage systemImageNamed:name];
}

static UITableViewCell *rygCell(void) {
	return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

static UISwitch *rygSwitch(BOOL on, id target, SEL action) {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [RYGUtils RYGColor_Primary];
	[sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

static void rygInstallReorderRow(UITableViewCell *cell, NSString *iconName, NSString *title, UIView *accessory) {
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UIImageView *icon = [[UIImageView alloc] initWithImage:rygLoadIcon(iconName)];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.tintColor = UIColor.labelColor;
	icon.contentMode = UIViewContentModeScaleAspectFit;

	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = title ?: @"";
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	label.numberOfLines = 1;

	UIView *cv = cell.contentView;
	[cv addSubview:icon];
	[cv addSubview:label];
	accessory.translatesAutoresizingMaskIntoConstraints = NO;
	[cv addSubview:accessory];

	UILayoutGuide *m = cv.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[icon.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[icon.widthAnchor constraintEqualToConstant:24.0],
		[icon.heightAnchor constraintEqualToConstant:24.0],
		[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
		[label.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[accessory.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
		[accessory.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:accessory.leadingAnchor constant:-12.0],
	]];
}

typedef NS_ENUM(NSInteger, RYGCardSection) {
	RYGCardSectionBehavior = 0,
	RYGCardSectionMetrics,
	RYGCardSectionApply,
};

typedef NS_ENUM(NSInteger, RYGBehaviorRow) {
	RYGBehaviorRowMaster = 0,
	RYGBehaviorRowShortNumbers,
	RYGBehaviorRowFetchMissing,
};

@interface RYGProfileCardDetailsViewController ()
@property (nonatomic, copy) NSArray<NSString *> *order;
@end

@implementation RYGProfileCardDetailsViewController

- (instancetype)init {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	self.title = RYGLocalized(@"Card details");
	_order = [self sanitizedOrder];
	return self;
}

- (NSArray<NSString *> *)sanitizedOrder {
	NSString *raw = [RYGUtils getStringPref:kOrderKey] ?: @"";
	NSArray<NSString *> *canon = rygCanon();
	NSMutableArray<NSString *> *out = [NSMutableArray array];
	for (NSString *p in [raw componentsSeparatedByString:@","]) {
		NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([canon containsObject:t] && ![out containsObject:t]) [out addObject:t];
	}
	for (NSString *c in canon) if (![out containsObject:c]) [out addObject:c];
	return out;
}

- (void)persistOrder {
	[RYGUtils setPref:[self.order componentsJoinedByString:@","] forKey:kOrderKey];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = rygBackground();
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
}

#pragma mark - Data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	switch (s) {
		case RYGCardSectionBehavior: return 3;
		case RYGCardSectionMetrics:  return self.order.count;
		default:                     return 2;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == RYGCardSectionBehavior)
		return RYGLocalized(@"Master switch for all card stats. Fetch missing counts uses Instagram's API and may hit rate limits.");
	if (s == RYGCardSectionMetrics)
		return RYGLocalized(@"Toggle each stat on or off. Drag the ≡ handle to reorder how they stack on the card.");
	return RYGLocalized(@"Applying restarts Instagram to load your changes.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == RYGCardSectionBehavior) return [self behaviorCellForRow:ip.row];
	if (ip.section == RYGCardSectionMetrics)  return [self metricCellForRow:ip.row];
	return ip.row == 0 ? [self applyCell] : [self resetCell];
}

- (UITableViewCell *)behaviorCellForRow:(NSInteger)row {
	UITableViewCell *cell = rygCell();
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	NSString *title, *key, *sf;
	switch (row) {
		case RYGBehaviorRowMaster:      title = RYGLocalized(@"Show card details"); key = @"reel_card_master_enabled"; sf = @"rectangle.grid.1x2"; break;
		case RYGBehaviorRowShortNumbers: title = RYGLocalized(@"Short numbers"); key = @"reel_card_shortened_numbers"; sf = @"number"; break;
		default:                        title = RYGLocalized(@"Fetch missing counts"); key = @"reel_card_fetch_missing"; sf = @"arrow.down.circle"; break;
	}

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = title;
	config.image = rygLoadIcon(sf);
	config.imageProperties.tintColor = UIColor.labelColor;
	config.imageProperties.maximumSize = CGSizeMake(24.0, 24.0);
	config.imageProperties.reservedLayoutSize = CGSizeMake(24.0, 24.0);
	config.imageToTextPadding = 14.0;
	cell.contentConfiguration = config;

	UISwitch *sw = rygSwitch([RYGUtils getBoolPref:key], self, @selector(behaviorToggleChanged:));
	sw.accessibilityIdentifier = key;
	cell.accessoryView = sw;
	cell.editingAccessoryView = sw;
	return cell;
}

- (UITableViewCell *)metricCellForRow:(NSInteger)row {
	UITableViewCell *cell = rygCell();
	if (row < 0 || row >= (NSInteger)self.order.count) return cell;
	NSString *m = self.order[row];
	UISwitch *sw = rygSwitch([RYGUtils getBoolPref:rygMetricPrefKey(m)], self, @selector(metricToggleChanged:));
	sw.accessibilityIdentifier = m;
	rygInstallReorderRow(cell, rygMetricIcon(m), rygMetricTitle(m), sw);
	return cell;
}

- (UITableViewCell *)applyCell {
	UITableViewCell *cell = rygCell();
	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = RYGLocalized(@"Apply & restart");
	config.textProperties.color = [RYGUtils RYGColor_Primary];
	config.textProperties.alignment = UIListContentTextAlignmentCenter;
	cell.contentConfiguration = config;
	return cell;
}

- (UITableViewCell *)resetCell {
	UITableViewCell *cell = rygCell();
	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = RYGLocalized(@"Reset to defaults");
	config.textProperties.color = UIColor.systemRedColor;
	config.textProperties.alignment = UIListContentTextAlignmentCenter;
	cell.contentConfiguration = config;
	return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section != RYGCardSectionApply) return;
	if (ip.row == 0) [RYGUtils showRestartConfirmation];
	else [self confirmReset];
}

- (void)confirmReset {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
																   message:RYGLocalized(@"Restores the default stats, order, and options for profile card details.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		for (NSString *k in @[@"reel_card_master_enabled", @"reel_card_full_views", @"reel_card_show_likes",
		                      @"reel_card_show_comments", @"reel_card_show_shares", @"reel_card_show_reposts",
		                      @"reel_card_show_date", @"reel_card_shortened_numbers", @"reel_card_fetch_missing"])
			[RYGUtils setPref:@(NO) forKey:k];
		[RYGUtils setPref:kDefaultOrder forKey:kOrderKey];
		self.order = [self sanitizedOrder];
		[self.tableView reloadData];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Toggles

- (void)behaviorToggleChanged:(UISwitch *)sender {
	if (sender.accessibilityIdentifier.length)
		[RYGUtils setPref:@(sender.isOn) forKey:sender.accessibilityIdentifier];
}

- (void)metricToggleChanged:(UISwitch *)sender {
	NSString *m = sender.accessibilityIdentifier;
	if (m.length) [RYGUtils setPref:@(sender.isOn) forKey:rygMetricPrefKey(m)];
}

#pragma mark - Reorder

- (BOOL)isReorderableSection:(NSInteger)section { return section == RYGCardSectionMetrics; }

- (void)didMoveRowFromIndexPath:(NSIndexPath *)src toIndexPath:(NSIndexPath *)dst {
	NSInteger from = src.row, to = dst.row;
	if (from < 0 || from >= (NSInteger)self.order.count) return;
	NSMutableArray *m = [self.order mutableCopy];
	NSString *moved = m[from];
	[m removeObjectAtIndex:from];
	[m insertObject:moved atIndex:MIN(to, (NSInteger)m.count)];
	self.order = m;
	[self persistOrder];
}

@end
