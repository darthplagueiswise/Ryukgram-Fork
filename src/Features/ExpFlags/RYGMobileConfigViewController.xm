#import "RYGMobileConfigViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigBackup.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Localization/RYGLocalization.h"
#import "../../Utils.h"
#import <objc/runtime.h>

static UIColor *RYGMCAccent(void) { return [UIColor systemOrangeColor]; }
static const void *kRYGMCParamKey = &kRYGMCParamKey;

@interface RYGMCConfigDetailViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) RYGMCConfig *config;
@end

#pragma mark - list

@interface RYGMobileConfigViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UISegmentedControl *scope;
@property (nonatomic, strong) NSArray<RYGMCConfig *> *rows;
@property (nonatomic, strong) NSArray<NSNumber *> *rowOverrideCounts;
@property (nonatomic, strong) NSArray<NSString *> *rowParamHits;
@end

@implementation RYGMobileConfigViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.title = RYGLocalized(@"MobileConfig");

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [RYGPopupChrome backgroundColor];
    [self.view addSubview:bar];

    self.scope = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"All"), RYGLocalized(@"Overridden")]];
    self.scope.selectedSegmentIndex = 0;
    self.scope.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scope addTarget:self action:@selector(scopeChanged) forControlEvents:UIControlEventValueChanged];
    [bar addSubview:self.scope];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.estimatedRowHeight = 64;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:g.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.scope.topAnchor constraintEqualToAnchor:bar.topAnchor constant:6],
        [self.scope.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-6],
        [self.scope.leadingAnchor constraintEqualToAnchor:bar.layoutMarginsGuide.leadingAnchor],
        [self.scope.trailingAnchor constraintEqualToAnchor:bar.layoutMarginsGuide.trailingAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = RYGLocalized(@"Search name or config number");
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[self menu]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
                                                 name:@"RYGMobileConfigNamesDidChange" object:nil];
    [self reload];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)scopeChanged {
    [self reload];
    if (self.rows.count)
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                              atScrollPosition:UITableViewScrollPositionTop animated:NO];
}

- (UIMenu *)menu {
    __weak __typeof__(self) ws = self;
    RYGMobileConfig *e = [RYGMobileConfig shared];
    UIAction *reset = [UIAction actionWithTitle:RYGLocalized(@"Reset all overrides")
                                          image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                                     identifier:nil handler:^(__kindof UIAction *a) {
        UIAlertController *c = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset all overrides?")
                                                                  message:[NSString stringWithFormat:RYGLocalized(@"%lu override(s) will be removed."), (unsigned long)e.overrideCount]
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a2) {
            [e resetAllOverrides]; [ws reload];
        }]];
        [ws presentViewController:c animated:YES completion:nil];
    }];
    reset.attributes = e.overrideCount ? 0 : UIMenuElementAttributesDisabled;

    UIAction *exportAction = [UIAction actionWithTitle:RYGLocalized(@"Export overrides")
                                                 image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                            identifier:nil handler:^(__kindof UIAction *a) {
        [RYGMobileConfigBackup presentExportFrom:ws];
    }];
    UIAction *importAction = [UIAction actionWithTitle:RYGLocalized(@"Import overrides")
                                                 image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                            identifier:nil handler:^(__kindof UIAction *a) {
        [RYGMobileConfigBackup presentImportFrom:ws completion:^{ [ws reload]; }];
    }];

    UIMenu *backup = [UIMenu menuWithTitle:@"" image:nil identifier:nil
                                   options:UIMenuOptionsDisplayInline children:@[exportAction, importAction]];
    return [UIMenu menuWithChildren:@[backup, reset]];
}

