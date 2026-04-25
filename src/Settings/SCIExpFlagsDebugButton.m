#import "SCIExpFlagsViewController.h"
#import "SCIMobileConfigSymbolObserverViewController.h"
#import "../Features/ExpFlags/SCIExpMobileConfigDebug.h"
#import "../Features/ExpFlags/SCIExpMobileConfigMapping.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface SCIMCDebugViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@end

@implementation SCIMCDebugViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Debug";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Reload" style:UIBarButtonItemStylePlain target:self action:@selector(reloadTapped)],
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyTapped)]
    ];

    self.textView = [UITextView new];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.backgroundColor = UIColor.systemBackgroundColor;
    self.textView.textColor = UIColor.labelColor;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 24, 12);
    [self.view addSubview:self.textView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    ]];

    [self reloadTapped];
}

- (NSString *)buildDebugText {
    NSString *state = [SCIExpMobileConfigDebug runDebugDumps] ?: @"nil";
    NSString *mapping = [SCIExpMobileConfigMapping mappingSourceDescription] ?: @"none";
    return [NSString stringWithFormat:@"%@\n\nMapping: %@", state, mapping];
}

- (void)reloadTapped {
    [SCIExpMobileConfigMapping reloadMapping];
    self.textView.text = [self buildDebugText];
    [self.textView setContentOffset:CGPointZero animated:NO];
}

- (void)copyTapped {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation SCIExpFlagsViewController (MCDebugButton)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = self;
        SEL originalSEL = @selector(viewDidLoad);
        SEL swizzledSEL = @selector(sci_mcdebug_viewDidLoad);
        Method original = class_getInstanceMethod(cls, originalSEL);
        Method swizzled = class_getInstanceMethod(cls, swizzledSEL);
        if (!original || !swizzled) return;
        method_exchangeImplementations(original, swizzled);
    });
}

- (void)sci_mcdebug_viewDidLoad {
    [self sci_mcdebug_viewDidLoad];

    UIBarButtonItem *debug = [[UIBarButtonItem alloc]
        initWithTitle:@"MC Debug"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(sci_mcdebug_presentState)];

    UIBarButtonItem *symbols = [[UIBarButtonItem alloc]
        initWithTitle:@"MC Symbols"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(sci_mcdebug_pushSymbols)];

    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray arrayWithObjects:debug, symbols, nil];
    if (self.navigationItem.rightBarButtonItems.count) {
        [items addObjectsFromArray:self.navigationItem.rightBarButtonItems];
    } else if (self.navigationItem.rightBarButtonItem) {
        [items addObject:self.navigationItem.rightBarButtonItem];
    }
    self.navigationItem.rightBarButtonItems = items;
}

- (void)sci_mcdebug_presentState {
    SCIMCDebugViewController *vc = [SCIMCDebugViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)sci_mcdebug_pushSymbols {
    [self.navigationController pushViewController:[SCIMobileConfigSymbolObserverViewController new] animated:YES];
}

@end
