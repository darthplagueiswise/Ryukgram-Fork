// Incoming typing from IGDirectTypingStatusService (single + batch paths); route
// both through the engine, which drops self and dedups.

#import "RYGActivityEngine.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static id atIvar(id o, const char *n) {
    Ivar iv = o ? class_getInstanceVariable([o class], n) : NULL;
    return iv ? object_getIvar(o, iv) : nil;
}
static NSString *atStr(id o, const char *n) {
    id v = atIvar(o, n);
    if ([v isKindOfClass:NSString.class]) return v;
    return [v respondsToSelector:@selector(stringValue)] ? [v stringValue] : nil;
}
static BOOL atBool(id o, const char *n) {
    Ivar iv = o ? class_getInstanceVariable([o class], n) : NULL;
    if (!iv) return NO;
    return *(signed char *)((char *)(__bridge void *)o + ivar_getOffset(iv)) != 0;
}

static void atHandleStatus(id status) {
    if (!status) return;
    NSString *pk = atStr(status, "_userPk");
    if (!pk.length) return;
    [RYGActivityEngine handleTypingActive:atBool(status, "_isActive") forPK:pk threadId:atStr(status, "_threadId")];
}

%group ActivityTyping

%hook IGDirectTypingStatusService

- (void)receiveOptimisticTypingStatus:(id)status {
    %orig;
    @try { atHandleStatus(status); } @catch (__unused id e) {}
}

- (void)setThreadIdToTypingStatuses:(id)map {
    %orig;
    @try {
        if (![map respondsToSelector:@selector(objectEnumerator)]) return;
        for (id val in [map objectEnumerator]) {
            if ([val respondsToSelector:@selector(objectEnumerator)] && ![val isKindOfClass:NSString.class]) {
                for (id s in [val objectEnumerator]) atHandleStatus(s);
            } else {
                atHandleStatus(val);
            }
        }
    } @catch (__unused id e) {}
}

%end

%end

%ctor {
    if ([RYGUtils getBoolPref:@"activity_notif_enabled"])
        %init(ActivityTyping);
}
