#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../RYGChrome.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Password-locked reels use IGMediaOverlayProfileWithPasswordView as a blur overlay.
// The password is stored in the _asnwer ivar (IG typo). We read it at runtime,
// then provide buttons to auto-fill + submit or reveal + copy the password.

#define RYG_PW_BTN_TAG 1342

static NSString * _Nullable rygGetPassword(id overlayView) {
    Class cls = [overlayView class];
    while (cls && cls != [UIView class]) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *name = ivar_getName(ivars[i]);
            if (name && strcmp(name, "_asnwer") == 0) {
                id value = object_getIvar(overlayView, ivars[i]);
                free(ivars);
                if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0)
                    return (NSString *)value;
                return nil;
            }
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }

    // Fallback: scan for any password-related string ivar
    cls = [overlayView class];
    while (cls && cls != [UIView class]) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            @try {
                id value = object_getIvar(overlayView, ivars[i]);
                if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) continue;
                const char *name = ivar_getName(ivars[i]);
                if (!name) continue;
                NSString *lower = [[NSString stringWithUTF8String:name] lowercaseString];
                if ([lower containsString:@"answer"] || [lower containsString:@"asnwer"] ||
                    [lower containsString:@"password"] || [lower containsString:@"secret"]) {
                    free(ivars);
                    return (NSString *)value;
                }
            } @catch(id e) {}
        }
        if (ivars) free(ivars);
        cls = class_getSuperclass(cls);
    }
    return nil;
}

static UITextField * _Nullable rygFindTextField(UIView *root) {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:[UITextField class]]) return (UITextField *)v;
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return nil;
}

static UIView * _Nullable rygFindSubmitButton(UIView *root) {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass([v class]) containsString:@"IGDSMediaTextButton"]) return v;
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return nil;
}

%hook IGMediaOverlayProfileWithPasswordView

- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;
    if (![RYGUtils getBoolPref:@"unlock_password_reels"]) return;
    [self rygAddButtons];
}

- (void)layoutSubviews {
    %orig;
    if (![RYGUtils getBoolPref:@"unlock_password_reels"]) return;
    [self rygAddButtons];
}

%new - (void)rygAddButtons {
    if ([self viewWithTag:RYG_PW_BTN_TAG]) return;

    RYGChromeButton *unlockBtn = [[RYGChromeButton alloc] initWithSymbol:@"lock.open.fill" pointSize:18.0 diameter:40.0];
    unlockBtn.tag = RYG_PW_BTN_TAG;
    unlockBtn.iconTint = [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0];
    unlockBtn.bubbleColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    unlockBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [unlockBtn addTarget:self action:@selector(rygUnlockTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:unlockBtn];

    RYGChromeButton *eyeBtn = [[RYGChromeButton alloc] initWithSymbol:@"eye.fill" pointSize:18.0 diameter:40.0];
    eyeBtn.tag = RYG_PW_BTN_TAG + 1;
    eyeBtn.iconTint = [UIColor whiteColor];
    eyeBtn.bubbleColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    eyeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [eyeBtn addTarget:self action:@selector(rygShowPasswordTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:eyeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [unlockBtn.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:200],
        [unlockBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [unlockBtn.widthAnchor constraintEqualToConstant:40],
        [unlockBtn.heightAnchor constraintEqualToConstant:40],

        [eyeBtn.topAnchor constraintEqualToAnchor:unlockBtn.bottomAnchor constant:12],
        [eyeBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [eyeBtn.widthAnchor constraintEqualToConstant:40],
        [eyeBtn.heightAnchor constraintEqualToConstant:40],
    ]];
}

%new - (void)rygUnlockTapped {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    NSString *password = rygGetPassword(self);
    if (!password) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No password found")];
        return;
    }

    UITextField *textField = rygFindTextField(self);
    if (!textField) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No text field found")];
        return;
    }

    textField.text = password;
    [textField sendActionsForControlEvents:UIControlEventEditingChanged];
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:textField];

    if (textField.delegate) {
        if ([textField.delegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)])
            [textField.delegate textField:textField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:password];
        if ([textField.delegate respondsToSelector:@selector(textFieldDidChangeSelection:)])
            [textField.delegate textFieldDidChangeSelection:textField];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *submitBtn = rygFindSubmitButton(self);
        if (submitBtn && [submitBtn isKindOfClass:[UIControl class]]) {
            [(UIControl *)submitBtn setHidden:NO];
            [(UIControl *)submitBtn sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
    });
}

%new - (void)rygShowPasswordTapped {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    NSString *password = rygGetPassword(self);
    if (!password) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No password found")];
        return;
    }

    [[UIPasteboard generalPasteboard] setString:password];
    RYGNotifySuccess(RYG_NOTIF_COPY_PASSWORD,
                     [NSString stringWithFormat:RYGLocalized(@"Copied %@"), password],
                     nil);
}

%end
