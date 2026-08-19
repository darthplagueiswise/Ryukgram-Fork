#import "RYGWordmarkViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../UI/RYGIcon.h"
#import "../Utils.h"
#import <objc/runtime.h>
#include <string.h>

static const void *kRYGWordmarkMethodKey = &kRYGWordmarkMethodKey;

static NSArray<NSDictionary<NSString *, NSString *> *> *RYGWordmarkVariants(void) {
    static NSArray *variants;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        variants = @[
            @{@"title":@"1A", @"asset":@"instagram-wordmark-1a", @"selector":@"isIGWordmark1aEnabled"},
            @{@"title":@"1A Alt", @"asset":@"instagram-wordmark-1a-alt", @"selector":@"isIGWordmark1aAltEnabled"},
            @{@"title":@"1B", @"asset":@"instagram-wordmark-1b", @"selector":@"isIGWordmark1bEnabled"},
            @{@"title":@"1B Alt", @"asset":@"instagram-wordmark-1b-alt", @"selector":@"isIGWordmark1bAltEnabled"},
        ];
    });
    return variants;
}

static const char *RYGWordmarkSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGWordmarkArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGWordmarkSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGWordmarkBoolMethod(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGWordmarkSkipQualifiers(encoded);
    return type && *type == 'B' && RYGWordmarkArgumentKind(method) >= 0;
}

static NSDictionary<NSString *, RYGRuntimeBoolMethod *> *RYGWordmarkScan(void) {
    NSMutableSet<NSString *> *selectors = [NSMutableSet set];
    for (NSDictionary *variant in RYGWordmarkVariants()) [selectors addObject:variant[@"selector"]];

    NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableSet<NSString *> *wantedImages = [NSMutableSet set];
    if (main.length) [wantedImages addObject:main];
    for (NSString *path in images) {
        if ([path.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [wantedImages addObject:path.stringByStandardizingPath];
        }
    }

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return @{};
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        const char *rawImage = class_getImageName(cls);
        if (!rawImage) continue;
        NSString *imagePath = [[NSString stringWithUTF8String:rawImage] stringByStandardizingPath];
        if (![wantedImages containsObject:imagePath]) continue;
        NSString *className = NSStringFromClass(cls);
        if (!className.length) continue;

        for (NSInteger pass = 0; pass < 2; pass++) {
            BOOL classMethod = pass == 1;
            Class owner = classMethod ? object_getClass(cls) : cls;
            if (!owner) continue;
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(owner, &methodCount);
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                Method method = methods[methodIndex];
                SEL selector = method_getName(method);
                if (!selector || !RYGWordmarkBoolMethod(method)) continue;
                NSString *selectorName = NSStringFromSelector(selector);
                if (![selectors containsObject:selectorName] || found[selectorName]) continue;
                RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                row.imagePath = imagePath;
                row.className = className;
                row.selectorName = selectorName;
                row.classMethod = classMethod;
                row.argumentKind = RYGWordmarkArgumentKind(method);
                const char *types = method_getTypeEncoding(method);
                row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                found[selectorName] = row;
            }
            if (methods) free(methods);
        }
    }
    free(classes);
    return found.copy;
}

@interface RYGWordmarkViewController ()
@property (nonatomic, strong) UIStackView *grid;
@property (nonatomic, copy) NSDictionary<NSString *, RYGRuntimeBoolMethod *> *methodsBySelector;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RYGWordmarkViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IGWordMark";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];

    self.grid = [UIStackView new];
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    self.grid.axis = UILayoutConstraintAxisVertical;
    self.grid.spacing = 12.0;
    self.grid.distribution = UIStackViewDistributionFillEqually;
    [self.view addSubview:self.grid];

    [NSLayoutConstraint activateConstraints:@[
        [self.grid.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16.0],
        [self.grid.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0],
        [self.grid.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16.0],
        [self.grid.heightAnchor constraintEqualToAnchor:self.grid.widthAnchor multiplier:0.86],
    ]];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithCustomView:self.spinner];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(nativeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self refreshRuntime];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)nativeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *method in self.methodsBySelector.allValues) {
        if ([method.overrideKey isEqualToString:key]) {
            [self rebuildGrid];
            return;
        }
    }
}

