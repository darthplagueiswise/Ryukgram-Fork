#import "SCIDateFormatPickerVC.h"
#import "../Utils.h"
#import "../Features/General/SCIDateFormatEntries.h"

static NSString *const kFmtKey = @"feed_date_format";
static NSString *const kSecKey = @"feed_date_show_seconds";
static NSString *const kCompactKey = @"feed_date_compact_relative";
static NSString *const kThresholdKey = @"feed_date_relative_days_threshold";
static NSString *const kAppendKey = @"feed_date_append_relative";

static NSArray<NSArray *> *sciDateFormatOptions(void) {
	static NSArray *opts = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		opts = @[
			@[@"default", @"", @""],
			@[@"short", @"MMM d", @"MMM d"],
			@[@"medium", @"MMM d, yyyy", @"MMM d, yyyy"],
			@[@"full", @"MMM d, yyyy 'at' h:mm a", @"MMM d, yyyy 'at' h:mm:ss a"],
			@[@"time_12", @"MMM d 'at' h:mm a", @"MMM d 'at' h:mm:ss a"],
			@[@"time_24", @"MMM d 'at' HH:mm", @"MMM d 'at' HH:mm:ss"],
			@[@"dd_mmm", @"dd-MMM-yyyy 'at' h:mm a", @"dd-MMM-yyyy 'at' h:mm:ss a"],
			@[@"day_slash", @"dd/MM/yyyy h:mm a", @"dd/MM/yyyy h:mm:ss a"],
			@[@"month_slash", @"MM/dd/yyyy h:mm a", @"MM/dd/yyyy h:mm:ss a"],
			@[@"euro", @"dd.MM.yyyy HH:mm", @"dd.MM.yyyy HH:mm:ss"],
			@[@"iso", @"yyyy-MM-dd", @"yyyy-MM-dd"],
			@[@"iso_time", @"yyyy-MM-dd HH:mm", @"yyyy-MM-dd HH:mm:ss"],
		];
	});
	return opts;
}

static NSArray<NSArray<NSString *> *> *sciSurfaceEntries(void) {
	static NSArray *entries = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableArray *m = NSMutableArray.array;
		NSMutableSet *seen = NSMutableSet.set;

		#define SCI_EMIT(NAME, SEL_, LABEL, ARITY, PREF) \
			if (strlen(LABEL) && ![seen containsObject:@PREF]) { \
				[seen addObject:@PREF]; \
				[m addObject:@[@PREF, @LABEL]]; \
			}

		SCI_DATE_FORMAT_ENTRIES(SCI_EMIT)

		#undef SCI_EMIT

		entries = m.copy;
	});
	return entries;
}

static NSDate *sciRefDate(void) {
	static NSDate *ref = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		ref = [NSDate dateWithTimeIntervalSince1970:1736348730];
	});
	return ref;
}

static NSString *sciExampleForKey(NSString *key) {
	if (!key.length || [key isEqualToString:@"default"]) return SCILocalized(@"Default");

	BOOL sec = [SCIUtils getBoolPref:kSecKey];

	for (NSArray *opt in sciDateFormatOptions()) {
		if (![opt[0] isEqualToString:key]) continue;

		NSString *pattern = sec ? opt[2] : opt[1];
		if (!pattern.length) return SCILocalized(@"Default");

		NSDateFormatter *df = NSDateFormatter.new;
		df.locale = NSLocale.currentLocale;
		df.dateFormat = pattern;

		return [df stringFromDate:sciRefDate()];
	}

	return SCILocalized(@"Default");
}

static NSString *sciThresholdText(void) {
	NSInteger days = (NSInteger)[SCIUtils getDoublePref:kThresholdKey];

	if (days <= 0) return SCILocalized(@"Off");
	if (days == 1) return SCILocalized(@"Within 1 day");

	return [NSString stringWithFormat:SCILocalized(@"Within %ld days"), (long)days];
}

@implementation SCIDateFormatPickerVC {
	UITableView *_tableView;
}

+ (NSString *)currentFormatExample {
	return sciExampleForKey([SCIUtils getStringPref:kFmtKey]);
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Date format");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.backgroundColor = self.view.backgroundColor;
	_tableView.dataSource = self;
	_tableView.delegate = self;

	[self.view addSubview:_tableView];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return (NSInteger)sciDateFormatOptions().count;
	if (section == 1) return 1;
	if (section == 2) return 3;
	return (NSInteger)sciSurfaceEntries().count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"Absolute format");
	if (section == 1) return SCILocalized(@"Time");
	if (section == 2) return SCILocalized(@"Relative time");
	return SCILocalized(@"Apply to");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"Pick how absolute dates are written. “Default” leaves IG's own format untouched.");
	if (section == 1) return SCILocalized(@"Include seconds when the format already shows time.");
	if (section == 2) return SCILocalized(@"Dates younger than the threshold show as relative time. Older dates fall back to the absolute format. Append mode shows both, like “Jan 5, 2026 (2h)”.");
	if (section == 3) return SCILocalized(@"Each surface in IG goes through a different NSDate formatter. Toggle the ones you want this format to apply to.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) return [self formatCellForTableView:tableView indexPath:indexPath];
	if (indexPath.section == 1) return [self switchCellForTableView:tableView title:SCILocalized(@"Show seconds") subtitle:nil key:kSecKey action:@selector(secondsToggled:) reuseID:@"seconds"];
	if (indexPath.section == 2) return [self relativeCellForTableView:tableView indexPath:indexPath];

	NSArray *entry = sciSurfaceEntries()[indexPath.row];

	return [self switchCellForTableView:tableView
								  title:SCILocalized(entry[1])
							   subtitle:nil
									key:entry[0]
								 action:@selector(surfaceToggled:)
								reuseID:@"surface"];
}

