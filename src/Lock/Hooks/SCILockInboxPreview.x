// Masks the last-message preview in the inbox cell when the thread is locked
// and the Chats group is currently locked. Pref-gated. Reloads the inbox list
// adapter when the locked-chat set or chats session changes.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../SCILockManager.h"
#import "../SCILockGroups.h"
#import <objc/runtime.h>
#import <objc/message.h>

static id sciInboxSafeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

@interface IGDirectInboxViewController (SCILockInboxPreview)
- (void)sciReloadInboxForLockChange;
@end

%hook IGDirectInboxThreadCellViewModel

- (id)messageText {
    id orig = %orig;
    if (![[SCILockManager shared] isMasterEnabled]) return orig;
    if (![SCIUtils getBoolPref:@"lock_chats_hide_preview"]) return orig;
    if (![[SCILockManager shared] isGroupLocked:SCILockGroupChats]) return orig;
    NSString *tid = sciInboxSafeKey(self, @"threadId");
    if (!tid.length) return orig;
    if (![[[SCILockManager shared] lockedChatIDs] containsObject:tid]) return orig;
    return [[NSAttributedString alloc] initWithString:@"• • •"];
}

%end

%hook IGDirectInboxViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(sciReloadInboxForLockChange)
                                                  name:SCILockChatListDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(sciReloadInboxForLockChange)
                                                  name:SCILockSessionDidChangeNotification
                                                object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%new
- (void)sciReloadInboxForLockChange {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self sciReloadInboxForLockChange]; });
        return;
    }
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_listAdapter");
    if (!iv) return;
    id adapter = object_getIvar(self, iv);
    if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)]) {
        ((void(*)(id,SEL,BOOL,id))objc_msgSend)(adapter, @selector(performUpdatesAnimated:completion:), NO, nil);
    }
}

%end
