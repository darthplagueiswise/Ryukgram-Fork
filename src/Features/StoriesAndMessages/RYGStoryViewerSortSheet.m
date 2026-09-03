#import "RYGStoryViewerSortSheet.h"
#import "RYGStoryViewerFilter.h"
#import "../../UI/RYGPopupChrome.h"

@implementation RYGStoryViewerSortSheet

+ (void)presentFrom:(UIViewController *)host hidePinned:(BOOL)hidePinned onChange:(void (^)(void))onChange {
	if (!host) return;
	RYGStoryViewerSortSheet *sheet = [[RYGStoryViewerSortSheet alloc] initWithStyle:UITableViewStyleInsetGrouped];
	sheet.hidePinned = hidePinned;
	sheet.onChange = onChange;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:sheet];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	if (@available(iOS 15.0, *)) {
		UISheetPresentationController *spc = nav.sheetPresentationController;
		spc.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
		spc.prefersGrabberVisible = YES;
		spc.preferredCornerRadius = 22;
		spc.prefersScrollingExpandsWhenScrolledToEdge = NO;   // scroll the list, don't hijack to resize
	}
	[host presentViewController:nav animated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)filterRows {
	NSArray *rows = rygSVFilterRows();
	if (!self.hidePinned) return rows;
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *r in rows) if ([r[@"v"] unsignedIntegerValue] != RYGSVFilterPinned) [out addObject:r];
	return out;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Filter & sort");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { [self.tableView reloadData]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (s == 0) return [self filterRows].count;
	if (s == 1) return rygSVSortRows().count + 1;
	return 1;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if (s == 0) return RYGLocalized(@"Show only");
	if (s == 1) return RYGLocalized(@"Sort by");
	return nil;
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == 0) return self.hidePinned ? RYGLocalized(@"Tick several to combine them.")
	                                   : RYGLocalized(@"Tick several to combine them. Pinned viewers always stay on top and ignore these filters.");
	if (s == 1) return RYGLocalized(@"Settings are saved and reused next time.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.tintColor = UIColor.systemBlueColor;
	if (ip.section == 0) {
		NSDictionary *r = [self filterRows][ip.row];
		cell.textLabel.text = r[@"t"];
		cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
		cell.accessoryType = (rygSVFilter() & [r[@"v"] unsignedIntegerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if (ip.section == 1) {
		if (ip.row < (NSInteger)rygSVSortRows().count) {
			NSDictionary *r = rygSVSortRows()[ip.row];
			cell.textLabel.text = r[@"t"];
			cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
			cell.accessoryType = (rygSVSort() == (RYGSVSort)[r[@"v"] integerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		} else {
			cell.textLabel.text = RYGLocalized(@"Reverse order");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.arrow.down"];
			cell.accessoryType = rygSVReverse() ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		}
	} else {
		cell.textLabel.text = RYGLocalized(@"Reset");
		cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle"];
		BOOL active = rygSVActive();
		cell.textLabel.textColor = active ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
		cell.tintColor = UIColor.systemRedColor;
		cell.selectionStyle = active ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	}
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 0) {
		RYGSVFilter bit = (RYGSVFilter)[[self filterRows][ip.row][@"v"] unsignedIntegerValue];
		rygSVSetFilter(rygSVFilter() ^ bit);
	} else if (ip.section == 1) {
		if (ip.row < (NSInteger)rygSVSortRows().count) rygSVSetSort((RYGSVSort)[rygSVSortRows()[ip.row][@"v"] integerValue]);
		else rygSVSetReverse(!rygSVReverse());
	} else {
		if (!rygSVActive()) return;
		rygSVSetFilter(0); rygSVSetSort(RYGSVSortDefault); rygSVSetReverse(NO);
	}
	if (self.onChange) self.onChange();
	[self refresh];
}

@end