- (void)reload {
    BOOL onlyOv = self.scope.selectedSegmentIndex == 1;
    RYGMobileConfig *e = [RYGMobileConfig shared];
    NSString *query = self.search.searchBar.text;
    self.rows = [e configsMatching:query onlyOverridden:onlyOv];

    BOOL anyOverride = e.overrideCount > 0;
    BOOL searching = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length > 0;
    NSMutableArray<NSNumber *> *counts = [NSMutableArray arrayWithCapacity:self.rows.count];
    NSMutableArray<NSString *> *hints = [NSMutableArray arrayWithCapacity:self.rows.count];
    for (RYGMCConfig *c in self.rows) {
        NSUInteger ov = 0;
        if (anyOverride)
            for (RYGMCParam *p in c.params) if ([e overrideStateFor:p] == RYGMCOverrideSet) ov++;
        [counts addObject:@(ov)];
        NSArray<NSString *> *pm = searching ? [e paramNamesMatching:query inConfig:c] : nil;
        [hints addObject:pm.count ? [pm componentsJoinedByString:@", "] : @""];
    }
    self.rowOverrideCounts = counts;
    self.rowParamHits = hints;

    [self.scope setTitle:e.overrideCount ? [NSString stringWithFormat:@"%@ (%lu)", RYGLocalized(@"Overridden"), (unsigned long)e.overrideCount]
                                         : RYGLocalized(@"Overridden")
       forSegmentAtIndex:1];
    self.navigationItem.rightBarButtonItem.menu = [self menu];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc { [self reload]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    RYGMCConfig *c = self.rows[ip.row];
    NSUInteger ov = ip.row < self.rowOverrideCounts.count ? self.rowOverrideCounts[ip.row].unsignedIntegerValue : 0;

    cell.textLabel.text = c.displayName;
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:c.name.length ? UIFontWeightSemibold : UIFontWeightRegular];
    cell.textLabel.textColor = c.name.length ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSMutableAttributedString *sub = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%u · %lu %@", c.number, (unsigned long)c.params.count,
                        c.params.count == 1 ? RYGLocalized(@"param") : RYGLocalized(@"params")]
        attributes:@{NSForegroundColorAttributeName: [UIColor secondaryLabelColor], NSFontAttributeName: [UIFont systemFontOfSize:12]}];
    if (ov) [sub appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"  ·  %lu %@", (unsigned long)ov, RYGLocalized(@"overridden")]
        attributes:@{NSForegroundColorAttributeName: RYGMCAccent(), NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]}]];

    NSString *hint = ip.row < self.rowParamHits.count ? self.rowParamHits[ip.row] : @"";
    if (hint.length) [sub appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"\n%@ %@", RYGLocalized(@"Parameter:"), hint]
        attributes:@{NSForegroundColorAttributeName: [UIColor systemBlueColor], NSFontAttributeName: [UIFont systemFontOfSize:12]}]];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.attributedText = sub;

    if (ov) {
        cell.imageView.image = [UIImage systemImageNamed:@"circle.fill"];
        cell.imageView.tintColor = RYGMCAccent();
    } else {
        cell.imageView.image = [UIImage systemImageNamed:c.name.length ? @"slider.horizontal.3" : @"number"];
        cell.imageView.tintColor = [UIColor tertiaryLabelColor];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    RYGMCConfigDetailViewController *d = [[RYGMCConfigDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    d.config = self.rows[ip.row];
    [self.navigationController pushViewController:d animated:YES];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    RYGMobileConfig *e = [RYGMobileConfig shared];
    return [NSString stringWithFormat:RYGLocalized(@"%lu configs  ·  %lu named"),
            (unsigned long)self.rows.count, (unsigned long)e.namedConfigCount];
}

// Long-press a config to reset just its overrides.
- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    RYGMobileConfig *e = [RYGMobileConfig shared];
    RYGMCConfig *c = self.rows[ip.row];
    NSUInteger ov = ip.row < self.rowOverrideCounts.count ? self.rowOverrideCounts[ip.row].unsignedIntegerValue : 0;
    if (!ov) return nil;
    __weak __typeof__(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *sug) {
        UIAction *reset = [UIAction actionWithTitle:[NSString stringWithFormat:RYGLocalized(@"Reset %lu override(s)"), (unsigned long)ov]
                                              image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                                         identifier:nil handler:^(__kindof UIAction *a) {
            [e resetOverridesForConfig:c]; [ws reload];
        }];
        reset.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithTitle:c.displayName children:@[reset]];
    }];
}

@end

#pragma mark - detail

@interface RYGMCConfigDetailViewController ()
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSArray<RYGMCParam *> *shown;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *liveCache;
@end

