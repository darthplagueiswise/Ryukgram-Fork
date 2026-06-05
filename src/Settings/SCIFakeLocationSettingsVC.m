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

@implementation SCIFakeLocationSettingsVC

- (instancetype)init {
	if ((self = [super initWithTitle:SCILocalized(@"Fake location")])) {
		[self rebuildSections];
	}
	return self;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuildSections];
}

#pragma mark - Data

- (NSUserDefaults *)defaults {
	return NSUserDefaults.standardUserDefaults;
}

- (NSArray<NSDictionary *> *)presets {
	id raw = [self.defaults objectForKey:kPresets];
	return [raw isKindOfClass:NSArray.class] ? raw : @[];
}

- (void)setPresets:(NSArray<NSDictionary *> *)presets {
	[self.defaults setObject:presets ?: @[] forKey:kPresets];
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

#pragma mark - Sections

- (void)rebuildSections {
	__weak typeof(self) weak = self;

	SCIBaseSettingsRow *enabled = [SCIBaseSettingsRow switchRowWithTitle:SCILocalized(@"Enable fake location")
																 subtitle:SCILocalized(@"Override Instagram location reads.")
																	value:^BOOL{
		return [SCIUtils getBoolPref:kEnabled];
	} action:^(BOOL on, UIViewController *vc) {
		SCIFakeLocationSettingsVC *self = (id)vc;
		[self.defaults setBool:on forKey:kEnabled];
		[self postMapButtonRefresh];
	}];

	SCIBaseSettingsRow *showButton = [SCIBaseSettingsRow switchRowWithTitle:SCILocalized(@"Show map button")
																   subtitle:SCILocalized(@"Show the quick button in Friends Map.")
																	  value:^BOOL{
		return [SCIUtils getBoolPref:kShowBtn];
	} action:^(BOOL on, UIViewController *vc) {
		SCIFakeLocationSettingsVC *self = (id)vc;
		[self.defaults setBool:on forKey:kShowBtn];
		[self postMapButtonRefresh];
	}];

	SCIBaseSettingsRow *current = [SCIBaseSettingsRow rowWithTitle:@""
														  subtitle:nil
															action:nil];
	current.dynamicTitle = ^{ return weak.currentName.length ? weak.currentName : SCILocalized(@"(unset)"); };
	current.dynamicSubtitle = ^{ return [weak coordTextWithLat:weak.currentLat lon:weak.currentLon]; };
	current.icon = [UIImage systemImageNamed:@"location.fill"];

	SCIBaseSettingsRow *select = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Select location on map")
														 subtitle:nil
														   action:^(UIViewController *vc) {
		[(SCIFakeLocationSettingsVC *)vc openCurrentPicker];
	}];
	select.titleColor = UIColor.systemBlueColor;

	NSMutableArray *presetRows = [NSMutableArray new];
	for (NSDictionary *preset in self.presets) {
		NSString *name = [preset[@"name"] isKindOfClass:NSString.class] ? preset[@"name"] : SCILocalized(@"Preset");
		double lat = [preset[@"lat"] doubleValue];
		double lon = [preset[@"lon"] doubleValue];

		SCIBaseSettingsRow *row = [SCIBaseSettingsRow rowWithTitle:name.length ? name : SCILocalized(@"Preset")
														  subtitle:[self coordTextWithLat:lat lon:lon]
															action:^(UIViewController *vc) {
			SCIFakeLocationSettingsVC *self = (id)vc;
			[self applyLat:lat lon:lon name:name enable:YES];
		}];
		row.accessoryType = UITableViewCellAccessoryNone;
		row.icon = [UIImage systemImageNamed:@"mappin.circle.fill"];
		[presetRows addObject:row];
	}

	SCIBaseSettingsRow *addPreset = [SCIBaseSettingsRow rowWithTitle:SCILocalized(@"Add preset")
															subtitle:nil
															  action:^(UIViewController *vc) {
		[(SCIFakeLocationSettingsVC *)vc openPresetPicker];
	}];
	addPreset.titleColor = UIColor.systemBlueColor;
	addPreset.accessoryType = UITableViewCellAccessoryNone;
	addPreset.icon = [UIImage systemImageNamed:@"plus.circle.fill"];
	[presetRows addObject:addPreset];

	self.sections = @[
		[SCIBaseSettingsSection sectionWithHeader:nil footer:SCILocalized(@"When on, Instagram location requests return your selected fake location. The map button adds a quick shortcut inside Friends Map.") rows:@[enabled, showButton]],
		[SCIBaseSettingsSection sectionWithHeader:SCILocalized(@"Current location") footer:nil rows:@[current, select]],
		[SCIBaseSettingsSection sectionWithHeader:SCILocalized(@"Saved locations") footer:SCILocalized(@"Tap a preset to make it active. Swipe left to delete.") rows:presetRows],
	];

	[self reloadSettings];
}

#pragma mark - Actions

- (void)postMapButtonRefresh {
	[NSNotificationCenter.defaultCenter postNotificationName:kMapBtnChanged object:nil];
}

- (void)applyLat:(double)lat lon:(double)lon name:(NSString *)name enable:(BOOL)enable {
	[self.defaults setObject:@(lat) forKey:kLat];
	[self.defaults setObject:@(lon) forKey:kLon];
	[self.defaults setObject:name ?: @"" forKey:kName];

	if (enable) [self.defaults setBool:YES forKey:kEnabled];

	[self postMapButtonRefresh];
	[self rebuildSections];
}

- (void)presentPickerWithTitle:(NSString *)title completion:(void (^)(double lat, double lon, NSString *name))completion {
	SCIFakeLocationPickerVC *vc = [SCIFakeLocationPickerVC new];
	vc.initialCoord = self.currentCoord;
	vc.titleText = title;
	vc.onPick = completion;

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	[self presentViewController:nav animated:YES completion:nil];
}

- (void)openCurrentPicker {
	__weak typeof(self) weak = self;

	[self presentPickerWithTitle:SCILocalized(@"Set current location") completion:^(double lat, double lon, NSString *name) {
		[weak applyLat:lat lon:lon name:name enable:YES];
	}];
}

- (void)openPresetPicker {
	__weak typeof(self) weak = self;

	[self presentPickerWithTitle:SCILocalized(@"Add preset") completion:^(double lat, double lon, NSString *name) {
		[weak askNameAndSavePresetWithLat:lat lon:lon name:name];
	}];
}

- (void)askNameAndSavePresetWithLat:(double)lat lon:(double)lon name:(NSString *)name {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Save preset")
																   message:nil
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = SCILocalized(@"Name");
		field.text = name;
		field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weak = self;
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		__strong typeof(weak) self = weak;
		if (!self) return;

		NSString *finalName = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : name;
		NSDictionary *preset = @{@"name": finalName ?: @"", @"lat": @(lat), @"lon": @(lon)};

		NSMutableArray *items = self.presets.mutableCopy ?: NSMutableArray.array;
		[items addObject:preset];

		[self setPresets:items];
		[self rebuildSections];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == 2 && indexPath.row < (NSInteger)self.presets.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style != UITableViewCellEditingStyleDelete) return;

	NSMutableArray *items = self.presets.mutableCopy ?: NSMutableArray.array;
	if (indexPath.row >= (NSInteger)items.count) return;

	[items removeObjectAtIndex:indexPath.row];
	[self setPresets:items];
	[self rebuildSections];
}

@end