#import "../../Utils.h"
#import "../../CallButtonHelpers.h"

%hook IGDirectThreadCallButtonsCoordinator
// Newer A/B: the call button opens an IGDSMenu whose entries each run their own
// handler block. One pass over the unfiltered menu drops the hidden type's entry
// and wraps the survivor's handler with a confirmation (type from menu position).
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
        void (^wrapped)(void) = ^{ [SCIUtils showConfirmation:^(void) { if (orig) orig(); } title:ctitle]; };

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
    if ([SCIUtils getBoolPref:key]) {
        [SCIUtils showConfirmation:^(void) { %orig; }
                             title:SCILocalized(isVideo ? @"Confirm video call" : @"Confirm voice call")];
    } else {
        return %orig;
    }
}

// 426+ dropped the sender arg
- (void)_didTapAudioButton {
    if ([SCIUtils getBoolPref:@"voice_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; } title:SCILocalized(@"Confirm voice call")];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton {
    if ([SCIUtils getBoolPref:@"video_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; } title:SCILocalized(@"Confirm video call")];
    } else {
        return %orig;
    }
}

// Pre-426 signatures
- (void)_didTapAudioButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"voice_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; } title:SCILocalized(@"Confirm voice call")];
    } else {
        return %orig;
    }
}

- (void)_didTapVideoButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"video_call_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; } title:SCILocalized(@"Confirm video call")];
    } else {
        return %orig;
    }
}
%end