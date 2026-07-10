#import "SCIDateFormatPickerVC.h"
#import "../Utils.h"
#import "../UI/SCIOptionSheet.h"
#import "../Features/General/SCIDateFormatEntries.h"
#import "../Features/General/SCIDateFormatTemplate.h"

static NSString *const kFmtKey = @"feed_date_format";
static NSString *const kSecKey = @"feed_date_show_seconds";
static NSString *const kCompactKey = @"feed_date_compact_relative";
static NSString *const kThresholdKey = @"feed_date_relative_days_threshold";
static NSString *const kCombineKey = @"feed_date_combine_with_date";

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
			@[@"day_slash_24", @"dd/MM/yyyy HH:mm", @"dd/MM/yyyy HH:mm:ss"],
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

static NSString *sciExampleForTemplate(NSString *tpl) {
	NSString *pattern = SCIDateFormatPatternFromTemplate(tpl);
	if (!pattern.length) return nil;

	NSDateFormatter *df = NSDateFormatter.new;
	df.locale = NSLocale.currentLocale;
	df.dateFormat = pattern;

	return [df stringFromDate:sciRefDate()];
}

static NSString *sciExampleForKey(NSString *key) {
	if (!key.length || [key isEqualToString:@"default"]) return SCILocalized(@"Default");

	if ([key hasPrefix:@"custom:"]) {
		NSString *ex = sciExampleForTemplate(SCIDateFormatCustomTemplateForKey(key));
		return ex.length ? ex : SCILocalized(@"Custom");
	}

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

static NSString *sciCombineDisplayName(NSString *mode) {
	if ([mode isEqualToString:@"absolute_first"]) return SCILocalized(@"Absolute then relative");
	if ([mode isEqualToString:@"relative_first"]) return SCILocalized(@"Relative – absolute");
	return SCILocalized(@"Off");
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

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[_tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return (NSInteger)(sciDateFormatOptions().count + SCIDateFormatCustomList().count) + 1;
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
	if (section == 0) return SCILocalized(@"Pick how absolute dates are written. “Default” leaves IG's own format untouched. Swipe a custom format to edit or delete it.");
	if (section == 1) return SCILocalized(@"Include seconds when the format already shows time. The custom format controls seconds itself with {ss}.");
	if (section == 2) return SCILocalized(@"Dates younger than the threshold show as relative time. Older dates fall back to the absolute format. “Combine with date” shows both — “Jan 5, 2026 (2h)” or “2h – Jan 5, 2026”.");
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
	NSString *current = [SCIUtils getStringPref:kFmtKey];
	if (!current.length) current = @"default";

	NSInteger presets = (NSInteger)sciDateFormatOptions().count;
	NSArray<NSDictionary *> *customs = SCIDateFormatCustomList();

	if (indexPath.row >= presets + (NSInteger)customs.count) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"formatAdd"];
		if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"formatAdd"];

		cell.textLabel.text = SCILocalized(@"Add custom format…");
		cell.textLabel.font = [UIFont systemFontOfSize:16.0];
		cell.textLabel.textColor = [SCIUtils SCIColor_Primary];
		cell.accessoryView = nil;
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;

		return cell;
	}

	if (indexPath.row >= presets) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"formatCustom"];
		if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"formatCustom"];

		NSDictionary *entry = customs[indexPath.row - presets];
		NSString *ex = sciExampleForTemplate(entry[@"tpl"]);
		NSString *key = [@"custom:" stringByAppendingString:entry[@"id"]];

		cell.textLabel.text = ex.length ? ex : SCILocalized(@"Custom");
		cell.textLabel.font = [UIFont systemFontOfSize:16.0];
		cell.detailTextLabel.text = SCILocalized(@"Custom");
		cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
		cell.accessoryView = nil;
		cell.accessoryType = [current isEqualToString:key] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;

		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"format"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"format"];

	NSString *key = sciDateFormatOptions()[indexPath.row][0];

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

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"combine"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"combine"];

	cell.textLabel.text = SCILocalized(@"Combine with date");
	cell.textLabel.numberOfLines = 0;
	cell.detailTextLabel.text = sciCombineDisplayName([SCIUtils getStringPref:kCombineKey]);
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	return cell;
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

	NSInteger index = [sciSurfaceEntries() indexOfObjectPassingTest:^BOOL(NSArray<NSString *> *entry, NSUInteger idx, BOOL *stop) {
		return [entry[0] isEqualToString:key];
	}];

	return index == NSNotFound ? -1 : index;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section != 0) return nil;

	NSInteger idx = indexPath.row - (NSInteger)sciDateFormatOptions().count;
	NSArray<NSDictionary *> *customs = SCIDateFormatCustomList();
	if (idx < 0 || idx >= (NSInteger)customs.count) return nil;

	NSString *uid = customs[idx][@"id"];
	__weak typeof(self) weakSelf = self;

	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																	  title:SCILocalized(@"Delete")
																	handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completion)(BOOL)) {
		NSMutableArray *list = SCIDateFormatCustomList().mutableCopy;
		[list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, __unused NSDictionary *bindings) {
			return ![entry[@"id"] isEqualToString:uid];
		}]];
		SCIDateFormatCustomSaveList(list);

		NSString *key = [@"custom:" stringByAppendingString:uid];
		if ([[SCIUtils getStringPref:kFmtKey] isEqualToString:key]) {
			[NSUserDefaults.standardUserDefaults setObject:@"default" forKey:kFmtKey];
		}

		[tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
		completion(YES);
	}];

	UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																	   title:SCILocalized(@"Edit")
																	 handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completion)(BOOL)) {
		[weakSelf.navigationController pushViewController:[[SCIDateFormatCustomVC alloc] initWithEntryID:uid] animated:YES];
		completion(YES);
	}];
	edit.backgroundColor = UIColor.systemBlueColor;

	UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[del, edit]];
	config.performsFirstActionWithFullSwipe = NO;
	return config;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0) {
		NSInteger presets = (NSInteger)sciDateFormatOptions().count;
		NSArray<NSDictionary *> *customs = SCIDateFormatCustomList();

		if (indexPath.row >= presets + (NSInteger)customs.count) {
			NSString *uid = NSUUID.UUID.UUIDString;
			NSMutableArray *list = customs.mutableCopy;
			[list addObject:@{@"id": uid, @"tpl": @"{DD}/{MM}/{YYYY} {HH}:{mm}:{ss}"}];
			SCIDateFormatCustomSaveList(list);

			[NSUserDefaults.standardUserDefaults setObject:[@"custom:" stringByAppendingString:uid] forKey:kFmtKey];
			[self.navigationController pushViewController:[[SCIDateFormatCustomVC alloc] initWithEntryID:uid] animated:YES];
			return;
		}

		if (indexPath.row >= presets) {
			NSString *uid = customs[indexPath.row - presets][@"id"];
			[NSUserDefaults.standardUserDefaults setObject:[@"custom:" stringByAppendingString:uid] forKey:kFmtKey];
		} else {
			[NSUserDefaults.standardUserDefaults setObject:sciDateFormatOptions()[indexPath.row][0] forKey:kFmtKey];
		}

		[tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
		return;
	}

	if (indexPath.section == 2 && indexPath.row == 0) {
		[self showThresholdEditorFromTableView:tableView indexPath:indexPath];
		return;
	}

	if (indexPath.section == 2 && indexPath.row == 2) {
		[self showCombinePickerFromTableView:tableView indexPath:indexPath];
	}
}

