// Masks the last-message preview in the inbox cell when the thread is locked
// and the Chats group is currently locked. Pref-gated. Reloads the inbox list
// adapter when the locked-chat set or chats session changes.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../RYGLockManager.h"
#import "../RYGLockGroups.h"
#import <objc/runtime.h>
#import <objc/message.h>

static id rygInboxSafeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

@interface IGDirectInboxViewController (RYGLockInboxPreview)
- (void)rygReloadInboxForLockChange;
@end

%hook IGDirectInboxThreadCellViewModel

- (id)messageText {
    id orig = %orig;
    if (![[RYGLockManager shared] isMasterEnabled]) return orig;
    if (![RYGUtils getBoolPref:@"lock_chats_hide_preview"]) return orig;
    if (![[RYGLockManager shared] isGroupLocked:RYGLockGroupChats]) return orig;
    NSString *tid = rygInboxSafeKey(self, @"threadId");
    if (!tid.length) return orig;
    if (![[[RYGLockManager shared] lockedChatIDs] containsObject:tid]) return orig;
    return [[NSAttributedString alloc] initWithString:@"• • •"];
}

%end

%hook IGDirectInboxViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(rygReloadInboxForLockChange)
                                                  name:RYGLockChatListDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(rygReloadInboxForLockChange)
                                                  name:RYGLockSessionDidChangeNotification
                                                object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%new
- (void)rygReloadInboxForLockChange {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self rygReloadInboxForLockChange]; });
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
