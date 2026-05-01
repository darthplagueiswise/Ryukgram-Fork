#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Utils.h"

@class SCIMCFocusedLabRow;

@interface SCIMCFocusedLabRow : NSObject
@property (nonatomic, assign) unsigned long long paramID;
@property (nonatomic, copy) NSString *paramHex;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *resolvedName;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *gate;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *original;
@property (nonatomic, copy) NSString *overrideKey;
@property (nonatomic, assign) NSUInteger hits;
@property (nonatomic, assign) BOOL wouldChange;
@end

@interface SCIMCFocusedLabViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *targets;
@property (nonatomic, strong) NSArray<SCIMCFocusedLabRow *> *rows;
- (NSString *)activeTargetKey;
- (NSDictionary *)activeTarget;
- (void)setActiveTargetKey:(NSString *)key;
- (void)refresh;
- (BOOL)effectiveValueForRow:(SCIMCFocusedLabRow *)row;
- (NSString *)specifierHex:(unsigned long long)specifier;
@end

static const void *kSCIMCSortOverlaySwitchKey = &kSCIMCSortOverlaySwitchKey;

static NSString *SCIMCSafe(NSString *value) {
    return value ?: @"";
}

static NSString *SCIMCActiveTargetTitle(SCIMCFocusedLabViewController *vc) {
    NSDictionary *target = [vc activeTarget] ?: @{};
    NSString *title = target[@"title"] ?: @"All";
    NSString *subtitle = target[@"subtitle"] ?: @"";
    if (subtitle.length) return [NSString stringWithFormat:@"%@ / %@", title, subtitle];
    return title;
}

%hook SCIMCFocusedLabViewController

- (void)viewDidLoad {
    %orig;

    UIBarButtonItem *bulkItem = [[UIBarButtonItem alloc] initWithTitle:@"Bulk"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(showBulkMenu)];
    UIBarButtonItem *sortItem = [[UIBarButtonItem alloc] initWithTitle:@"Sort"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(showSortMenu)];
    self.navigationItem.rightBarButtonItems = @[bulkItem, sortItem];
}

%new
- (void)showSortMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sort / Filter"
                                                                   message:@"Escolha uma categoria, gate C ou getter ObjC. A lista principal mostra os observed bools desse filtro."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *active = [self activeTargetKey] ?: @"";

    for (NSDictionary *target in self.targets ?: @[]) {
        NSString *key = target[@"key"] ?: @"";
        NSString *title = target[@"title"] ?: @"";
        NSString *subtitle = target[@"subtitle"] ?: @"";
        NSString *label = subtitle.length ? [NSString stringWithFormat:@"%@ — %@", title, subtitle] : title;
        if ([key isEqualToString:active]) label = [@"✓ " stringByAppendingString:label];

        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self setActiveTargetKey:key];
            [self refresh];
            [SCIUtils showSuccessHUDWithDescription:@"Sort applied"];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        NSArray<UIBarButtonItem *> *items = self.navigationItem.rightBarButtonItems;
        sheet.popoverPresentationController.barButtonItem = items.count > 1 ? items[1] : self.navigationItem.rightBarButtonItem;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Observed bools — %@", SCIMCActiveTargetTitle(self)];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Use Sort para trocar categoria/gate/getter. O switch reflete o valor efetivo observado; tocar cria override seletivo só para aquele param/nome.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mc-focused-sort-row"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc-focused-sort-row"];
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if ((NSUInteger)indexPath.row >= self.rows.count) {
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = @"";
        return cell;
    }

    SCIMCFocusedLabRow *row = self.rows[(NSUInteger)indexPath.row];
    SCIExpFlagOverride ov = [SCIExpFlags overrideForName:row.overrideKey ?: @""];
    NSString *ovText = ov == SCIExpFlagOverrideTrue ? @"FORCED ON" : (ov == SCIExpFlagOverrideFalse ? @"FORCED OFF" : @"default");
    NSString *change = row.wouldChange ? @" WOULD_TRUE" : @"";

    cell.textLabel.text = [NSString stringWithFormat:@"[%@] %@ %@%@",
                           SCIMCSafe(row.category),
                           SCIMCSafe(row.name),
                           SCIMCSafe(row.paramHex),
                           change];

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · original=%@ · effective=%@ · override=%@ · ×%lu",
                                 SCIMCSafe(row.gate),
                                 row.original.length ? row.original : @"?",
                                 [self effectiveValueForRow:row] ? @"YES" : @"NO",
                                 ovText,
                                 (unsigned long)row.hits];

    UISwitch *sw = [UISwitch new];
    sw.on = [self effectiveValueForRow:row];
    objc_setAssociatedObject(sw, kSCIMCSortOverlaySwitchKey, row.overrideKey ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sw addTarget:self action:@selector(sortOverlaySwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;

    return cell;
}

%new
- (void)sortOverlaySwitchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, kSCIMCSortOverlaySwitchKey);
    if (!key.length) return;

    [SCIExpFlags setOverride:(sender.on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forName:key];
    [self refresh];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= self.rows.count) return;

    SCIMCFocusedLabRow *row = self.rows[(NSUInteger)indexPath.row];

    NSString *msg = [NSString stringWithFormat:@"gate=%@\nparam=%@\nname=%@\nresolved=%@\ncategory=%@\noriginal=%@\neffective=%@\noverrideKey=%@\nhits=%lu\n\n%@",
                     SCIMCSafe(row.gate),
                     SCIMCSafe(row.paramHex),
                     SCIMCSafe(row.name),
                     SCIMCSafe(row.resolvedName),
                     SCIMCSafe(row.category),
                     SCIMCSafe(row.original),
                     [self effectiveValueForRow:row] ? @"YES" : @"NO",
                     SCIMCSafe(row.overrideKey),
                     (unsigned long)row.hits,
                     SCIMCSafe(row.detail)];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.name ?: @"MC bool"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy row" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = msg;
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"No override" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [SCIExpFlags setOverride:SCIExpFlagOverrideOff forName:row.overrideKey ?: @""];
        [self refresh];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [SCIExpFlags setOverride:SCIExpFlagOverrideTrue forName:row.overrideKey ?: @""];
        [self refresh];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [SCIExpFlags setOverride:SCIExpFlagOverrideFalse forName:row.overrideKey ?: @""];
        [self refresh];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

%end
