#import "RYGChoicePickerVC.h"
#import "../Utils.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGChoicePickerVC ()
@property (nonatomic, copy) NSString *defaultsKey;
@property (nonatomic, copy) NSArray<NSDictionary *> *options;
@end

@implementation RYGChoicePickerVC

- (instancetype)initWithTitle:(NSString *)title defaultsKey:(NSString *)key options:(NSArray<NSDictionary *> *)options {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
		self.title = title;
		_defaultsKey = key;
		_options = options ?: @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = [RYGPopupChrome backgroundColor];
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
	[self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"opt"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.options.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return self.footerText; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"opt" forIndexPath:ip];
	NSDictionary *opt = self.options[ip.row];
	cell.textLabel.text = opt[@"title"];
	cell.textLabel.numberOfLines = 0;
	cell.textLabel.textColor = UIColor.labelColor;
	cell.tintColor = UIColor.systemBlueColor;
	NSString *cur = [RYGUtils getStringPref:self.defaultsKey];
	cell.accessoryType = [opt[@"value"] isEqualToString:cur] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	NSString *value = self.options[ip.row][@"value"];
	if (value.length) [NSUserDefaults.standardUserDefaults setValue:value forKey:self.defaultsKey];
	[tv reloadData];
	[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
	[self.navigationController popViewControllerAnimated:YES];
}

@end