#pragma mark - Cells

- (UITableViewCell *)formatCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"format"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"format"];

	NSString *key = sciDateFormatOptions()[indexPath.row][0];
	NSString *current = [SCIUtils getStringPref:kFmtKey];
	if (!current.length) current = @"default";

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = sciExampleForKey(key);
	config.textProperties.font = [UIFont systemFontOfSize:16.0];

	cell.contentConfiguration = config;
	cell.accessoryView = nil;
	cell.accessoryType = [current isEqualToString:key] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	return cell;
}

- (UITableViewCell *)relativeCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	if (indexPath.row == 0) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"threshold"];
		if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"threshold"];

		cell.textLabel.text = SCILocalized(@"Relative within");
		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.text = sciThresholdText();
		cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;

		return cell;
	}

	if (indexPath.row == 1) {
		return [self switchCellForTableView:tableView
									  title:SCILocalized(@"Compact style")
								   subtitle:SCILocalized(@"Example: “1h” instead of “1 hour ago”")
										key:kCompactKey
									 action:@selector(compactToggled:)
									reuseID:@"compact"];
	}

	return [self switchCellForTableView:tableView
								  title:SCILocalized(@"Append after absolute date")
							   subtitle:SCILocalized(@"Example: “Jan 5, 2026 (2h)”")
									key:kAppendKey
								 action:@selector(appendToggled:)
								reuseID:@"append"];
}

- (UITableViewCell *)switchCellForTableView:(UITableView *)tableView title:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key action:(SEL)action reuseID:(NSString *)reuseID {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = title;
	config.textProperties.font = [UIFont systemFontOfSize:16.0];

	if (subtitle.length) {
		config.secondaryText = subtitle;
		config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
		config.textToSecondaryTextVerticalPadding = 4.5;
	}

	UISwitch *sw = UISwitch.new;
	sw.on = [SCIUtils getBoolPref:key];
	sw.onTintColor = [SCIUtils SCIColor_Primary];
	sw.tag = [self switchTagForKey:key];
	[sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];

	cell.contentConfiguration = config;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = sw;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	return cell;
}

- (NSInteger)switchTagForKey:(NSString *)key {
	if ([key isEqualToString:kSecKey]) return 0;
	if ([key isEqualToString:kCompactKey]) return 1;
	if ([key isEqualToString:kAppendKey]) return 2;

	NSInteger index = [sciSurfaceEntries() indexOfObjectPassingTest:^BOOL(NSArray<NSString *> *entry, NSUInteger idx, BOOL *stop) {
		return [entry[0] isEqualToString:key];
	}];

	return index == NSNotFound ? -1 : index;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0) {
		[NSUserDefaults.standardUserDefaults setObject:sciDateFormatOptions()[indexPath.row][0] forKey:kFmtKey];
		[tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
		return;
	}

	if (indexPath.section == 2 && indexPath.row == 0) {
		[self showThresholdEditorFromTableView:tableView indexPath:indexPath];
	}
}

- (void)showThresholdEditorFromTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Relative within")
																   message:SCILocalized(@"Show relative time for dates younger than this many days. 0 disables it.")
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		NSInteger days = (NSInteger)[SCIUtils getDoublePref:kThresholdKey];
		field.keyboardType = UIKeyboardTypeNumberPad;
		field.placeholder = @"0";
		field.text = [NSString stringWithFormat:@"%ld", (long)days];
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		NSInteger days = alert.textFields.firstObject.text.integerValue;
		if (days < 0) days = 0;
		if (days > 365) days = 365;

		[NSUserDefaults.standardUserDefaults setInteger:days forKey:kThresholdKey];
		[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)secondsToggled:(UISwitch *)sender {
	[NSUserDefaults.standardUserDefaults setBool:sender.on forKey:kSecKey];
	[_tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)compactToggled:(UISwitch *)sender {
	[NSUserDefaults.standardUserDefaults setBool:sender.on forKey:kCompactKey];
}

- (void)appendToggled:(UISwitch *)sender {
	[NSUserDefaults.standardUserDefaults setBool:sender.on forKey:kAppendKey];
}

- (void)surfaceToggled:(UISwitch *)sender {
	if (sender.tag < 0 || sender.tag >= (NSInteger)sciSurfaceEntries().count) return;

	NSArray *entry = sciSurfaceEntries()[sender.tag];
	[NSUserDefaults.standardUserDefaults setBool:sender.on forKey:entry[0]];
}

@end