#import "RYGGridToggleSettingsViewController.h"
#import "RYGGridTogglePositionViewController.h"
#import "RYGGridFeedInfo.h"
#import "../../../UI/RYGPopupChrome.h"
#import "../../../UI/RYGIcon.h"
#import "../../../Utils.h"

typedef NS_ENUM(NSInteger, RYGGridToggleSection) {
	RYGGridToggleSectionMaster = 0,
	RYGGridToggleSectionMode,
	RYGGridToggleSectionPosition,
};

static UIImage *rygRowIcon(NSString *name) {
	return [RYGIcon imageNamed:name pointSize:22] ?: [UIImage systemImageNamed:name];
}

@implementation RYGGridToggleSettingsViewController

- (instancetype)init {
	if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
	self.title = RYGLocalized(@"Switch button");
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

- (BOOL)switchOn { return [RYGGridFeedInfo togglePlacement] != RYGGridTogglePlacementOff; }
- (BOOL)usesButton { return [RYGGridFeedInfo togglePlacement] == RYGGridTogglePlacementButton; }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (s == RYGGridToggleSectionMode) return 2;
	return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if (s == RYGGridToggleSectionMode) return RYGLocalized(@"How to switch");
	return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == RYGGridToggleSectionMaster)
		return RYGLocalized(@"Switches between the grid and Instagram's feed without turning the grid off. Off leaves the home bar shortcut as the only way.");
	if (s == RYGGridToggleSectionPosition && [self usesButton])
		return RYGLocalized(@"The button never sits under the header or the tab bar. Hold it on the feed to come back here.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == RYGGridToggleSectionMaster) return [self masterCell];
	if (ip.section == RYGGridToggleSectionMode) return [self modeCellForRow:ip.row];
	return [self positionCell];
}

- (UITableViewCell *)masterCell {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = RYGLocalized(@"Switch button");
	cfg.image = rygRowIcon(@"ig_icon_hand_point_outline_24");
	cfg.imageProperties.tintColor = UIColor.labelColor;
	cell.contentConfiguration = cfg;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UISwitch *sw = UISwitch.new;
	sw.on = [self switchOn];
	sw.onTintColor = [RYGUtils RYGColor_Primary];
	[sw addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = sw;
	return cell;
}

- (UITableViewCell *)modeCellForRow:(NSInteger)row {
	BOOL heart = (row == 0);
	RYGGridTogglePlacement mode = heart ? RYGGridTogglePlacementHeartLongPress : RYGGridTogglePlacementButton;
	BOOL enabled = [self switchOn];

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = [RYGGridFeedInfo nameForTogglePlacement:mode];
	cfg.secondaryText = heart ? RYGLocalized(@"Hold the heart in Instagram's header")
	                          : RYGLocalized(@"A small round button on the feed");
	cfg.image = rygRowIcon(heart ? @"ig_icon_heart_outline_24" : @"ig_icon_circle_outline_24");
	cfg.imageProperties.tintColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	cfg.textProperties.color = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	cfg.secondaryTextProperties.color = enabled ? UIColor.secondaryLabelColor : UIColor.quaternaryLabelColor;
	cell.contentConfiguration = cfg;

	BOOL picked = enabled && ([RYGGridFeedInfo togglePlacement] == mode);
	cell.accessoryType = picked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.tintColor = [RYGUtils RYGColor_Primary];
	cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)positionCell {
	BOOL enabled = [self usesButton];
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = RYGLocalized(@"Button position");
	cfg.image = rygRowIcon(@"reposition");
	cfg.imageProperties.tintColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	cfg.textProperties.color = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
	cell.contentConfiguration = cfg;
	cell.accessoryType = enabled ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == RYGGridToggleSectionMode) {
		if (![self switchOn]) return;
		[RYGGridFeedInfo setTogglePlacement:(ip.row == 0 ? RYGGridTogglePlacementHeartLongPress : RYGGridTogglePlacementButton)];
		[tv reloadData];
		return;
	}
	if (ip.section == RYGGridToggleSectionPosition && [self usesButton])
		[self.navigationController pushViewController:[RYGGridTogglePositionViewController new] animated:YES];
}

// Off is its own placement, so remember the mode to come back to.
- (void)masterChanged:(UISwitch *)sw {
	if (!sw.isOn) {
		[RYGUtils setPref:@([RYGGridFeedInfo togglePlacement]) forKey:@"grid_feed_toggle_last_mode"];
		[RYGGridFeedInfo setTogglePlacement:RYGGridTogglePlacementOff];
	} else {
		NSInteger last = (NSInteger)[RYGUtils getDoublePref:@"grid_feed_toggle_last_mode"];
		if (last != RYGGridTogglePlacementHeartLongPress && last != RYGGridTogglePlacementButton)
			last = RYGGridTogglePlacementHeartLongPress;
		[RYGGridFeedInfo setTogglePlacement:(RYGGridTogglePlacement)last];
	}
	[self.tableView reloadData];
}

@end
