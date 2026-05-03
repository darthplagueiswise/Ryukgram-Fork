#import "SCIExperimentRuntimeBrowserViewController.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface SCIRuntimeMethodEntry : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *methodName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) BOOL returnsBool;
@property (nonatomic, assign) unsigned int argCount;
@end
@implementation SCIRuntimeMethodEntry
@end

@interface SCIRuntimeClassEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray<SCIRuntimeMethodEntry *> *methods;
@property (nonatomic, strong) NSArray<NSString *> *properties;
@property (nonatomic, strong) NSArray<NSString *> *ivars;
@end
@implementation SCIRuntimeClassEntry
@end

typedef NS_ENUM(NSInteger, SCIRuntimeBrowserTab) {
    SCIRuntimeBrowserTabClasses = 0,
    SCIRuntimeBrowserTabBoolMethods,
    SCIRuntimeBrowserTabEnabled,
};

@interface SCIExperimentRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) SCIRuntimeBrowserTab tab;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<SCIRuntimeClassEntry *> *classes;
@property (nonatomic, strong) NSArray<SCIRuntimeMethodEntry *> *boolMethods;
@property (nonatomic, strong) NSArray<SCIRuntimeMethodEntry *> *enabledMethods;
@end

@implementation SCIExperimentRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime experiments";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.tab = SCIRuntimeBrowserTabClasses;

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Classes", @"BOOL", @"Enabled"]];
    self.segmentedControl.selectedSegmentIndex = self.tab;
    [self.segmentedControl addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.segmentedControl];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search experiment / enabled / class / method";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleSubtitle];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.segmentedControl.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
    ]];

    [self.spinner startAnimating];
    self.emptyLabel.text = @"Scanning Objective-C runtime…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self scanRuntime];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            [self.tableView reloadData];
            [self updateEmpty];
        });
    });
}

- (void)segChanged {
    self.tab = (SCIRuntimeBrowserTab)self.segmentedControl.selectedSegmentIndex;
    [self.tableView reloadData];
    [self updateEmpty];
}

- (BOOL)stringLooksInteresting:(NSString *)s {
    if (!s.length) return NO;
    NSString *l = s.lowercaseString;
    return [l containsString:@"experiment"] || [l containsString:@"enabled"] || [l containsString:@"isenabled"] || [l containsString:@"shouldenable"] || [l containsString:@"shouldshow"] || [l containsString:@"eligib"] || [l containsString:@"launcher"] || [l containsString:@"dogfood"] || [l containsString:@"internal"];
}

- (BOOL)methodReturnsBool:(Method)m {
    char rt[64] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c';
}

- (NSArray<SCIRuntimeMethodEntry *> *)methodEntriesForClass:(Class)cls meta:(BOOL)meta className:(NSString *)className {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Method m = methods[i];
        SEL sel = method_getName(m);
        NSString *name = NSStringFromSelector(sel);
        if (![self stringLooksInteresting:name]) continue;
        SCIRuntimeMethodEntry *e = [SCIRuntimeMethodEntry new];
        e.className = className;
        e.methodName = name;
        e.classMethod = meta;
        e.returnsBool = [self methodReturnsBool:m];
        e.argCount = method_getNumberOfArguments(m);
        const char *types = method_getTypeEncoding(m);
        e.typeEncoding = types ? @(types) : @"";
        [out addObject:e];
    }
    if (methods) free(methods);
    return out;
}

