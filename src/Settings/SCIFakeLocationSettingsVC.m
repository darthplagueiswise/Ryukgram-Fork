#import "SCIFakeLocationSettingsVC.h"
#import "SCIFakeLocationPickerVC.h"
#import "../Utils.h"

static NSString *const kEnabled = @"fake_location_enabled";
static NSString *const kShowBtn = @"show_fake_location_map_button";
static NSString *const kLat = @"fake_location_lat";
static NSString *const kLon = @"fake_location_lon";
static NSString *const kName = @"fake_location_name";
static NSString *const kPresets = @"fake_location_presets";
static NSString *const kMapBtnChanged = @"SCIFakeLocationMapBtnPrefChanged";

typedef NS_ENUM(NSInteger, SCIFakeLocationSection) {
	SCIFakeLocationSectionToggle,
	SCIFakeLocationSectionCurrent,
	SCIFakeLocationSectionPresets,
};

@interface SCIFakeLocationSettingsVC ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SCIFakeLocationSettingsVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Fake location");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;

	[self.view addSubview:self.tableView];
}

#pragma mark - Helpers

- (NSUserDefaults *)defaults {
	return NSUserDefaults.standardUserDefaults;
}

- (NSArray<NSDictionary *> *)presets {
	id raw = [self.defaults objectForKey:kPresets];
	return [raw isKindOfClass:NSArray.class] ? raw : @[];
}

- (void)setPresets:(NSArray<NSDictionary *> *)presets {
	[self.defaults setObject:(presets ?: @[]) forKey:kPresets];
}

- (double)currentLat {
	return [[self.defaults objectForKey:kLat] doubleValue];
}

- (double)currentLon {
	return [[self.defaults objectForKey:kLon] doubleValue];
}

- (NSString *)currentName {
	NSString *name = [self.defaults objectForKey:kName];
	return [name isKindOfClass:NSString.class] ? name : @"";
}

- (CLLocationCoordinate2D)currentCoord {
	return CLLocationCoordinate2DMake(self.currentLat, self.currentLon);
}

- (NSString *)coordTextWithLat:(double)lat lon:(double)lon {
	return [NSString stringWithFormat:@"%.5f, %.5f", lat, lon];
}

- (void)postMapButtonRefresh {
	[NSNotificationCenter.defaultCenter postNotificationName:kMapBtnChanged object:nil];
}

- (void)applyLat:(double)lat lon:(double)lon name:(NSString *)name enable:(BOOL)enable {
	NSUserDefaults *d = self.defaults;

	[d setObject:@(lat) forKey:kLat];
	[d setObject:@(lon) forKey:kLon];
	[d setObject:(name ?: @"") forKey:kName];

	if (enable) [d setBool:YES forKey:kEnabled];

	[self.tableView reloadData];
	[self postMapButtonRefresh];
}

- (UITableViewCell *)cellForTableView:(UITableView *)tableView reuseID:(NSString *)reuseID {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
	}

	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.contentView.alpha = 1.0;

	return cell;
}

- (UISwitch *)switchWithOn:(BOOL)on action:(SEL)action {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	sw.onTintColor = [SCIUtils SCIColor_Primary];
	[sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

- (void)presentPickerWithTitle:(NSString *)title completion:(void (^)(double lat, double lon, NSString *name))completion {
	SCIFakeLocationPickerVC *vc = SCIFakeLocationPickerVC.new;
	vc.initialCoord = self.currentCoord;
	vc.titleText = title;
	vc.onPick = completion;

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	[self presentViewController:nav animated:YES completion:nil];
}

- (void)askNameAndSavePresetWithLat:(double)lat lon:(double)lon name:(NSString *)name {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Save preset") message:nil preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = SCILocalized(@"Name");
		field.text = name;
		field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		NSString *finalName = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : name;
		NSDictionary *preset = @{@"name": finalName ?: @"", @"lat": @(lat), @"lon": @(lon)};

		NSMutableArray *items = self.presets.mutableCopy ?: NSMutableArray.array;
		[items addObject:preset];

		[self setPresets:items];
		[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SCIFakeLocationSectionPresets] withRowAnimation:UITableViewRowAnimationAutomatic];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == SCIFakeLocationSectionToggle) return 2;
	if (section == SCIFakeLocationSectionCurrent) return 2;
	return self.presets.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == SCIFakeLocationSectionCurrent) return SCILocalized(@"Current location");
	if (section == SCIFakeLocationSectionPresets) return SCILocalized(@"Saved locations");
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == SCIFakeLocationSectionToggle) return SCILocalized(@"When on, Instagram location requests return your selected fake location. The map button adds a quick shortcut inside Friends Map.");
	if (section == SCIFakeLocationSectionPresets) return SCILocalized(@"Tap a preset to make it active. Swipe left to delete.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == SCIFakeLocationSectionToggle) {
		return [self switchCellForTableView:tableView indexPath:indexPath];
	}

	if (indexPath.section == SCIFakeLocationSectionCurrent) {
		return indexPath.row == 0
			? [self currentLocationCellForTableView:tableView]
			: [self selectLocationCellForTableView:tableView];
	}

	return [self presetCellForTableView:tableView indexPath:indexPath];
}

#pragma mark - Cells