- (void)showCombinePickerFromTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	NSArray<NSDictionary<NSString *, NSString *> *> *options = @[
		@{@"title": SCILocalized(@"Off"),
		  @"value": @"off",
		  @"description": SCILocalized(@"Relative when young, absolute when older.")},
		@{@"title": SCILocalized(@"Absolute then relative"),
		  @"value": @"absolute_first",
		  @"description": SCILocalized(@"Example: “Jan 5, 2026 (2h)”")},
		@{@"title": SCILocalized(@"Relative – absolute"),
		  @"value": @"relative_first",
		  @"description": SCILocalized(@"Example: “2h – Jan 5, 2026”")},
	];

	[SCIOptionSheet presentFrom:self
						  title:SCILocalized(@"Combine with date")
					defaultsKey:kCombineKey
						options:options
					   onChange:^(__unused NSString *value) {
		[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
	}];
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

- (void)surfaceToggled:(UISwitch *)sender {
	if (sender.tag < 0 || sender.tag >= (NSInteger)sciSurfaceEntries().count) return;

	NSArray *entry = sciSurfaceEntries()[sender.tag];
	[NSUserDefaults.standardUserDefaults setBool:sender.on forKey:entry[0]];
}

@end

#pragma mark - Custom template editor

@implementation SCIDateFormatCustomVC {
	UITableView *_tableView;
	UITextField *_field;
	UITableViewCell *_fieldCell;
	UITableViewCell *_previewCell;
	NSArray<NSArray<NSString *> *> *_tokenRows; // @[token, example]
	NSString *_entryID;
}

- (instancetype)initWithEntryID:(NSString *)entryID {
	if ((self = [super initWithNibName:nil bundle:nil])) {
		_entryID = entryID.copy;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Custom");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	NSString *tpl = nil;
	for (NSDictionary *entry in SCIDateFormatCustomList()) {
		if ([entry[@"id"] isEqualToString:_entryID]) {
			tpl = entry[@"tpl"];
			break;
		}
	}
	if (!tpl) tpl = @"{DD}/{MM}/{YYYY} {HH}:{mm}:{ss}";

	NSDateFormatter *df = NSDateFormatter.new;
	df.locale = NSLocale.currentLocale;

	NSMutableArray *rows = NSMutableArray.array;
	for (NSArray *token in SCIDateFormatTemplateTokens()) {
		df.dateFormat = token[1];
		[rows addObject:@[token[0], [df stringFromDate:sciRefDate()]]];
	}
	_tokenRows = rows.copy;

	_field = UITextField.new;
	_field.text = tpl;
	_field.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
	_field.autocorrectionType = UITextAutocorrectionTypeNo;
	_field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_field.smartQuotesType = UITextSmartQuotesTypeNo;
	_field.smartDashesType = UITextSmartDashesTypeNo;
	_field.spellCheckingType = UITextSpellCheckingTypeNo;
	_field.clearButtonMode = UITextFieldViewModeWhileEditing;
	_field.placeholder = @"{DD}/{MM}/{YYYY} {HH}:{mm}";
	_field.delegate = self;
	[_field addTarget:self action:@selector(templateChanged) forControlEvents:UIControlEventEditingChanged];

	_fieldCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	_fieldCell.selectionStyle = UITableViewCellSelectionStyleNone;
	_field.translatesAutoresizingMaskIntoConstraints = NO;
	[_fieldCell.contentView addSubview:_field];
	[NSLayoutConstraint activateConstraints:@[
		[_field.leadingAnchor constraintEqualToAnchor:_fieldCell.contentView.layoutMarginsGuide.leadingAnchor],
		[_field.trailingAnchor constraintEqualToAnchor:_fieldCell.contentView.layoutMarginsGuide.trailingAnchor],
		[_field.topAnchor constraintEqualToAnchor:_fieldCell.contentView.topAnchor constant:12.0],
		[_field.bottomAnchor constraintEqualToAnchor:_fieldCell.contentView.bottomAnchor constant:-12.0],
	]];

	_previewCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	_previewCell.selectionStyle = UITableViewCellSelectionStyleNone;
	_previewCell.textLabel.text = SCILocalized(@"Preview");
	_previewCell.textLabel.font = [UIFont systemFontOfSize:16.0];
	_previewCell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

	[self updatePreview];

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.backgroundColor = self.view.backgroundColor;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	[self.view addSubview:_tableView];
}

- (void)templateChanged {
	NSMutableArray *list = SCIDateFormatCustomList().mutableCopy;
	NSDictionary *updated = @{@"id": _entryID, @"tpl": (_field.text ?: @"")};

	NSUInteger idx = [list indexOfObjectPassingTest:^BOOL(NSDictionary *entry, __unused NSUInteger i, __unused BOOL *stop) {
		return [entry[@"id"] isEqualToString:self->_entryID];
	}];

	if (idx == NSNotFound) [list addObject:updated];
	else list[idx] = updated;

	SCIDateFormatCustomSaveList(list);
	[self updatePreview];
}

- (void)updatePreview {
	NSString *ex = sciExampleForTemplate(_field.text);
	_previewCell.detailTextLabel.text = ex.length ? ex : @"—";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 2 : (NSInteger)_tokenRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? SCILocalized(@"Template") : SCILocalized(@"Placeholders");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"Placeholders are replaced with date parts; anything else is shown as-is.");
	return SCILocalized(@"Tap a placeholder to insert it at the cursor.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) return indexPath.row == 0 ? _fieldCell : _previewCell;

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"token"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"token"];

	NSArray *row = _tokenRows[indexPath.row];
	cell.textLabel.text = row[0];
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
	cell.detailTextLabel.text = row[1];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1) return;

	NSString *token = _tokenRows[indexPath.row][0];
	UITextRange *sel = _field.isFirstResponder ? _field.selectedTextRange : nil;

	if (sel) {
		[_field replaceRange:sel withText:token];
	} else {
		_field.text = [(_field.text ?: @"") stringByAppendingString:token];
	}

	[self templateChanged];
}

@end