- (void)refreshRuntime {
    NSUInteger generation = ++self.generation;
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *methods = RYGWordmarkScan();
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.methodsBySelector = methods;
            [self.spinner stopAnimating];
            [self rebuildGrid];
        });
    });
}

- (void)rebuildGrid {
    for (UIView *view in self.grid.arrangedSubviews.copy) {
        [self.grid removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSArray *variants = RYGWordmarkVariants();
    for (NSInteger rowIndex = 0; rowIndex < 2; rowIndex++) {
        UIStackView *rowStack = [UIStackView new];
        rowStack.axis = UILayoutConstraintAxisHorizontal;
        rowStack.spacing = 12.0;
        rowStack.distribution = UIStackViewDistributionFillEqually;
        [self.grid addArrangedSubview:rowStack];

        for (NSInteger column = 0; column < 2; column++) {
            NSDictionary *variant = variants[(NSUInteger)(rowIndex * 2 + column)];
            RYGRuntimeBoolMethod *method = self.methodsBySelector[variant[@"selector"]];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
            button.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
            button.accessibilityLabel = [NSString stringWithFormat:@"IGWordMark %@", variant[@"title"]];
            objc_setAssociatedObject(button, kRYGWordmarkMethodKey, method, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [button addTarget:self action:@selector(wordmarkTapped:) forControlEvents:UIControlEventTouchUpInside];
            RYGLiquidGlassConfigureButton(button, NO);

            UIStackView *content = [UIStackView new];
            content.userInteractionEnabled = NO;
            content.translatesAutoresizingMaskIntoConstraints = NO;
            content.axis = UILayoutConstraintAxisVertical;
            content.spacing = 8.0;
            content.alignment = UIStackViewAlignmentCenter;
            content.distribution = UIStackViewDistributionFill;
            [button addSubview:content];

            UIImageView *imageView = [[UIImageView alloc] initWithImage:[RYGIcon fbImageNamed:variant[@"asset"]]];
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            imageView.tintColor = UIColor.labelColor;
            [content addArrangedSubview:imageView];
            [imageView.heightAnchor constraintGreaterThanOrEqualToConstant:56.0].active = YES;

            UILabel *title = [UILabel new];
            title.text = variant[@"title"];
            title.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
            title.textColor = UIColor.labelColor;
            [content addArrangedSubview:title];

            UILabel *state = [UILabel new];
            state.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
            state.textColor = UIColor.secondaryLabelColor;
            if (!method) state.text = @"Unavailable";
            else if (method.overrideValue) state.text = method.overrideValue.boolValue ? @"Forced On" : @"Forced Off";
            else if (method.liveValue) state.text = method.liveValue.boolValue ? @"Native On" : @"Native Off";
            else state.text = @"Native";
            [content addArrangedSubview:state];

            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:12.0],
                [content.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-12.0],
                [content.topAnchor constraintEqualToAnchor:button.topAnchor constant:14.0],
                [content.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-14.0],
            ]];
            button.enabled = method != nil;
            [rowStack addArrangedSubview:button];
        }
    }
}

- (void)wordmarkTapped:(UIButton *)button {
    RYGRuntimeBoolMethod *method = objc_getAssociatedObject(button, kRYGWordmarkMethodKey);
    if (!method) return;
    NSString *variantTitle = button.accessibilityLabel ?: @"IGWordMark";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:variantTitle
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe Native" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force On" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf rebuildGrid];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force Off" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf rebuildGrid];
    }]];
    if (method.overrideValue) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf rebuildGrid];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = button;
        sheet.popoverPresentationController.sourceRect = button.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end