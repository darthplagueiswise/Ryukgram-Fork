#import "SCIExpFlagsViewController.h"
#import "../Features/ExpFlags/SCIExpMobileConfigDebug.h"
#import "../Features/ExpFlags/SCIExpMobileConfigMapping.h"
#import <objc/runtime.h>

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

    UIBarButtonItem *existing = self.navigationItem.leftBarButtonItem;
    if (existing) self.navigationItem.leftBarButtonItems = @[debug, existing];
    else self.navigationItem.leftBarButtonItem = debug;
}

- (void)sci_mcdebug_presentState {
    NSString *state = [SCIExpMobileConfigDebug runDebugDumps] ?: @"nil";
    NSString *mapping = [SCIExpMobileConfigMapping mappingSourceDescription] ?: @"none";
    NSString *message = [NSString stringWithFormat:@"%@\n\nMapping: %@", state, mapping];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MobileConfig Debug State"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = message;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reload mapping" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [SCIExpMobileConfigMapping reloadMapping];
        NSString *newMessage = [NSString stringWithFormat:@"%@\n\nMapping: %@",
                                [SCIExpMobileConfigDebug debugState] ?: @"nil",
                                [SCIExpMobileConfigMapping mappingSourceDescription] ?: @"none"];
        [UIPasteboard generalPasteboard].string = newMessage;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

@end
