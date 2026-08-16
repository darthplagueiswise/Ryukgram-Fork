#import "RYGOptionSheet.h"
#import "../Utils.h"

@interface RYGOptionSheetVC : UITableViewController
@property (nonatomic, copy) NSArray<NSDictionary *> *options;
@property (nonatomic, copy, nullable) NSString *defaultsKey;
@property (nonatomic, copy) NSString *currentValue;
@property (nonatomic, copy, nullable) void (^onChange)(NSString *);
@end

@implementation RYGOptionSheetVC

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.allowsSelection = YES;
	self.tableView.alwaysBounceVertical = NO;
	UINavigationItem *nav = self.navigationItem;
	nav.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSelf)];
}

- (void)dismissSelf {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"opt"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"opt"];
	NSDictionary *opt = self.options[(NSUInteger)indexPath.row];
	cell.textLabel.text = opt[@"title"] ?: opt[@"value"];
	cell.textLabel.numberOfLines = 0;
	NSString *desc = opt[@"description"];
	cell.detailTextLabel.text = desc.length ? desc : nil;
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	NSString *value = opt[@"value"] ?: @"";
	cell.accessoryType = [value isEqualToString:self.currentValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.tintColor = [UIColor systemBlueColor];
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *opt = self.options[(NSUInteger)indexPath.row];
	NSString *value = opt[@"value"] ?: @"";
	self.currentValue = value;
	if (self.defaultsKey.length) [[NSUserDefaults standardUserDefaults] setObject:value forKey:self.defaultsKey];
	if (self.onChange) self.onChange(value);
	[tableView reloadData];
	UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[fb impactOccurred];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self dismissViewControllerAnimated:YES completion:nil];
	});
}

@end

@implementation RYGOptionSheet

+ (void)presentFrom:(UIViewController *)presenter
              title:(NSString *)title
        defaultsKey:(NSString *)defaultsKey
            options:(NSArray<NSDictionary<NSString *, NSString *> *> *)options
           onChange:(void (^)(NSString *))onChange {
	if (!presenter || !options.count) return;

	// Present while a previous sheet is mid-dismiss → UIKit rejects.
	// Ride the transition coordinator and re-enter once it lands.
	if (presenter.presentedViewController) {
		id<UIViewControllerTransitionCoordinator> coord = presenter.presentedViewController.transitionCoordinator;
		if (coord) {
			[coord animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> _) {
				[self presentFrom:presenter title:title defaultsKey:defaultsKey options:options onChange:onChange];
			}];
			return;
		}
	}

	RYGOptionSheetVC *vc = [RYGOptionSheetVC new];
	vc.title = title;
	vc.options = options;
	vc.defaultsKey = defaultsKey;
	vc.currentValue = defaultsKey.length ? ([[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey] ?: @"") : @"";
	vc.onChange = onChange;

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	UISheetPresentationController *sheet = nav.sheetPresentationController;
	if (sheet) {
		sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
		sheet.prefersGrabberVisible = YES;
		sheet.preferredCornerRadius = 24.0;
	}
	[presenter presentViewController:nav animated:YES completion:nil];
}

@end
