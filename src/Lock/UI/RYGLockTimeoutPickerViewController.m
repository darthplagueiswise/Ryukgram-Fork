#import "RYGLockTimeoutPickerViewController.h"

#import "../RYGLockGroups.h"

#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"

@interface RYGLockTimeoutPickerViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, copy) NSArray<NSNumber *> *options;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation RYGLockTimeoutPickerViewController

- (instancetype)initWithGroupID:(NSString *)groupID {
	if ((self = [super init])) {
		_groupID = [groupID copy];
		_options = @[
			@0,
			@30,
			@60,
			@300,
			@900,
			@1800,
			@3600
		];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = RYGLocalized(@"Auto-relock after idle");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.navigationController.navigationBar.prefersLargeTitles = NO;

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
	self.tableView.estimatedRowHeight = 52.0;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;

	[self.view addSubview:self.tableView];
}

#pragma mark - Helpers

- (UIColor *)primaryColor {
	return [RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor;
}

- (double)currentTimeout {
	return [RYGUtils getDoublePref:RYGLockPrefIdleTimeout(self.groupID)];
}

- (NSString *)labelForSeconds:(double)seconds {
	if (seconds <= 0.0) {
		return RYGLocalized(@"Never");
	}

	if (seconds < 60.0) {
		return [NSString stringWithFormat:RYGLocalized(@"%lds"), (long)seconds];
	}

	if (seconds < 3600.0) {
		return [NSString stringWithFormat:RYGLocalized(@"%ld min"), (long)(seconds / 60.0)];
	}

	return [NSString stringWithFormat:RYGLocalized(@"%ld h"), (long)(seconds / 3600.0)];
}

- (NSString *)subtitleForSeconds:(double)seconds {
	if (seconds <= 0.0) {
		return RYGLocalized(@"Stay unlocked until app close or background");
	}

	if (seconds == 30.0) {
		return RYGLocalized(@"Best for sensitive sections");
	}

	if (seconds == 60.0) {
		return RYGLocalized(@"Short idle window");
	}

	if (seconds == 300.0) {
		return RYGLocalized(@"Balanced default");
	}

	if (seconds == 900.0 || seconds == 1800.0) {
		return RYGLocalized(@"Less frequent prompts");
	}

	return RYGLocalized(@"Longest idle window");
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
	return self.options.count;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section {
	return RYGLocalized(@"Choose how long this section stays unlocked while idle. Never keeps it unlocked until Instagram closes or goes to background.");
}

- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)self.options.count) {
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}

	double seconds = self.options[indexPath.row].doubleValue;
	double current = [self currentTimeout];
	BOOL selected = (NSInteger)current == (NSInteger)seconds;

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = [self labelForSeconds:seconds];
	config.textProperties.color = UIColor.labelColor;

	NSString *subtitle = [self subtitleForSeconds:seconds];
	if (subtitle.length) {
		config.secondaryText = subtitle;
		config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
		config.textToSecondaryTextVerticalPadding = 4.5;
	}

	cell.contentConfiguration = config;
	cell.tintColor = [self primaryColor];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.row >= (NSInteger)self.options.count) return;

	double seconds = self.options[indexPath.row].doubleValue;

	[[NSUserDefaults standardUserDefaults] setObject:@(seconds) forKey:RYGLockPrefIdleTimeout(self.groupID)];

	[[NSNotificationCenter defaultCenter] postNotificationName:RYGLockPrefsDidChangeNotification
														object:self.groupID];

	[self.tableView reloadData];
	[self.navigationController popViewControllerAnimated:YES];
}

@end
