#import "SCIIDListViewController.h"
#import "../Localization/SCILocalization.h"
#import "../Settings/GlassUI/SCIAdaptiveGlass.h"
#import "../Settings/SCISearchBarStyler.h"

@implementation SCIIDListConfig
- (instancetype)init {
	if ((self = [super init])) {
		_allowsEdit = YES;
		_allowsAdd = YES;
	}
	return self;
}
@end

@interface SCIIDListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong, readwrite) SCIIDListConfig *config;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIToolbar *batchToolbar;
@property (nonatomic, strong) UIBarButtonItem *editBtn;
@property (nonatomic, strong) UIBarButtonItem *sortBtn;
@property (nonatomic, copy) NSArray *filtered;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) NSInteger sortMode;
@end

@implementation SCIIDListViewController

- (instancetype)initWithConfig:(SCIIDListConfig *)config {
	if ((self = [super init])) {
		_config = config;
		_filtered = @[];
		_query = @"";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	SCIApplyGlassBackdropToViewController(self);
	self.navigationItem.title = @"";

	_headerView = [UIView new];
	_headerView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_headerView];

	_titleLabel = [UILabel new];
	_titleLabel.text = self.config.title ?: @"";
	_titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
	_titleLabel.textColor = UIColor.labelColor;
	_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[_headerView addSubview:_titleLabel];

	_countLabel = [UILabel new];
	_countLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	_countLabel.textColor = UIColor.secondaryLabelColor;
	_countLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[_headerView addSubview:_countLabel];

	_searchBar = [UISearchBar new];
	_searchBar.delegate = self;
	_searchBar.searchBarStyle = UISearchBarStyleMinimal;
	_searchBar.placeholder = self.config.searchPlaceholder ?: SCILocalized(@"Search");
	_searchBar.translatesAutoresizingMaskIntoConstraints = NO;
	[SCISearchBarStyler styleSearchBar:_searchBar];
	[_headerView addSubview:_searchBar];

	_tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_tableView.dataSource = self;
	_tableView.delegate = self;
	SCIStyleTableViewForGlass(_tableView);
	_tableView.separatorInset = UIEdgeInsetsMake(0, 76, 0, 16);
	_tableView.contentInset = UIEdgeInsetsMake(4, 0, 12, 0);
	_tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	_tableView.allowsMultipleSelectionDuringEditing = YES;
	_tableView.rowHeight = UITableViewAutomaticDimension;
	_tableView.estimatedRowHeight = 72;
	_tableView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_tableView];

	_emptyLabel = [UILabel new];
	_emptyLabel.textColor = UIColor.secondaryLabelColor;
	_emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.numberOfLines = 0;
	_emptyLabel.hidden = YES;
	_emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_emptyLabel];

	_batchToolbar = [UIToolbar new];
	_batchToolbar.hidden = YES;
	_batchToolbar.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_batchToolbar];

	[NSLayoutConstraint activateConstraints:@[
		[_headerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[_headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_titleLabel.topAnchor constraintEqualToAnchor:_headerView.topAnchor constant:12],
		[_titleLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:20],
		[_titleLabel.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-20],
		[_countLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
		[_countLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
		[_countLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
		[_searchBar.topAnchor constraintEqualToAnchor:_countLabel.bottomAnchor constant:8],
		[_searchBar.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:8],
		[_searchBar.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-8],
		[_searchBar.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:-8],
		[_tableView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
		[_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_tableView.bottomAnchor constraintEqualToAnchor:_batchToolbar.topAnchor],
		[_emptyLabel.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
		[_emptyLabel.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor constant:-30],
		[_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
		[_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
		[_batchToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_batchToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_batchToolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
	]];

	NSMutableArray *items = [NSMutableArray new];
	if (self.config.allowsEdit) {
		_editBtn = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Select") style:UIBarButtonItemStylePlain target:self action:@selector(toggleEdit)];
		[items addObject:_editBtn];
	}
	if (self.config.sortTitles.count) {
		_sortBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(tapSort)];
		[items addObject:_sortBtn];
	}
	if (self.config.allowsAdd) {
		[items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(tapAdd)]];
	}
	self.navigationItem.rightBarButtonItems = items;

	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	[self.view endEditing:YES];
}

- (void)reload {
	NSArray *items = self.config.itemsProvider ? self.config.itemsProvider() : @[];
	NSString *q = self.query.lowercaseString ?: @"";

	if (q.length && self.config.matchesQuery) {
		items = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, __unused NSDictionary *_) {
			return self.config.matchesQuery(item, q);
		}]];
	}

	if (self.config.sortedItems) items = self.config.sortedItems(items, self.sortMode);
	self.filtered = items ?: @[];

	NSUInteger count = self.filtered.count;
	self.countLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)count, count == 1 ? SCILocalized(@"item") : SCILocalized(@"items")];
	self.emptyLabel.text = count ? @"" : (q.length ? SCILocalized(@"No results found.") : SCILocalized(@"Nothing here yet."));
	self.emptyLabel.hidden = count > 0;

	[self.tableView reloadData];
	if (self.tableView.isEditing) [self refreshBatchToolbar];
}

- (void)dismissKeyboard {
	[self.searchBar resignFirstResponder];
	[self.view endEditing:YES];
}

- (void)scrollViewWillBeginDragging:(__unused UIScrollView *)scrollView {
	[self dismissKeyboard];
}

- (void)toggleEdit {
	[self dismissKeyboard];

	BOOL editing = !self.tableView.isEditing;
	[self.tableView setEditing:editing animated:YES];
	self.editBtn.title = editing ? SCILocalized(@"Done") : SCILocalized(@"Select");
	self.editBtn.style = editing ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
	self.batchToolbar.hidden = !editing;
	[self refreshBatchToolbar];
}

- (void)exitEdit {
	if (self.tableView.isEditing) [self toggleEdit];
}

- (NSArray *)selectedItems {
	NSMutableArray *items = [NSMutableArray new];
	for (NSIndexPath *ip in self.tableView.indexPathsForSelectedRows ?: @[]) {
		if (ip.row < (NSInteger)self.filtered.count) [items addObject:self.filtered[ip.row]];
	}
	return items;
}

- (void)refreshBatchToolbar {
	if (!self.tableView.isEditing) return;

	NSArray *selected = [self selectedItems];
	UIBarButtonItem *remove = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Remove") style:UIBarButtonItemStylePlain target:self action:@selector(tapBatchRemove)];
	remove.tintColor = UIColor.systemRedColor;
	remove.enabled = selected.count > 0;

	UIBarButtonItem *count = [[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"%lu %@", (unsigned long)selected.count, SCILocalized(@"selected")] style:UIBarButtonItemStylePlain target:nil action:nil];
	count.enabled = NO;

	UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	NSMutableArray *items = [NSMutableArray arrayWithObjects:remove, flex, count, nil];

	if (self.config.extraBatchActions) {
		__weak typeof(self) weak = self;
		NSArray *extra = self.config.extraBatchActions(selected, ^{ [weak reload]; }, ^{ [weak exitEdit]; });
		if (extra.count) {
			[items addObject:flex];
			[items addObjectsFromArray:extra];
		}
	}
	self.batchToolbar.items = items;
}

- (void)tapBatchRemove {
	NSArray *selected = [self selectedItems];
	if (!selected.count || !self.config.onRemoveItem) return;

	for (id item in selected) self.config.onRemoveItem(item);
	[self exitEdit];
	[self reload];
}

- (void)tapSort {
	[self dismissKeyboard];

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Sort by") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSInteger i = 0; i < (NSInteger)self.config.sortTitles.count; i++) {
		UIAlertAction *a = [UIAlertAction actionWithTitle:self.config.sortTitles[i] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
			self.sortMode = i;
			[self reload];
		}];
		if (i == self.sortMode) [a setValue:@YES forKey:@"checked"];
		[sheet addAction:a];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.barButtonItem = self.sortBtn;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)tapAdd {
	[self dismissKeyboard];
	if (!self.config.onAddRequest) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.config.addAlertTitle ?: SCILocalized(@"Add") message:self.config.addAlertMessage preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = self.config.addAlertPlaceholder ?: SCILocalized(@"Enter value");
		tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	__weak typeof(self) weak = self;
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Continue") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (text.length && weak.config.onAddRequest) weak.config.onAddRequest(text, weak, ^{ [weak reload]; });
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)searchBar:(__unused UISearchBar *)searchBar textDidChange:(NSString *)text {
	self.query = text ?: @"";
	[self reload];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
	[self dismissKeyboard];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.query = @"";
	[self dismissKeyboard];
	[self reload];
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
	return self.filtered.count;
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForHeaderInSection:(__unused NSInteger)section {
	return 8;
}

- (UIView *)tableView:(__unused UITableView *)tableView viewForHeaderInSection:(__unused NSInteger)section {
	return [UIView new];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
	static NSString *reuse = @"sciIDListCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
		SCIStyleCellForGlass(cell);
		cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
		cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
		cell.detailTextLabel.numberOfLines = 2;
	}

	id item = self.filtered[ip.row];
	cell.textLabel.text = self.config.titleProvider ? self.config.titleProvider(item) : @"";
	cell.detailTextLabel.text = self.config.subtitleProvider ? self.config.subtitleProvider(item) : @"";
	cell.imageView.image = self.config.iconProvider ? self.config.iconProvider(item) : nil;
	cell.accessoryView = nil;
	cell.accessoryType = tableView.isEditing || !self.config.onTapItem ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[self dismissKeyboard];

	if (tableView.isEditing) {
		[self refreshBatchToolbar];
		return;
	}

	[tableView deselectRowAtIndexPath:ip animated:YES];
	if (self.config.onTapItem && ip.row < (NSInteger)self.filtered.count) self.config.onTapItem(self.filtered[ip.row], self);
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(__unused NSIndexPath *)ip {
	if (tableView.isEditing) [self refreshBatchToolbar];
}

- (UISwipeActionsConfiguration *)tableView:(__unused UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if (!self.config.onRemoveItem || ip.row >= (NSInteger)self.filtered.count) return nil;

	id item = self.filtered[ip.row];
	__weak typeof(self) weak = self;
	UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SCILocalized(@"Remove") handler:^(__unused UIContextualAction *a, __unused UIView *v, void (^done)(BOOL)) {
		self.config.onRemoveItem(item);
		[weak reload];
		done(YES);
	}];

	return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

- (UISwipeActionsConfiguration *)tableView:(__unused UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
	if (!self.config.leadingSwipeActionsForItem || ip.row >= (NSInteger)self.filtered.count) return nil;

	__weak typeof(self) weak = self;
	NSArray *actions = self.config.leadingSwipeActionsForItem(self.filtered[ip.row], ^{ [weak reload]; });
	return actions.count ? [UISwipeActionsConfiguration configurationWithActions:actions] : nil;
}

- (UIContextMenuConfiguration *)tableView:(__unused UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(__unused CGPoint)point {
	if (!self.config.contextMenuForItem || ip.row >= (NSInteger)self.filtered.count) return nil;

	id item = self.filtered[ip.row];
	__weak typeof(self) weak = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(__unused NSArray<UIMenuElement *> *elements) {
		return self.config.contextMenuForItem(item, ^{ [weak reload]; });
	}];
}

@end
