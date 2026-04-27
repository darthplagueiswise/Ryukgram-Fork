#import "SCIResolverReportViewController.h"
#import "SCIResolverScanner.h"

@interface SCIResolverReportViewController ()
@property (nonatomic) SCIResolverReportKind kind;
@property (nonatomic, copy) NSString *reportTitle;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation SCIResolverReportViewController

- (instancetype)initWithKind:(SCIResolverReportKind)kind title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _kind = kind;
        _reportTitle = [title copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO;
    textView.selectable = YES;
    textView.alwaysBounceVertical = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    textView.text = @"Running resolver scan...\n\nThis is view-only: no hooks, no overrides, no alloc/init, no entrypoint invocation.";
    [self.view addSubview:textView];
    self.textView = textView;

    [self runReport];
}

- (void)runReport {
    SCIResolverReportKind kind = self.kind;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *report = @"";
        if (kind == SCIResolverReportKindDogfoodDeveloper) {
            report = [SCIResolverScanner runDogfoodDeveloperReport];
        } else if (kind == SCIResolverReportKindMobileConfigSymbols) {
            report = [SCIResolverScanner runMobileConfigSymbolReport];
        } else {
            report = [SCIResolverScanner runFullResolverReport];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.textView.text = report ?: @"(empty report)";
        });
    });
}

@end