@implementation RYGMCConfigDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.config.displayName;
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = 58;
    self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;

    self.liveCache = [NSMutableDictionary dictionary];
    self.shown = self.config.params ?: @[];

    if (self.config.params.count > 8) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.search.searchResultsUpdater = self;
        self.search.obscuresBackgroundDuringPresentation = NO;
        self.search.searchBar.placeholder = RYGLocalized(@"Search");
        self.navigationItem.searchController = self.search;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        self.definesPresentationContext = YES;
    }
}

- (void)applyFilter {
    NSString *q = self.search.searchBar.text ?: @"";
    self.shown = [[RYGMobileConfig shared] paramsMatching:q inConfig:self.config];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc { [self applyFilter]; }

- (id)liveFor:(RYGMCParam *)p {
    NSNumber *key = @(p.paramID);
    id v = self.liveCache[key];
    if (!v) {
        v = [[RYGMobileConfig shared] liveValueFor:p] ?: [NSNull null];
        self.liveCache[key] = v;
    }
    return v == [NSNull null] ? nil : v;
}

// section 0 = config info (copiable), sections 1..n = one per param
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1 + self.shown.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? (self.config.name.length ? 2 : 1) : 1;
}

- (RYGMCParam *)paramAtSection:(NSInteger)s {
    NSInteger i = s - 1;
    return (i >= 0 && i < (NSInteger)self.shown.count) ? self.shown[i] : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return RYGLocalized(@"Config");
    RYGMCParam *p = [self paramAtSection:s];
    if (!p) return nil;
    return p.name.length ? p.name : [NSString stringWithFormat:@"#%u", p.paramIndex];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return RYGLocalized(@"Tap a field to copy. Tap a value below to edit.");
    return nil;
}

- (void)configureParamCell:(UITableViewCell *)cell param:(RYGMCParam *)p {
    RYGMobileConfig *e = [RYGMobileConfig shared];
    BOOL overridden = [e overrideStateFor:p] == RYGMCOverrideSet;

    cell.textLabel.text = overridden ? RYGLocalized(@"Override") : RYGLocalized(@"Value");
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];

    NSString *meta = [NSString stringWithFormat:@"%@ · #%u", p.typeName, p.paramIndex];
    NSString *note = [e noteFor:p];
    if (note.length) meta = [meta stringByAppendingFormat:@" · “%@”", note];
    cell.detailTextLabel.text = meta;
    cell.detailTextLabel.textColor = overridden ? RYGMCAccent() : [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    cell.imageView.image = [UIImage systemImageNamed:overridden ? @"circle.fill" : @"circle"];
    cell.imageView.tintColor = overridden ? RYGMCAccent() : [UIColor tertiaryLabelColor];

    if (p.type == RYGMCTypeBool) {
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        sw.on = overridden ? [[e overrideValueFor:p] boolValue] : [[self liveFor:p] boolValue];
        sw.onTintColor = overridden ? RYGMCAccent() : nil;
        objc_setAssociatedObject(sw, kRYGMCParamKey, p, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        UILabel *val = (UILabel *)cell.accessoryView;
        id shown = overridden ? [e overrideValueFor:p] : [self liveFor:p];
        val.text = shown ? [shown description] : @"—";
        val.textColor = overridden ? RYGMCAccent() : [UIColor secondaryLabelColor];
        [val sizeToFit];
        if (val.frame.size.width > 150) val.frame = CGRectMake(0, 0, 150, val.frame.size.height);
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"info"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"info"];
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
            cell.detailTextLabel.textColor = [UIColor labelColor];
            cell.detailTextLabel.numberOfLines = 2;
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        }
        if (self.config.name.length && ip.row == 0) {
            cell.textLabel.text = RYGLocalized(@"Name");
            cell.detailTextLabel.text = self.config.name;
        } else {
            cell.textLabel.text = RYGLocalized(@"Number");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%u", self.config.number];
        }
        return cell;
    }

    RYGMCParam *p = [self paramAtSection:ip.section];
    BOOL isBool = p.type == RYGMCTypeBool;
    NSString *rid = isBool ? @"sw" : @"val";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
        if (isBool) {
            UISwitch *sw = [UISwitch new];
            [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            UILabel *val = [[UILabel alloc] init];
            val.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
            cell.accessoryView = val;
        }
    }
    if (p) [self configureParamCell:cell param:p];
    return cell;
}

