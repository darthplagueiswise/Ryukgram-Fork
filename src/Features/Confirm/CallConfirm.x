#import "../../Utils.h"
#import "../../CallButtonHelpers.h"

// Old dual-button accounts chain tap methods (_didTapAudioButton ->
// _didTapButtonWithCallType:); guard against the nested hook confirming twice.
static BOOL rygCallConfirmProceeding = NO;

%hook IGDirectThreadCallButtonsCoordinator
// Newer A/B: call button opens an IGDSMenu; drop the hidden type's entry and
// wrap the survivor's handler with a confirmation.
- (id)buttonMenuItems {
    NSArray *items = %orig;
    if (![items isKindOfClass:[NSArray class]]) return items;

    BOOL hideV = [RYGUtils getBoolPref:@"hide_video_call_button"];
    BOOL hideA = [RYGUtils getBoolPref:@"hide_voice_call_button"];
    BOOL confV = [RYGUtils getBoolPref:@"video_call_confirm"];
    BOOL confA = [RYGUtils getBoolPref:@"voice_call_confirm"];
    if (!hideV && !hideA && !confV && !confA) return items;

    Class itemCls = NSClassFromString(@"IGDSMenuItem");
    NSUInteger count = items.count;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        id item = items[i];
        BOOL isVideo = rygCallMenuTypeIsVideo(item, i, count);
        if (isVideo ? hideV : hideA) continue;

        NSString *key = isVideo ? @"video_call_confirm" : @"voice_call_confirm";
        Ivar hv = class_getInstanceVariable([item class], "_handler");
        if (!itemCls || !hv || ![RYGUtils getBoolPref:key]) { [out addObject:item]; continue; }

        void (^orig)(void) = object_getIvar(item, hv);
        Ivar iv = class_getInstanceVariable([item class], "_image");
        UIImage *img = iv ? object_getIvar(item, iv) : nil;
        NSString *title = [item respondsToSelector:@selector(title)] ? [item title] : nil;
        NSString *ctitle = RYGLocalized(isVideo ? @"Confirm video call" : @"Confirm voice call");
        void (^wrapped)(void) = ^{ [RYGUtils showConfirmation:^(void) {
            rygCallConfirmProceeding = YES;
            if (orig) orig();
            rygCallConfirmProceeding = NO;
        } title:ctitle]; };

        typedef id (*Init)(id, SEL, id, id, id);
        id newItem = ((Init)objc_msgSend)([itemCls alloc], @selector(initWithTitle:image:handler:),
                                          title, img, wrapped);
        [out addObject:(newItem ?: item)];
    }
    return out;
}

// Standalone joint-button variants route here instead of through the menu.
- (void)_didTapButtonWithCallType:(long long)type {
    BOOL resolved = NO;
    BOOL isVideo = rygCallTypeIsVideo(self, type, &resolved);
    NSString *key = isVideo ? @"video_call_confirm" : @"voice_call_confirm";
    if (!rygCallConfirmProceeding && [RYGUtils getBoolPref:key]) {
        [RYGUtils showConfirmation:^(void) {
            rygCallConfirmProceeding = YES; %orig; rygCallConfirmProceeding = NO;
        } title:RYGLocalized(isVideo ? @"Confirm video call" : @"Confirm voice call")];
    } else {
        return %orig;
    }
}

// 426+ dropped the sender arg
- (void)_didTapAudioButton {
    if (!rygCallConfirmProceeding && [RYGUtils getBoolPref:@"voice_call_confirm"]) {
        [RYGUtils showConfirmation:^(void) {
            rygCallConfirmProceeding = YES; %orig; rygCallConfirmProceeding = NO;
        } title:RYGLocalized(@"Confirm voice call")];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton {
    if (!rygCallConfirmProceeding && [RYGUtils getBoolPref:@"video_call_confirm"]) {
        [RYGUtils showConfirmation:^(void) {
            rygCallConfirmProceeding = YES; %orig; rygCallConfirmProceeding = NO;
        } title:RYGLocalized(@"Confirm video call")];
    } else {
        return %orig;
    }
}

// Pre-426 signatures
- (void)_didTapAudioButton:(id)arg1 {
    if (!rygCallConfirmProceeding && [RYGUtils getBoolPref:@"voice_call_confirm"]) {
        [RYGUtils showConfirmation:^(void) {
            rygCallConfirmProceeding = YES; %orig; rygCallConfirmProceeding = NO;
        } title:RYGLocalized(@"Confirm voice call")];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton:(id)arg1 {
    if (!rygCallConfirmProceeding && [RYGUtils getBoolPref:@"video_call_confirm"]) {
        [RYGUtils showConfirmation:^(void) {
            rygCallConfirmProceeding = YES; %orig; rygCallConfirmProceeding = NO;
        } title:RYGLocalized(@"Confirm video call")];
    } else {
        return %orig;
    }
}
%end