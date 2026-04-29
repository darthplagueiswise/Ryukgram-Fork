#import "SCIExpPersistedQueryViewController.h"
#import "../Features/ExpFlags/SCIPersistedQueryCatalog.h"

@interface SCIExpPersistedQueryViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<SCIPersistedQueryEntry *> *filteredEntries;
@property (nonatomic, strong) NSArray<SCIPersistedQueryEntry *> *quickSnapEntries;
@property (nonatomic, strong) NSArray<SCIPersistedQueryEntry *> *dogfoodEntries;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@end

@implementation SCIExpPersistedQueryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Persisted GraphQL";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.query = @"";

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyReport)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadCatalog)]
    ];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search operation, doc_id, hash, category";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    [self loadRowsAsync:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadRowsAsync:NO];
}

- (void)reloadCatalog {
    [self loadRowsAsync:YES];
}

- (void)loadRowsAsync:(BOOL)forceReload {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        SCIPersistedQueryCatalog *catalog = [SCIPersistedQueryCatalog sharedCatalog];
        if (forceReload) [catalog reload];

        NSArray *quickSnap = [catalog priorityQuickSnapEntries];
        NSArray *dogfood = [catalog priorityDogfoodEntries];
        NSArray *cats = [catalog allCategories];
        NSArray *filtered = [catalog entriesMatchingQuery:self.query ?: @"" category:nil limit:250];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.quickSnapEntries = quickSnap ?: @[];
            self.dogfoodEntries = dogfood ?: @[];
            self.categories = cats ?: @[];
            self.filteredEntries = filtered ?: @[];
            [self.spinner stopAnimating];
            [self.tableView reloadData];
        });
    });
}

- (void)copyReport {
    NSString *report = [[SCIPersistedQueryCatalog sharedCatalog] diagnosticReport];
    UIPasteboard.generalPasteboard.string = report ?: @"";
    [self showMessage:@"Copied" message:@"Persisted query catalog report copied to clipboard."];
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self loadRowsAsync:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return MAX(1, (NSInteger)self.quickSnapEntries.count);
    if (section == 2) return MAX(1, (NSInteger)self.dogfoodEntries.count);
    if (section == 3) return MAX(1, (NSInteger)self.categories.count);
    return MAX(1, (NSInteger)self.filteredEntries.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Import status";
    if (section == 1) return @"QuickSnap / Instants priority operations";
    if (section == 2) return @"Dogfood / Internal priority operations";
    if (section == 3) return @"Categories";
    return self.query.length ? @"Search results" : @"Catalog sample";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"The catalog is loaded once and indexed in memory. Hooks should use O(1) lookups instead of scanning FBSharedFramework at runtime.";
    if (section == 1) return @"These operation names come from the persisted JSON. In FBSharedFramework 426/26 the exact QuickSnap query names are not present as direct literal strings; QuickSnap runtime still depends on MC/eligibility gates.";
    if (section == 2) return @"ExposeExperimentFromClientQuery is present in the framework. DogfoodingEligibilityQuery is resolved from the persisted JSON catalog.";
    if (section == 3) return @"Categories are heuristic buckets over all imported operation names.";
    return @"Tap any operation to copy operation name, client_doc_id or the full summary line.";
}

- (UITableViewCell *)subtitleCell:(NSString *)identifier {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell entry:(SCIPersistedQueryEntry *)entry {
    cell.textLabel.text = entry.operationName ?: @"unknown";
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · doc=%@\nnameHash=%@ · textHash=%@ · schema=%@",
                                 entry.category ?: @"Other",
                                 entry.clientDocID ?: @"",
                                 entry.operationNameHash ?: @"",
                                 entry.operationTextHash ?: @"",
                                 entry.schema ?: @""];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (UITableViewCell *)emptyCellWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UITableViewCell *cell = [self subtitleCell:@"EmptyCell"];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = subtitle;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [self subtitleCell:@"StatusCell"];
        SCIPersistedQueryCatalog *catalog = [SCIPersistedQueryCatalog sharedCatalog];
        cell.textLabel.text = [NSString stringWithFormat:@"%lu operations imported", (unsigned long)[catalog allEntries].count];
        cell.detailTextLabel.text = [catalog sourceDescription];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 1) {
        if (!self.quickSnapEntries.count) return [self emptyCellWithTitle:@"No QuickSnap priority operations found" subtitle:@"Check whether the full igios-instagram-schema_client-persist.json was embedded or exists in FBSharedFramework.framework."];
        UITableViewCell *cell = [self subtitleCell:@"OperationCell"];
        [self configureCell:cell entry:self.quickSnapEntries[indexPath.row]];
        return cell;
    }

    if (indexPath.section == 2) {
        if (!self.dogfoodEntries.count) return [self emptyCellWithTitle:@"No dogfood priority operations found" subtitle:@"Check the persisted JSON import. ExposeExperimentFromClientQuery should exist in the current framework and JSON."];
        UITableViewCell *cell = [self subtitleCell:@"OperationCell"];
        [self configureCell:cell entry:self.dogfoodEntries[indexPath.row]];
        return cell;
    }

    if (indexPath.section == 3) {
        if (!self.categories.count) return [self emptyCellWithTitle:@"No categories" subtitle:@"Catalog is empty or JSON failed to parse."];
        NSString *category = self.categories[indexPath.row];
        UITableViewCell *cell = [self subtitleCell:@"CategoryCell"];
        cell.textLabel.text = category;
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu operations", (unsigned long)[[SCIPersistedQueryCatalog sharedCatalog] entriesForCategory:category].count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (!self.filteredEntries.count) return [self emptyCellWithTitle:@"No matching operations" subtitle:@"Try another operation name, doc_id, hash or category."];
    UITableViewCell *cell = [self subtitleCell:@"OperationCell"];
    [self configureCell:cell entry:self.filteredEntries[indexPath.row]];
    return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self copyReport];
        return;
    }

    if (indexPath.section == 3 && self.categories.count) {
        NSString *category = self.categories[indexPath.row];
        self.query = category;
        self.searchBar.text = category;
        [self loadRowsAsync:NO];
        return;
    }

    SCIPersistedQueryEntry *entry = nil;
    if (indexPath.section == 1 && indexPath.row < self.quickSnapEntries.count) entry = self.quickSnapEntries[indexPath.row];
    else if (indexPath.section == 2 && indexPath.row < self.dogfoodEntries.count) entry = self.dogfoodEntries[indexPath.row];
    else if (indexPath.section == 4 && indexPath.row < self.filteredEntries.count) entry = self.filteredEntries[indexPath.row];
    if (!entry) return;

    [self presentCopySheetForEntry:entry fromCell:[tableView cellForRowAtIndexPath:indexPath]];
}

- (void)presentCopySheetForEntry:(SCIPersistedQueryEntry *)entry fromCell:(UITableViewCell *)cell {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:entry.operationName
                                                                   message:[entry summaryLine]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy operation_name" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = entry.operationName ?: @"";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy client_doc_id" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = entry.clientDocID ?: @"";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy full line" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [entry summaryLine] ?: @"";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
