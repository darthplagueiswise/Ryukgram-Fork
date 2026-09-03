#import "RYGActionIconListViewController.h"
#import "RYGIconBrowserViewController.h"
#import "RYGIcon.h"
#import "../ActionButton/RYGActionIcon.h"
#import "../Localization/RYGLocalization.h"

static NSString *const kRYGUseDefaultIcon = @"__ryg_use_default__";

@interface RYGActionIconListViewController ()
@property (nonatomic, strong) NSArray<NSNumber *> *sources;
@end

@implementation RYGActionIconListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = RYGLocalized(@"Action button icon");
    self.sources = [RYGActionIcon overridableSources];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (UIImage *)glyphForSymbol:(NSString *)name {
    if ([RYGIcon isIGAssetName:name])
        return [RYGIcon menuImageNamed:name pointSize:22];
    return [RYGIcon sfImageNamed:name pointSize:20 weight:UIImageSymbolWeightSemibold];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)self.sources.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? RYGLocalized(@"Default") : RYGLocalized(@"Per button");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return RYGLocalized(@"Override the icon for a specific button. Buttons left on Default follow the shared icon above.");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kID = @"RYGActionIconRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.imageView.tintColor = [UIColor labelColor];

    if (indexPath.section == 0) {
        NSString *symbol = [RYGActionIcon symbolName];
        cell.textLabel.text = RYGLocalized(@"All buttons");
        cell.detailTextLabel.text = symbol;
        cell.imageView.image = [self glyphForSymbol:symbol];
    } else {
        RYGActionSource source = (RYGActionSource)self.sources[indexPath.row].integerValue;
        NSString *override = [RYGActionIcon overrideForSource:source];
        cell.textLabel.text = [RYGActionCatalog displayNameForSource:source];
        cell.detailTextLabel.text = override.length ? override : RYGLocalized(@"Default");
        cell.imageView.image = [self glyphForSymbol:[RYGActionIcon effectiveSymbolNameForSource:source]];
    }
    return cell;
}

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    RYGIconBrowserViewController *browser;
    if (indexPath.section == 0) {
        browser = [[RYGIconBrowserViewController alloc] initWithTitle:RYGLocalized(@"Action button icon")
                                                         currentName:[RYGActionIcon symbolName]
                                                        specialTitle:nil
                                                         specialIcon:nil
                                                        specialValue:nil
                                                          completion:^(NSString *picked) {
            [RYGActionIcon setSymbolName:picked];
        }];
    } else {
        RYGActionSource source = (RYGActionSource)self.sources[indexPath.row].integerValue;
        NSString *override = [RYGActionIcon overrideForSource:source];
        browser = [[RYGIconBrowserViewController alloc] initWithTitle:[RYGActionCatalog displayNameForSource:source]
                                                         currentName:(override.length ? override : kRYGUseDefaultIcon)
                                                        specialTitle:RYGLocalized(@"Default")
                                                         specialIcon:RYGActionIconDefaultName
                                                        specialValue:kRYGUseDefaultIcon
                                                          completion:^(NSString *picked) {
            if ([picked isEqualToString:kRYGUseDefaultIcon]) [RYGActionIcon setOverride:@"" forSource:source];
            else [RYGActionIcon setOverride:picked forSource:source];
        }];
    }
    [self.navigationController pushViewController:browser animated:YES];
}

@end
