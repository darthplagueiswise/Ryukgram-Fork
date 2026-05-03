#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "SCIDogfoodingMainLauncher.h"

static const NSInteger RYDogSelectorButtonTag = 0xD06F091;
static void (*origRYDogSelectorExpDidAppear)(id self, SEL _cmd, BOOL animated);

@interface NSObject (RYDogSelectorButtonAction)
- (void)ryDogSelectorButtonTapped:(id)sender;
@end

@implementation NSObject (RYDogSelectorButtonAction)
- (void)ryDogSelectorButtonTapped:(id)sender {
    UIViewController *vc = [self isKindOfClass:UIViewController.class] ? (UIViewController *)self : nil;
    RYDogOpenMainFrom(vc);
}
@end

static UIButton *RYDogSelectorMakeButton(UIViewController *target) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = RYDogSelectorButtonTag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 18.0;
    button.clipsToBounds = YES;
    button.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.90];
    [button setTitle:@"Call Dogfood Selector" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [button addTarget:target action:@selector(ryDogSelectorButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static void RYDogSelectorAttachButton(UIViewController *vc) {
    if (!vc || !vc.view) return;
    if ([vc.view viewWithTag:RYDogSelectorButtonTag]) return;

    UIButton *button = RYDogSelectorMakeButton(vc);
    [vc.view addSubview:button];

    UILayoutGuide *guide = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [button.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-58.0],
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:176.0],
        [button.heightAnchor constraintEqualToConstant:36.0]
    ]];
}

static void hookRYDogSelectorExpDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origRYDogSelectorExpDidAppear) origRYDogSelectorExpDidAppear(self, _cmd, animated);
    if ([self isKindOfClass:UIViewController.class]) {
        RYDogSelectorAttachButton((UIViewController *)self);
    }
}

__attribute__((constructor))
static void RYDogSelectorButtonInit(void) {
    @autoreleasepool {
        Class expCls = NSClassFromString(@"SCIExpFlagsViewController");
        if (expCls && class_getInstanceMethod(expCls, @selector(viewDidAppear:))) {
            MSHookMessageEx(expCls,
                            @selector(viewDidAppear:),
                            (IMP)hookRYDogSelectorExpDidAppear,
                            (IMP *)&origRYDogSelectorExpDidAppear);
        }
        NSLog(@"[RyukGram][Dogfood] selector caller button loaded");
    }
}
