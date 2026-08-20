#import "RYGWordmarkViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../UI/RYGIcon.h"
#import "../Utils.h"
#import <objc/runtime.h>
#include <string.h>

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
    RYGRuntimeArgumentKind argument = RYGWordmarkArgumentKind(method);
    return type && *type == 'B'
        && argument >= RYGRuntimeArgumentNone
        && argument <= RYGRuntimeArgumentInteger;
}

static BOOL RYGWordmarkContains(NSString *value, NSString *needle) {
    return value.length && needle.length &&
        [value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSArray<NSString *> *RYGWordmarkPrimaryImages(void) {
    NSArray<NSString *> *images = RYGRuntimeBrowserEngine.runtimeImagePaths;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    NSString *main = NSBundle.mainBundle.executablePath;
    for (NSString *path in images) {
        if ([path isEqualToString:main] ||
            [path.stringByResolvingSymlinksInPath isEqualToString:main.stringByResolvingSymlinksInPath]) {
            [selected addObject:path];
            break;
        }
    }
    for (NSString *path in images) {
        if (RYGWordmarkContains(path.lastPathComponent, @"FBShared")) [selected addObject:path];
    }
    return selected.array;
}

static const char **RYGWordmarkCopyClassNames(NSString *imagePath, unsigned int *count) {
    if (count) *count = 0;
    const char **names = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, count);
    if (names) return names;
    NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
    if (![resolved isEqualToString:imagePath])
        return objc_copyClassNamesForImage(resolved.fileSystemRepresentation, count);
    return NULL;
}

static NSDictionary<NSString *, RYGRuntimeBoolMethod *> *RYGWordmarkScan(void) {
    NSMutableSet<NSString *> *wantedSelectors = [NSMutableSet set];
    for (NSDictionary *variant in RYGWordmarkVariants()) [wantedSelectors addObject:variant[@"selector"]];

    NSMutableDictionary<NSString *, RYGRuntimeBoolMethod *> *found = [NSMutableDictionary dictionary];
    for (NSString *imagePath in RYGWordmarkPrimaryImages()) {
        unsigned int classCount = 0;
        const char **classNames = RYGWordmarkCopyClassNames(imagePath, &classCount);
        if (!classNames) continue;

        for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
            const char *rawClassName = classNames[classIndex];
            if (!rawClassName || !*rawClassName) continue;
            Class cls = objc_lookUpClass(rawClassName);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:rawClassName];

            for (NSUInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    if (!RYGWordmarkBoolMethod(method)) continue;
                    SEL selector = method_getName(method);
                    if (!selector) continue;
                    NSString *selectorName = NSStringFromSelector(selector);
                    if (![wantedSelectors containsObject:selectorName] || found[selectorName]) continue;

                    RYGRuntimeBoolMethod *runtimeMethod = [RYGRuntimeBoolMethod new];
                    runtimeMethod.imagePath = imagePath;
                    runtimeMethod.className = className ?: @"";
                    runtimeMethod.selectorName = selectorName;
                    runtimeMethod.classMethod = classMethod;
                    runtimeMethod.argumentKind = RYGWordmarkArgumentKind(method);
                    const char *types = method_getTypeEncoding(method);
                    runtimeMethod.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                    found[selectorName] = runtimeMethod;
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }
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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(nativeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self refreshRuntime];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)nativeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *method in self.methodsBySelector.allValues) {
        if ([method.overrideKey isEqualToString:key]) { [self rebuildGrid]; return; }
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
            if (methods.count) RYGRuntimeBeginLiveObservation(methods.allValues);
        });
    });
}

- (UIMenu *)menuForMethod:(RYGRuntimeBoolMethod *)method {
    if (!method) return nil;
    __weak typeof(self) weakSelf = self;

    UIAction *observe = [UIAction actionWithTitle:@"Observe Native"
                                            image:[UIImage systemImageNamed:@"waveform.path.ecg"]
                                       identifier:nil
                                          handler:^(__unused UIAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
    }];

    NSNumber *forced = method.overrideValue;
    UIAction *nativeAction = [UIAction actionWithTitle:@"Native"
                                                image:nil
                                           identifier:nil
                                              handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
        [weakSelf rebuildGrid];
    }];
    nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;

    UIAction *forceOn = [UIAction actionWithTitle:@"Force On"
                                            image:nil
                                       identifier:nil
                                          handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        [weakSelf rebuildGrid];
    }];
    forceOn.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *forceOff = [UIAction actionWithTitle:@"Force Off"
                                             image:nil
                                        identifier:nil
                                           handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        [weakSelf rebuildGrid];
    }];
    forceOff.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIMenu *output = [UIMenu menuWithTitle:@"Output"
                                     image:nil
                                identifier:nil
                                   options:UIMenuOptionsSingleSelection | UIMenuOptionsDisplayInline
                                  children:@[nativeAction, forceOn, forceOff]];
    return [UIMenu menuWithTitle:method.selectorName ?: @"IGWordMark"
                           image:nil
                      identifier:nil
                         options:0
                        children:@[observe, output]];
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
            button.enabled = method != nil;
            if (method) {
                button.menu = [self menuForMethod:method];
                button.showsMenuAsPrimaryAction = YES;
                button.changesSelectionAsPrimaryAction = NO;
            }
            // The menu must exist before configuring Glass so UIKit uses its
            // default menu-source metrics and owns the closed→expanded morph.
            RYGLiquidGlassConfigureButton(button, NO);

            UIStackView *content = [UIStackView new];
            content.userInteractionEnabled = NO;
            content.translatesAutoresizingMaskIntoConstraints = NO;
            content.axis = UILayoutConstraintAxisVertical;
            content.spacing = 8.0;
            content.alignment = UIStackViewAlignmentCenter;
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
            [rowStack addArrangedSubview:button];
        }
    }
}

@end
