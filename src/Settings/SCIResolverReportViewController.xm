#import "SCIResolverReportViewController.h"
#import "SCIResolverScanner.h"
#import "SCIResolverSpecifierEntry.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Utils.h"
#import <objc/runtime.h>

@interface SCIResolverReportViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) SCIResolverReportKind kind;
@property (nonatomic, copy) NSString *reportTitle;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<SCIResolverSpecifierEntry *> *specifiers;
@property (nonatomic, copy) NSString *fullReport;
@end

@implementation SCIResolverReportViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _kind = SCIResolverReportKindFull;
        _reportTitle = @"Resolver Report";
    }
    return self;
}

- (instancetype)initWithKind:(SCIResolverReportKind)kind title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _kind = kind;
        _reportTitle = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.reportTitle;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy Report" style:UIBarButtonItemStylePlain target:self action:@selector(copyFullReport)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [self runReport];
}

- (void)runReport {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *report = @"";
        switch (self.kind) {
            case SCIResolverReportKindDogfoodDeveloper:
                report = [SCIResolverScanner runDogfoodDeveloperReport];
                break;
            case SCIResolverReportKindMobileConfigSymbols:
                report = [SCIResolverScanner runMobileConfigSymbolReport];
                break;
            case SCIResolverReportKindFull:
                report = [SCIResolverScanner runFullResolverReport];
                break;
        }
        
        NSArray *specs = [SCIResolverScanner allKnownSpecifierEntries];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fullReport = report;
            self.specifiers = specs;
            [self.tableView reloadData];
        });
    });
}

- (void)copyFullReport {
    if (self.fullReport.length) {
        [UIPasteboard generalPasteboard].string = self.fullReport;
        [SCIUtils showSuccessHUDWithDescription:@"Report copied"];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.specifiers.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Known Specifiers";
    return @"Full Report";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SpecifierCell"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SpecifierCell"];
        
        SCIResolverSpecifierEntry *e = self.specifiers[indexPath.row];
        SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:e.specifier];
        
        cell.textLabel.text = [NSString stringWithFormat:@"%@  0x%016llx", e.name, e.specifier];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        
        NSString *ovStr = (ov == SCIExpFlagOverrideTrue) ? @"True" : (ov == SCIExpFlagOverrideFalse) ? @"False" : @"None";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Source: %@ · Suggested: %@ · Override: %@", e.source, e.suggestedValue ? @"YES" : @"NO", ovStr];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        
        UISwitch *sw = [UISwitch new];
        sw.on = (ov == SCIExpFlagOverrideTrue);
        objc_setAssociatedObject(sw, "sci_spec", @(e.specifier), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sw addTarget:self action:@selector(specifierSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        
        return cell;
    } else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ReportCell"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ReportCell"];
        cell.textLabel.text = @"Copy full text report";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        return cell;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self copyFullReport];
    } else {
        SCIResolverSpecifierEntry *e = self.specifiers[indexPath.row];
        [self presentOverrideSheetForSpecifier:e fromCell:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

- (void)specifierSwitchChanged:(UISwitch *)sender {
    NSNumber *n = objc_getAssociatedObject(sender, "sci_spec");
    if (!n) return;
    unsigned long long spec = n.unsignedLongLongValue;
    [SCIExpFlags setInternalUseOverride:(sender.on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forSpecifier:spec];
    
    // Reload only the affected row to update the detail text
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if (cell.accessoryView == sender) {
            NSIndexPath *ip = [self.tableView indexPathForCell:cell];
            if (ip) [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
            break;
        }
    }
}

- (void)presentOverrideSheetForSpecifier:(SCIResolverSpecifierEntry *)e fromCell:(UITableViewCell *)cell {
    SCIExpFlagOverride cur = [SCIExpFlags internalUseOverrideForSpecifier:e.specifier];
    NSString *title = [NSString stringWithFormat:@"0x%016llx", e.specifier];
    NSString *msg = [NSString stringWithFormat:@"%@\nSource: %@\nSuggested: %@", e.name, e.source, e.suggestedValue ? @"YES" : @"NO"];
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    
    void (^add)(NSString *, SCIExpFlagOverride) = ^(NSString *t, SCIExpFlagOverride v) {
        if (v == cur) t = [t stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [SCIExpFlags setInternalUseOverride:v forSpecifier:e.specifier];
            [self.tableView reloadRowsAtIndexPaths:@[[self.tableView indexPathForCell:cell]] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    };
    
    add(@"No override", SCIExpFlagOverrideOff);
    add(@"Force ON",    SCIExpFlagOverrideTrue);
    add(@"Force OFF",   SCIExpFlagOverrideFalse);
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Hex" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"0x%016llx", e.specifier];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
