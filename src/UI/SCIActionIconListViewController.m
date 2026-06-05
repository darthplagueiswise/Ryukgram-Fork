#import "SCIActionIconListViewController.h"
#import "SCIIconPicker.h"
#import "../ActionButton/SCIActionIcon.h"
#import "../Localization/SCILocalization.h"
#import "../Settings/GlassUI/SCIAdaptiveGlass.h"

@interface SCIActionIconListViewController ()
@property (nonatomic, strong) NSArray<NSNumber *> *sources;
@end

@implementation SCIActionIconListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
	SCIApplyGlassBackdropToViewController(self);
    self.title = SCILocalized(@"Action button icon");
    self.sources = [SCIActionIcon overridableSources];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (UIImage *)glyphForSymbol:(NSString *)name {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)self.sources.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? SCILocalized(@"Default") : SCILocalized(@"Per button");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return SCILocalized(@"Override the icon for a specific button. Buttons left on Default follow the shared icon above.");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kID = @"SCIActionIconRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kID];
		SCIStyleCellForGlass(cell);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.imageView.tintColor = [UIColor labelColor];

    if (indexPath.section == 0) {
        NSString *symbol = [SCIActionIcon symbolName];
        cell.textLabel.text = SCILocalized(@"All buttons");
        cell.detailTextLabel.text = symbol;
        cell.imageView.image = [self glyphForSymbol:symbol];
    } else {
        SCIActionSource source = (SCIActionSource)self.sources[indexPath.row].integerValue;
        NSString *override = [SCIActionIcon overrideForSource:source];
        cell.textLabel.text = [SCIActionCatalog displayNameForSource:source];
        cell.detailTextLabel.text = override.length ? override : SCILocalized(@"Default");
        cell.imageView.image = [self glyphForSymbol:[SCIActionIcon effectiveSymbolNameForSource:source]];
    }
    return cell;
}

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    UIViewController *picker;
    if (indexPath.section == 0) {
        picker = [SCIIconPickerViewController new];
    } else {
        SCIActionSource source = (SCIActionSource)self.sources[indexPath.row].integerValue;
        picker = [[SCIIconPickerViewController alloc] initForSource:source];
    }
    [self.navigationController pushViewController:picker animated:YES];
}

@end
