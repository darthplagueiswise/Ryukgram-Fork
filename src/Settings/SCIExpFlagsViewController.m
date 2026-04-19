#import "SCIExpFlagsViewController.h"

@interface SCIExpFlagsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *items;
@end

@implementation SCIExpFlagsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Experimental flags";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.items = @[
        @{@"title": @"Feature incomplete", @"detail": @"The experimental flags browser source files were missing from this fork. This placeholder keeps the project buildable and preserves the settings entry."},
        @{@"title": @"Hooks toggle", @"detail": @"Use the existing \"Enable hooks\" switch in Settings to control runtime hooks."},
        @{@"title": @"Next step", @"detail": @"You can later replace this controller with the full experiments/MC browser implementation."}
    ];

    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self;
    tableView.delegate = self;
    [self.view addSubview:tableView];
    self.tableView = tableView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.items.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.items[section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"SCIExpFlagsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }

    NSDictionary *item = self.items[indexPath.section];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"detail"];
    return cell;
}

@end