- (void)refreshRowForParam:(RYGMCParam *)p {
    NSUInteger i = [self.shown indexOfObject:p];
    if (i == NSNotFound) return;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:(NSInteger)i + 1];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    if (cell) [self configureParamCell:cell param:p];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        NSString *copied = (self.config.name.length && ip.row == 0)
            ? self.config.name : [NSString stringWithFormat:@"%u", self.config.number];
        [UIPasteboard generalPasteboard].string = copied;
        [RYGUtils showToastForDuration:1.2 title:RYGLocalized(@"Copied") subtitle:copied];
        return;
    }
    RYGMCParam *p = [self paramAtSection:ip.section];
    if (!p || p.type == RYGMCTypeBool) return;
    [self editValueFor:p];
}

- (void)toggle:(UISwitch *)sw {
    RYGMCParam *p = objc_getAssociatedObject(sw, kRYGMCParamKey);
    if (!p) return;
    [[RYGMobileConfig shared] setOverride:@(sw.on) for:p];
    [self.liveCache removeObjectForKey:@(p.paramID)];
    [self refreshRowForParam:p];
}

- (void)editValueFor:(RYGMCParam *)p {
    RYGMobileConfig *e = [RYGMobileConfig shared];
    BOOL overridden = [e overrideStateFor:p] == RYGMCOverrideSet;
    UIAlertController *c = [UIAlertController alertControllerWithTitle:(p.name.length ? p.name : [NSString stringWithFormat:@"#%u", p.paramIndex])
                                                              message:[NSString stringWithFormat:RYGLocalized(@"Type: %@   ·   live: %@"), p.typeName, [self liveFor:p] ?: @"—"]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [c addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        id v = overridden ? [e overrideValueFor:p] : [self liveFor:p];
        tf.text = v ? [v description] : @"";
        tf.keyboardType = (p.type == RYGMCTypeString) ? UIKeyboardTypeDefault :
            (p.type == RYGMCTypeDouble ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumbersAndPunctuation);
        tf.clearButtonMode = UITextFieldViewModeAlways;
    }];
    __weak __typeof__(self) ws = self;
    [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    if (overridden)
        [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear override") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [e clearOverrideFor:p];
            [ws.liveCache removeObjectForKey:@(p.paramID)];
            [ws refreshRowForParam:p];
        }]];
    [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Set") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *t = c.textFields.firstObject.text ?: @"";
        id value;
        switch (p.type) {
            case RYGMCTypeInt:    value = @(strtoll(t.UTF8String, NULL, 10)); break;
            case RYGMCTypeDouble: value = @(t.doubleValue); break;
            default:              value = t; break;
        }
        [e setOverride:value for:p];
        [ws.liveCache removeObjectForKey:@(p.paramID)];
        [ws refreshRowForParam:p];
    }]];
    [self presentViewController:c animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return nil;
    RYGMobileConfig *e = [RYGMobileConfig shared];
    RYGMCParam *p = [self paramAtSection:ip.section];
    if (!p) return nil;
    __weak __typeof__(self) ws = self;
    NSMutableArray *acts = [NSMutableArray array];
    if ([e overrideStateFor:p] == RYGMCOverrideSet) {
        UIContextualAction *clr = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                          title:RYGLocalized(@"Clear")
                                                                        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [e clearOverrideFor:p];
            [ws.liveCache removeObjectForKey:@(p.paramID)];
            [ws refreshRowForParam:p];
            done(YES);
        }];
        [acts addObject:clr];
    }
    UIContextualAction *note = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                       title:RYGLocalized(@"Note")
                                                                     handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [ws editNoteFor:p]; done(YES);
    }];
    note.backgroundColor = [UIColor systemBlueColor];
    [acts addObject:note];
    return [UISwipeActionsConfiguration configurationWithActions:acts];
}

- (void)editNoteFor:(RYGMCParam *)p {
    RYGMobileConfig *e = [RYGMobileConfig shared];
    UIAlertController *c = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Note")
                                                              message:(p.name.length ? p.name : nil) preferredStyle:UIAlertControllerStyleAlert];
    [c addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [e noteFor:p]; }];
    __weak __typeof__(self) ws = self;
    [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [e setNote:c.textFields.firstObject.text for:p];
        [ws refreshRowForParam:p];
    }]];
    [self presentViewController:c animated:YES completion:nil];
}

@end