- (NSArray<NSString *> *)propertyNamesForClass:(Class)cls {
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(cls, &count);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *n = property_getName(props[i]);
        NSString *s = n ? @(n) : @"";
        if ([self stringLooksInteresting:s]) [out addObject:s];
    }
    if (props) free(props);
    return [out sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (NSArray<NSString *> *)ivarNamesForClass:(Class)cls {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *n = ivar_getName(ivars[i]);
        NSString *s = n ? @(n) : @"";
        if ([self stringLooksInteresting:s]) [out addObject:s];
    }
    if (ivars) free(ivars);
    return [out sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (void)scanRuntime {
    unsigned int n = 0;
    Class *all = objc_copyClassList(&n);
    NSMutableArray<SCIRuntimeClassEntry *> *classes = [NSMutableArray array];
    NSMutableArray<SCIRuntimeMethodEntry *> *boolMethods = [NSMutableArray array];
    NSMutableArray<SCIRuntimeMethodEntry *> *enabledMethods = [NSMutableArray array];

    for (unsigned int i = 0; i < n; i++) {
        Class cls = all[i];
        NSString *className = NSStringFromClass(cls);
        if (!className.length) continue;

        NSArray *inst = [self methodEntriesForClass:cls meta:NO className:className];
        NSArray *meta = [self methodEntriesForClass:cls meta:YES className:className];
        NSArray *props = [self propertyNamesForClass:cls];
        NSArray *ivars = [self ivarNamesForClass:cls];
        NSMutableArray *methods = [NSMutableArray array];
        [methods addObjectsFromArray:inst];
        [methods addObjectsFromArray:meta];

        BOOL classInteresting = [self stringLooksInteresting:className] || methods.count || props.count || ivars.count;
        if (!classInteresting) continue;

        SCIRuntimeClassEntry *ce = [SCIRuntimeClassEntry new];
        ce.name = className;
        ce.methods = [methods sortedArrayUsingComparator:^NSComparisonResult(SCIRuntimeMethodEntry *a, SCIRuntimeMethodEntry *b) {
            return [a.methodName caseInsensitiveCompare:b.methodName];
        }];
        ce.properties = props;
        ce.ivars = ivars;
        [classes addObject:ce];

        for (SCIRuntimeMethodEntry *m in methods) {
            if (m.returnsBool) [boolMethods addObject:m];
            NSString *l = m.methodName.lowercaseString;
            if ([l containsString:@"enabled"] || [l containsString:@"isenabled"] || [l containsString:@"shouldenable"]) [enabledMethods addObject:m];
        }
    }
    if (all) free(all);

    NSComparator methodSort = ^NSComparisonResult(SCIRuntimeMethodEntry *a, SCIRuntimeMethodEntry *b) {
        NSComparisonResult c = [a.className caseInsensitiveCompare:b.className];
        if (c != NSOrderedSame) return c;
        return [a.methodName caseInsensitiveCompare:b.methodName];
    };
    self.classes = [classes sortedArrayUsingComparator:^NSComparisonResult(SCIRuntimeClassEntry *a, SCIRuntimeClassEntry *b) {
        return [a.name caseInsensitiveCompare:b.name];
    }];
    self.boolMethods = [boolMethods sortedArrayUsingComparator:methodSort];
    self.enabledMethods = [enabledMethods sortedArrayUsingComparator:methodSort];
}

- (NSArray *)baseRows {
    switch (self.tab) {
        case SCIRuntimeBrowserTabClasses: return self.classes ?: @[];
        case SCIRuntimeBrowserTabBoolMethods: return self.boolMethods ?: @[];
        case SCIRuntimeBrowserTabEnabled: return self.enabledMethods ?: @[];
    }
}

- (NSArray *)filteredRows {
    NSArray *base = [self baseRows];
    if (!self.query.length) return base;
    NSString *q = self.query.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (id row in base) {
        NSString *hay = nil;
        if ([row isKindOfClass:SCIRuntimeClassEntry.class]) {
            SCIRuntimeClassEntry *c = row;
            hay = [NSString stringWithFormat:@"%@ %@ %@", c.name, [c.properties componentsJoinedByString:@" "], [c.ivars componentsJoinedByString:@" "]];
        } else {
            SCIRuntimeMethodEntry *m = row;
            hay = [NSString stringWithFormat:@"%@ %@ %@", m.className, m.methodName, m.typeEncoding];
        }
        if ([hay.lowercaseString containsString:q]) [out addObject:row];
    }
    return out;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self filteredRows].count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    id row = [self filteredRows][ip.row];
    if ([row isKindOfClass:SCIRuntimeClassEntry.class]) {
        SCIRuntimeClassEntry *c = row;
        cell.textLabel.text = c.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"methods=%lu · props=%lu · ivars=%lu", (unsigned long)c.methods.count, (unsigned long)c.properties.count, (unsigned long)c.ivars.count];
    } else {
        SCIRuntimeMethodEntry *m = row;
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", m.classMethod ? @"+" : @"-", m.methodName];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · args=%u · %@", m.className, m.argCount, m.typeEncoding ?: @""];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    id row = [self filteredRows][ip.row];
    if ([row isKindOfClass:SCIRuntimeClassEntry.class]) [self presentClassEntry:row fromCell:cell];
    else [self presentMethodEntry:row fromCell:cell];
}

- (void)presentClassEntry:(SCIRuntimeClassEntry *)entry fromCell:(UITableViewCell *)cell {
    NSMutableString *msg = [NSMutableString string];
    if (entry.properties.count) [msg appendFormat:@"Properties:\n%@\n\n", [entry.properties componentsJoinedByString:@"\n"]];
    if (entry.ivars.count) [msg appendFormat:@"Ivars:\n%@\n\n", [entry.ivars componentsJoinedByString:@"\n"]];
    if (entry.methods.count) {
        [msg appendString:@"Methods:\n"];
        NSUInteger max = MIN(entry.methods.count, 80);
        for (NSUInteger i = 0; i < max; i++) {
            SCIRuntimeMethodEntry *m = entry.methods[i];
            [msg appendFormat:@"%@ %@\n", m.classMethod ? @"+" : @"-", m.methodName];
        }
        if (entry.methods.count > max) [msg appendFormat:@"… +%lu more", (unsigned long)(entry.methods.count - max)];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry.name message:msg.length ? msg : @"No focused members." preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy class name" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.name; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy summary" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = msg; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)presentMethodEntry:(SCIRuntimeMethodEntry *)entry fromCell:(UITableViewCell *)cell {
    NSString *title = [NSString stringWithFormat:@"%@ %@", entry.classMethod ? @"+" : @"-", entry.methodName];
    NSString *msg = [NSString stringWithFormat:@"%@\nargs=%u\n%@", entry.className, entry.argCount, entry.typeEncoding ?: @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy selector" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.methodName; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy class.method" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@", entry.className, entry.methodName]; }]];

    if (entry.classMethod && entry.returnsBool && entry.argCount == 2) {
        [a addAction:[UIAlertAction actionWithTitle:@"Call BOOL getter" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
            Class cls = NSClassFromString(entry.className);
            SEL sel = NSSelectorFromString(entry.methodName);
            if (!cls || ![cls respondsToSelector:sel]) { [SCIUtils showErrorHUDWithDescription:@"Selector missing"]; return; }
            BOOL value = ((BOOL (*)(Class, SEL))objc_msgSend)(cls, sel);
            [SCIUtils showToastForDuration:2.0 title:[NSString stringWithFormat:@"%@", value ? @"YES" : @"NO"] subtitle:entry.methodName];
        }]];
    }

    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self.tableView reloadData]; [self updateEmpty]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (void)updateEmpty {
    NSInteger rows = [self tableView:self.tableView numberOfRowsInSection:0];
    self.emptyLabel.hidden = rows > 0 || self.spinner.isAnimating;
    if (!self.emptyLabel.hidden) self.emptyLabel.text = self.query.length ? @"No match." : @"Empty.";
}

@end
