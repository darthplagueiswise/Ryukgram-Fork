#import "RYGUserPickerViewController.h"
#import "RYGPopupChrome.h"
#import "../RYGImageCache.h"
#import "../Networking/RYGInstagramAPI.h"
#import "../Utils.h"

static NSString *upStr(id v) { return [v isKindOfClass:NSString.class] ? v : v ? [v description] : @""; }

@interface RYGUserPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) void (^onPick)(NSDictionary *user);
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<NSDictionary *> *recent;
@property (nonatomic, strong) NSArray<NSDictionary *> *results;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy, nullable) NSString *idLabel;
@property (nonatomic, assign) NSUInteger searchGen;
@property (nonatomic, assign) BOOL loadingRecents;
@end

@implementation RYGUserPickerViewController

+ (void)presentFromViewController:(UIViewController *)presenter title:(NSString *)title onPick:(void (^)(NSDictionary *))onPick {
    [self presentFromViewController:presenter title:title idLabel:nil onPick:onPick];
}

+ (void)presentFromViewController:(UIViewController *)presenter title:(NSString *)title idLabel:(NSString *)idLabel onPick:(void (^)(NSDictionary *))onPick {
    RYGUserPickerViewController *vc = [RYGUserPickerViewController new];
    vc.onPick = onPick;
    vc.idLabel = idLabel;
    vc.title = title.length ? title : RYGLocalized(@"Add user");
    [RYGPopupChrome presentVC:vc from:presenter];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.query = @"";
    self.results = @[];
    self.recent = @[];
    [self loadRecent];

    self.searchBar = [UISearchBar new];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = RYGLocalized(@"Search by username");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.backgroundImage = [UIImage new];
    [self.searchBar sizeToFit];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.tableHeaderView = self.searchBar;
    [self.view addSubview:self.tableView];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { [self runSearch:text]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar { searchBar.text = @""; [searchBar resignFirstResponder]; [self runSearch:@""]; }

- (void)loadRecent {
    self.loadingRecents = YES;
    __weak typeof(self) ws = self;
    [RYGInstagramAPI fetchRankedRecipientsWithCompletion:^(NSArray<NSDictionary *> *users, NSError *error) {
        NSString *me = [RYGUtils currentUserPK];
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *u in users ?: @[]) {
            NSString *pk = upStr(u[@"pk"]);
            if (!pk.length || (me.length && [pk isEqualToString:me])) continue;
            if (!upStr(u[@"username"]).length) continue;
            [out addObject:@{ @"pk": pk, @"username": upStr(u[@"username"]), @"fullName": upStr(u[@"full_name"]), @"profilePicURL": upStr(u[@"profile_pic_url"]) }];
        }
        ws.recent = out;
        ws.loadingRecents = NO;
        if (!ws.query.length) [ws.tableView reloadData];
    }];
}

#pragma mark - Search

- (void)runSearch:(NSString *)text {
    NSString *q = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    self.query = q;
    if (!q.length) { self.results = @[]; [self.tableView reloadData]; return; }

    NSString *local = q.lowercaseString;
    NSMutableArray *quick = [NSMutableArray array];
    for (NSDictionary *e in self.recent)
        if ([upStr(e[@"username"]).lowercaseString containsString:local]) [quick addObject:e];
    self.results = quick;
    [self.tableView reloadData];

    NSUInteger gen = ++self.searchGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != self.searchGen || ![self.query isEqualToString:q]) return;
        [RYGInstagramAPI searchUsersWithQuery:q completion:^(NSArray<NSDictionary *> *users, NSError *error) {
            if (gen != self.searchGen) return;
            NSMutableArray *merged = [NSMutableArray array];
            NSMutableSet *seen = [NSMutableSet set];
            for (NSDictionary *e in self.recent)
                if ([upStr(e[@"username"]).lowercaseString containsString:local]) { [merged addObject:e]; [seen addObject:upStr(e[@"pk"])]; }
            for (NSDictionary *u in users ?: @[]) {
                NSString *pk = upStr(u[@"pk"]);
                if (!pk.length || [seen containsObject:pk]) continue;
                [seen addObject:pk];
                [merged addObject:@{ @"pk": pk, @"username": upStr(u[@"username"]), @"fullName": upStr(u[@"full_name"]), @"profilePicURL": upStr(u[@"profile_pic_url"]) }];
            }
            self.results = merged;
            [self.tableView reloadData];
        }];
    });
}

- (BOOL)queryIsPK {
    return self.query.length >= 3 && [self.query rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

- (NSArray<NSDictionary *> *)activeList {
    if (!self.query.length) return self.recent;
    if (![self queryIsPK]) return self.results;
    NSDictionary *pkRow = @{ @"pk": self.query, @"username": @"", @"fullName": self.idLabel.length ? self.idLabel : RYGLocalized(@"Add by user ID"), @"profilePicURL": @"", @"manualID": @YES };
    return [@[pkRow] arrayByAddingObjectsFromArray:self.results];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.activeList.count; }

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (self.query.length) return self.activeList.count ? RYGLocalized(@"Results") : nil;
    return self.recent.count ? RYGLocalized(@"Recent in your DMs") : nil;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (self.query.length && !self.activeList.count) return RYGLocalized(@"No one found. Check the spelling or try a different name.");
    if (!self.query.length && self.loadingRecents) return RYGLocalized(@"Loading…");
    if (!self.query.length && !self.recent.count) return RYGLocalized(@"Open some chats first, or search a username above.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"u"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"u"];
    c.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    NSDictionary *e = self.activeList[ip.row];
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    NSString *un = upStr(e[@"username"]);
    c.textLabel.text = un.length ? [@"@" stringByAppendingString:un] : upStr(e[@"pk"]);
    c.detailTextLabel.text = upStr(e[@"fullName"]);
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    UIImageView *iv = c.imageView;
    iv.image = [UIImage systemImageNamed:@"person.circle.fill"];
    iv.tintColor = UIColor.systemGray3Color;
    NSString *urlStr = upStr(e[@"profilePicURL"]);
    iv.accessibilityValue = urlStr;
    if (urlStr.length) {
        NSURL *url = [NSURL URLWithString:urlStr];
        if (url) [RYGImageCache loadImageFromURL:url cacheKey:upStr(e[@"pk"]) completion:^(UIImage *img) {
            if (!img) return;
            UITableViewCell *cell = [t cellForRowAtIndexPath:ip];
            if (cell && [cell.imageView.accessibilityValue isEqualToString:urlStr]) {
                cell.imageView.image = [self rounded:img];
                [cell setNeedsLayout];
            }
        }];
    }
    return c;
}

- (UIImage *)rounded:(UIImage *)img {
    CGSize sz = CGSizeMake(40, 40);
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, sz.width, sz.height) cornerRadius:20] addClip];
    [img drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: img;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSArray *list = self.activeList;
    if (ip.row >= (NSInteger)list.count) return;
    NSDictionary *e = list[ip.row];
    void (^pick)(NSDictionary *) = self.onPick;
    [self.searchBar resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:^{ if (pick) pick(e); }];
}

@end