- (UITableViewCell *)switchCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	BOOL enabledRow = indexPath.row == 0;
	NSString *title = enabledRow ? SCILocalized(@"Enable fake location") : SCILocalized(@"Show map button");
	NSString *subtitle = enabledRow ? SCILocalized(@"Override Instagram location reads.") : SCILocalized(@"Show the quick button in Friends Map.");
	NSString *key = enabledRow ? kEnabled : kShowBtn;
	SEL action = enabledRow ? @selector(enabledToggled:) : @selector(showButtonToggled:);

	UITableViewCell *cell = [self cellForTableView:tableView reuseID:enabledRow ? @"enabled" : @"showButton"];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = title;
	config.secondaryText = subtitle;
	config.textProperties.font = [UIFont systemFontOfSize:16.0];
	config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
	config.textToSecondaryTextVerticalPadding = 4.5;

	cell.contentConfiguration = config;
	cell.accessoryView = [self switchWithOn:[SCIUtils getBoolPref:key] action:action];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}

- (UITableViewCell *)currentLocationCellForTableView:(UITableView *)tableView {
	UITableViewCell *cell = [self cellForTableView:tableView reuseID:@"current"];

	NSString *name = self.currentName;
	double lat = self.currentLat;
	double lon = self.currentLon;

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = name.length ? name : SCILocalized(@"(unset)");
	config.secondaryText = [self coordTextWithLat:lat lon:lon];
	config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
	config.secondaryTextProperties.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
	config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
	config.textToSecondaryTextVerticalPadding = 4.5;
	config.image = [UIImage systemImageNamed:@"location.fill"];
	config.imageProperties.tintColor = UIColor.systemGreenColor;

	cell.contentConfiguration = config;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}

- (UITableViewCell *)selectLocationCellForTableView:(UITableView *)tableView {
	UITableViewCell *cell = [self cellForTableView:tableView reuseID:@"select"];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = SCILocalized(@"Select location on map");
	config.textProperties.color = UIColor.systemBlueColor;
	config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
	config.image = [UIImage systemImageNamed:@"map"];
	config.imageProperties.tintColor = UIColor.systemBlueColor;

	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}

- (UITableViewCell *)presetCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	NSArray<NSDictionary *> *items = self.presets;

	if (indexPath.row >= (NSInteger)items.count) {
		return [self addPresetCellForTableView:tableView];
	}

	NSDictionary *preset = items[indexPath.row];
	NSString *name = [preset[@"name"] isKindOfClass:NSString.class] ? preset[@"name"] : SCILocalized(@"Preset");
	double lat = [preset[@"lat"] doubleValue];
	double lon = [preset[@"lon"] doubleValue];

	UITableViewCell *cell = [self cellForTableView:tableView reuseID:@"preset"];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = name.length ? name : SCILocalized(@"Preset");
	config.secondaryText = [self coordTextWithLat:lat lon:lon];
	config.secondaryTextProperties.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
	config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
	config.textToSecondaryTextVerticalPadding = 4.5;
	config.image = [UIImage systemImageNamed:@"mappin.circle.fill"];
	config.imageProperties.tintColor = UIColor.systemRedColor;

	cell.contentConfiguration = config;

	return cell;
}

- (UITableViewCell *)addPresetCellForTableView:(UITableView *)tableView {
	UITableViewCell *cell = [self cellForTableView:tableView reuseID:@"addPreset"];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = SCILocalized(@"Add preset");
	config.textProperties.color = UIColor.systemBlueColor;
	config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
	config.image = [UIImage systemImageNamed:@"plus.circle.fill"];
	config.imageProperties.tintColor = UIColor.systemBlueColor;

	cell.contentConfiguration = config;

	return cell;
}

#pragma mark - Editing

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == SCIFakeLocationSectionPresets && indexPath.row < (NSInteger)self.presets.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style != UITableViewCellEditingStyleDelete) return;

	NSMutableArray *items = self.presets.mutableCopy ?: NSMutableArray.array;
	if (indexPath.row >= (NSInteger)items.count) return;

	[items removeObjectAtIndex:indexPath.row];
	[self setPresets:items];

	[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == SCIFakeLocationSectionCurrent && indexPath.row == 1) {
		[self openCurrentPicker];
		return;
	}

	if (indexPath.section != SCIFakeLocationSectionPresets) return;

	NSArray<NSDictionary *> *items = self.presets;

	if (indexPath.row < (NSInteger)items.count) {
		NSDictionary *preset = items[indexPath.row];
		[self applyLat:[preset[@"lat"] doubleValue] lon:[preset[@"lon"] doubleValue] name:preset[@"name"] enable:YES];
		return;
	}

	[self openPresetPicker];
}

#pragma mark - Actions

- (void)enabledToggled:(UISwitch *)sender {
	[self.defaults setBool:sender.on forKey:kEnabled];
	[self postMapButtonRefresh];
}

- (void)showButtonToggled:(UISwitch *)sender {
	[self.defaults setBool:sender.on forKey:kShowBtn];
	[self postMapButtonRefresh];
}

- (void)openCurrentPicker {
	__weak typeof(self) weakSelf = self;

	[self presentPickerWithTitle:SCILocalized(@"Set current location") completion:^(double lat, double lon, NSString *name) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		[self applyLat:lat lon:lon name:name enable:YES];
	}];
}

- (void)openPresetPicker {
	__weak typeof(self) weakSelf = self;

	[self presentPickerWithTitle:SCILocalized(@"Add preset") completion:^(double lat, double lon, NSString *name) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		[self askNameAndSavePresetWithLat:lat lon:lon name:name];
	}];
}

@end