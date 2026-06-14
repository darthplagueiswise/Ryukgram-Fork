#import "../../Utils.h"
#import "../../CallButtonHelpers.h"

// Old dual-button accounts chain tap methods (_didTapAudioButton ->
// _didTapButtonWithCallType:); guard against the nested hook confirming twice.
static BOOL sciCallConfirmProceeding = NO;

%hook IGDirectThreadCallButtonsCoordinator
// Newer A/B: call button opens an IGDSMenu; drop the hidden type's entry and
// wrap the survivor's handler with a confirmation.
- (id)buttonMenuItems {
    NSArray *items = %orig;
    if (![items isKindOfClass:[NSArray class]]) return items;

    BOOL hideV = [SCIUtils getBoolPref:@"hide_video_call_button"];
    BOOL hideA = [SCIUtils getBoolPref:@"hide_voice_call_button"];
    BOOL confV = [SCIUtils getBoolPref:@"video_call_confirm"];
    BOOL confA = [SCIUtils getBoolPref:@"voice_call_confirm"];
    if (!hideV && !hideA && !confV && !confA) return items;

    Class itemCls = NSClassFromString(@"IGDSMenuItem");
    NSUInteger count = items.count;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        id item = items[i];
        BOOL isVideo = sciCallMenuTypeIsVideo(item, i, count);
        if (isVideo ? hideV : hideA) continue;

        NSString *key = isVideo ? @"video_call_confirm" : @"voice_call_confirm";
        Ivar hv = class_getInstanceVariable([item class], "_handler");
        if (!itemCls || !hv || ![SCIUtils getBoolPref:key]) { [out addObject:item]; continue; }

        void (^orig)(void) = object_getIvar(item, hv);
        Ivar iv = class_getInstanceVariable([item class], "_image");
        UIImage *img = iv ? object_getIvar(item, iv) : nil;
        NSString *title = [item respondsToSelector:@selector(title)] ? [item title] : nil;
        NSString *ctitle = SCILocalized(isVideo ? @"Confirm video call" : @"Confirm voice call");
        void (^wrapped)(void) = ^{ [SCIUtils showConfirmation:^(void) {
            sciCallConfirmProceeding = YES;
            if (orig) orig();
            sciCallConfirmProceeding = NO;
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
    BOOL isVideo = sciCallTypeIsVideo(self, type, &resolved);
    NSString *key = isVideo ? @"video_call_confirm" : @"voice_call_confirm";
    if (!sciCallConfirmProceeding && [SCIUtils getBoolPref:key]) {
        [SCIUtils showConfirmation:^(void) {
            sciCallConfirmProceeding = YES; %orig; sciCallConfirmProceeding = NO;
        } title:SCILocalized(isVideo ? @"Confirm video call" : @"Confirm voice call")];
    } else {
        return %orig;
    }
}

// 426+ dropped the sender arg
- (void)_didTapAudioButton {
    if (!sciCallConfirmProceeding && [SCIUtils getBoolPref:@"voice_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) {
            sciCallConfirmProceeding = YES; %orig; sciCallConfirmProceeding = NO;
        } title:SCILocalized(@"Confirm voice call")];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton {
    if (!sciCallConfirmProceeding && [SCIUtils getBoolPref:@"video_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) {
            sciCallConfirmProceeding = YES; %orig; sciCallConfirmProceeding = NO;
        } title:SCILocalized(@"Confirm video call")];
    } else {
        return %orig;
    }
}

// Pre-426 signatures
- (void)_didTapAudioButton:(id)arg1 {
    if (!sciCallConfirmProceeding && [SCIUtils getBoolPref:@"voice_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) {
            sciCallConfirmProceeding = YES; %orig; sciCallConfirmProceeding = NO;
        } title:SCILocalized(@"Confirm voice call")];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton:(id)arg1 {
    if (!sciCallConfirmProceeding && [SCIUtils getBoolPref:@"video_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) {
            sciCallConfirmProceeding = YES; %orig; sciCallConfirmProceeding = NO;
        } title:SCILocalized(@"Confirm video call")];
    } else {
        return %orig;
    }
}
%end
