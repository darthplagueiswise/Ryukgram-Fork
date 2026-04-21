#import "SCIExpFlagsViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"

@interface SCIExpFlagsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SCIExpObservation *> *metaItems;
@property (nonatomic, copy) NSArray<SCIExpMCObservation *> *mcItems;
@end

@implementation SCIExpFlagsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Experimental flags";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(backTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Reset"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(resetTapped)];

    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self;
    tableView.delegate = self;
    [self.view addSubview:tableView];
    self.tableView = tableView;

    [self reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}

- (void)backTapped {
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reloadData {
    self.metaItems = [SCIExpFlags allObservations];
    self.mcItems = [SCIExpFlags allMCObservations];
    [self.tableView reloadData];
}

- (void)resetTapped {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset experimental overrides"
                                                               message:@"Clear MetaLocalExperiment and IGMobileConfig overrides?"
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear all" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [SCIExpFlags resetAllOverrides];
        [SCIExpFlags resetAllMCOverrides];
        [self reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return MAX((NSInteger)self.metaItems.count, 1);
    return MAX((NSInteger)self.mcItems.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Status";
    if (section == 1) return @"MetaLocalExperiment";
    return @"IGMobileConfigContextManager";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"MetaLocalExperiment rows can be overridden by experiment name. IGMobileConfig rows are overridden by raw param ID and type.";
    }
    if (section == 1) {
        return @"Tap a row to cycle override: Off → Force On → Force Off.";
    }
    return @"Tap a BOOL row to cycle override. Tap INT/DOUBLE/STRING rows to set or clear a raw override value.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"SCIExpFlagsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Observed MetaLocalExperiment names";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.metaItems.count];
        } else {
            cell.textLabel.text = @"Observed IGMobileConfig param IDs";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.mcItems.count];
        }
        return cell;
    }

    if (indexPath.section == 1) {
        if (self.metaItems.count == 0) {
            cell.textLabel.text = @"No MetaLocalExperiment observations yet";
            cell.detailTextLabel.text = @"Open surfaces that query experiments, then come back here.";
            return cell;
        }
        SCIExpObservation *item = self.metaItems[(NSUInteger)indexPath.row];
        SCIExpFlagOverride o = [SCIExpFlags overrideForName:item.experimentName];
        NSString *state = (o == SCIExpFlagOverrideTrue) ? @"Force On" : (o == SCIExpFlagOverrideFalse) ? @"Force Off" : @"Off";
        cell.textLabel.text = item.experimentName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"group=%@ • hits=%lu • override=%@", item.lastGroup ?: @"", (unsigned long)item.hitCount, state];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    if (self.mcItems.count == 0) {
        cell.textLabel.text = @"No IGMobileConfig observations yet";
        cell.detailTextLabel.text = @"The hook observes getBool/getInt64/getDouble/getString calls once the app touches them.";
        return cell;
    }

    SCIExpMCObservation *item = self.mcItems[(NSUInteger)indexPath.row];
    NSString *type = @[@"BOOL", @"INT64", @"DOUBLE", @"STRING"][(NSUInteger)item.type];
    id override = [SCIExpFlags mcOverrideObjectForParamID:item.paramID type:item.type];
    NSString *ovText = override ? [override description] : @"Off";
    cell.textLabel.text = [NSString stringWithFormat:@"%llu (%@)", item.paramID, type];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"default=%@ • hits=%lu • override=%@", item.lastDefault ?: @"", (unsigned long)item.hitCount, ovText];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && self.metaItems.count > 0) {
        SCIExpObservation *item = self.metaItems[(NSUInteger)indexPath.row];
        SCIExpFlagOverride o = [SCIExpFlags overrideForName:item.experimentName];
        SCIExpFlagOverride next = (o == SCIExpFlagOverrideOff) ? SCIExpFlagOverrideTrue : (o == SCIExpFlagOverrideTrue) ? SCIExpFlagOverrideFalse : SCIExpFlagOverrideOff;
        [SCIExpFlags setOverride:next forName:item.experimentName];
        [self reloadData];
        return;
    }
    if (indexPath.section == 2 && self.mcItems.count > 0) {
        SCIExpMCObservation *item = self.mcItems[(NSUInteger)indexPath.row];
        if (item.type == SCIExpMCTypeBool) {
            NSNumber *o = [SCIExpFlags mcOverrideObjectForParamID:item.paramID type:item.type];
            id next = nil;
            if (!o) next = @YES;
            else if (o.boolValue) next = @NO;
            else next = nil;
            [SCIExpFlags setMCOverrideObject:next forParamID:item.paramID type:item.type];
            [self reloadData];
        } else {
            [self presentEditorForMCObservation:item];
        }
    }
}

- (void)presentEditorForMCObservation:(SCIExpMCObservation *)item {
    NSString *title = [NSString stringWithFormat:@"%llu", item.paramID];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:@"Set a raw override value"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        id current = [SCIExpFlags mcOverrideObjectForParamID:item.paramID type:item.type];
        tf.placeholder = item.lastDefault ?: @"";
        tf.text = current ? [current description] : @"";
        if (item.type == SCIExpMCTypeInt) tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        else if (item.type == SCIExpMCTypeDouble) tf.keyboardType = UIKeyboardTypeDecimalPad;
        else tf.keyboardType = UIKeyboardTypeDefault;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
        [SCIExpFlags setMCOverrideObject:nil forParamID:item.paramID type:item.type];
        [self reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *text = a.textFields.firstObject.text ?: @"";
        id value = nil;
        if (item.type == SCIExpMCTypeInt) value = @([text longLongValue]);
        else if (item.type == SCIExpMCTypeDouble) value = @([text doubleValue]);
        else value = text;
        [SCIExpFlags setMCOverrideObject:value forParamID:item.paramID type:item.type];
        [self reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
