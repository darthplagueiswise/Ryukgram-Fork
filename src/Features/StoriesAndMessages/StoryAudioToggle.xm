// Story audio mute/unmute toggle.
// Flips IGAudioStatusAnnouncer private state then fans out to listeners
// via the two IGUltralightAnnouncer sub-forwarders (426 dropped the old
// mute-switch notification).

#import <AVFoundation/AVFoundation.h>
#import "StoryHelpers.h"
#import "StoryMenuItems.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

extern "C" __weak UIViewController *rygActiveStoryViewerVC;
extern "C" void rygRefreshAllVisibleOverlays(UIViewController *);

static id rygAudioAnnouncer = nil;

static id rygReadIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    return object_getIvar(obj, iv);
}

static BOOL rygIGAudioEnabled(void) {
    if (!rygAudioAnnouncer) return NO;
    SEL s = NSSelectorFromString(@"isAudioEnabledForSoundBehavior:");
    if ([rygAudioAnnouncer respondsToSelector:s]) {
        typedef BOOL (*Fn)(id, SEL, NSInteger);
        return ((Fn)objc_msgSend)(rygAudioAnnouncer, s, 1);
    }
    Ivar ivar = class_getInstanceVariable([rygAudioAnnouncer class], "_audioEnabled");
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    return *(BOOL *)((char *)(__bridge void *)rygAudioAnnouncer + offset);
}

static void rygWriteAudioEnabled(BOOL value) {
    if (!rygAudioAnnouncer) return;
    Ivar ivar = class_getInstanceVariable([rygAudioAnnouncer class], "_audioEnabled");
    if (!ivar) return;
    ptrdiff_t offset = ivar_getOffset(ivar);
    *(BOOL *)((char *)(__bridge void *)rygAudioAnnouncer + offset) = value;
}

// ============ Volume KVO ============

@interface _RYGVolumeObserver : NSObject
@end
@implementation _RYGVolumeObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (rygActiveStoryViewerVC) rygRefreshAllVisibleOverlays(rygActiveStoryViewerVC);
    });
}
@end
static _RYGVolumeObserver *rygVolumeObserver = nil;

// ============ Public API ============

extern "C" {

BOOL rygStoryAudioBypass = NO;

void rygToggleStoryAudio(void) {
    if (!rygAudioAnnouncer) return;

    BOOL on = rygIGAudioEnabled();
    BOOL wanted = !on;
    rygStoryAudioBypass = YES;

    rygWriteAudioEnabled(wanted);

    // 2 = user-enabled, 1 = user-disabled.
    Ivar stickIv = class_getInstanceVariable([rygAudioAnnouncer class], "_stickySoundState");
    if (stickIv) {
        ptrdiff_t off = ivar_getOffset(stickIv);
        NSInteger *p = (NSInteger *)((char *)(__bridge void *)rygAudioAnnouncer + off);
        *p = wanted ? 2 : 1;
    }

    SEL notify = NSSelectorFromString(@"audioStatusDidChangeIsAudioEnabled:forReason:");
    typedef void (*NotifyFn)(id, SEL, BOOL, NSInteger);
    id subA = rygReadIvar(rygAudioAnnouncer, "_announcerForDefaultBehaviors");
    id subB = rygReadIvar(rygAudioAnnouncer, "_announcerForIgnoreUserPreferenceAndMatchDeviceState");
    if (subA) ((NotifyFn)objc_msgSend)(subA, notify, wanted, 0);
    if (subB) ((NotifyFn)objc_msgSend)(subB, notify, wanted, 0);

    rygStoryAudioBypass = NO;
    if (rygActiveStoryViewerVC) rygRefreshAllVisibleOverlays(rygActiveStoryViewerVC);
}

BOOL rygIsStoryAudioEnabled(void) {
    return rygIGAudioEnabled();
}

static BOOL rygKVORegistered = NO;

void rygInitStoryAudioState(void) {
    if (rygKVORegistered) return;
    if (!rygVolumeObserver) rygVolumeObserver = [_RYGVolumeObserver new];
    @try {
        [[AVAudioSession sharedInstance] addObserver:rygVolumeObserver
                                         forKeyPath:@"outputVolume"
                                            options:NSKeyValueObservingOptionNew
                                            context:NULL];
        rygKVORegistered = YES;
    } @catch (__unused id e) {}
}

void rygResetStoryAudioState(void) {
    if (!rygKVORegistered) return;
    @try {
        [[AVAudioSession sharedInstance] removeObserver:rygVolumeObserver forKeyPath:@"outputVolume"];
        rygKVORegistered = NO;
    } @catch (__unused id e) {}
}

} // extern "C"

// ============ Announcer hooks ============

static id (*orig_announcerInit)(id, SEL);
static id new_announcerInit(id self, SEL _cmd) {
    id r = orig_announcerInit(self, _cmd);
    rygAudioAnnouncer = self;
    return r;
}

static void (*orig_announce)(id, SEL, BOOL, NSInteger);
static void new_announce(id self, SEL _cmd, BOOL enabled, NSInteger reason) {
    orig_announce(self, _cmd, enabled, reason);
    if (rygActiveStoryViewerVC) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (rygActiveStoryViewerVC) rygRefreshAllVisibleOverlays(rygActiveStoryViewerVC);
        });
    }
}

// ============ story-menu entry ============
// Shared provider; icon reflects current state, title is the action (mirrors StoryOverlayButtons).
extern "C" RYGStoryMenuEntry *rygStoryAudioMenuEntry(void) {
    if (!rygActiveStoryViewerVC) return nil;
    BOOL on = rygIGAudioEnabled();
    NSString *title = on ? RYGLocalized(@"Mute story audio") : RYGLocalized(@"Unmute story audio");
    NSString *symbol = on ? @"speaker.wave.2.fill" : @"speaker.slash.fill";
    return [RYGStoryMenuEntry entryWithTitle:title symbol:symbol handler:^{ rygToggleStoryAudio(); }];
}

// ============ Ringer listener ============

static void rygRingerChanged(CFNotificationCenterRef center, void *observer,
                              CFNotificationName name, const void *object,
                              CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (rygActiveStoryViewerVC) rygRefreshAllVisibleOverlays(rygActiveStoryViewerVC);
    });
}

// ============ Init ============

__attribute__((constructor)) static void _storyAudioInit(void) {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        rygRingerChanged, CFSTR("com.apple.springboard.ringerstate"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    Class cls = NSClassFromString(@"IGAudioStatusAnnouncer");
    if (!cls) return;
    MSHookMessageEx(cls, @selector(init), (IMP)new_announcerInit, (IMP *)&orig_announcerInit);
    SEL s = NSSelectorFromString(@"_announceForDeviceStateChangesIfNeededForAudioEnabled:reason:");
    if (class_getInstanceMethod(cls, s))
        MSHookMessageEx(cls, s, (IMP)new_announce, (IMP *)&orig_announce);
}
