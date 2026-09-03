// Local, per-chat subscriber chat fonts. Non-subs can't apply them server-side,
// but the fonts ship in-app, so forcing IGDirectThreadMetadata.chatFontStyle makes
// the renderer use them locally. The metadata carries no thread id, so scope by the
// visible thread. The list rebuilds only on a thread-data change, so the font shows
// on the chat's next reopen.

#import "../../Utils.h"
#import "../ChatBackground/RYGChatBgThreadPickerVC.h"
#import "../ChatBackground/RYGChatBgIvars.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import <objc/runtime.h>

static long long gForcedFontStyle = -1;
static long long gPendingFontStyle = -1;
static NSString *gActiveThreadID = nil;

static NSString *const kFontStoreKey = @"ryg_chatfont_threads";

static long long rygFontForThread(NSString *tid) {
	if (!tid.length) return -1;
	id v = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFontStoreKey][tid];
	return v ? [v longLongValue] : -1;
}

static void rygSetFontForThread(NSString *tid, long long style) {
	if (!tid.length) return;
	NSDictionary *cur = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFontStoreKey];
	NSMutableDictionary *s = cur ? [cur mutableCopy] : [NSMutableDictionary new];
	if (style < 0) [s removeObjectForKey:tid]; else s[tid] = @(style);
	[[NSUserDefaults standardUserDefaults] setObject:s forKey:kFontStoreKey];
}

static NSString *rygThreadIDOfVC(id vc) {
	return RYGBgReadTidFromContainer(RYGBgFindThreadKey(RYGBgIvarValue(vc, "_threadSession")));
}

static void rygUnlockFontOption(id option) {
	if (!option) return;
	Ivar iv = class_getInstanceVariable([option class], "isLocked");
	if (iv) *(BOOL *)((char *)(__bridge void *)option + ivar_getOffset(iv)) = NO;
}

static id rygObjIvar(id obj, const char *name) {
	if (!obj) return nil;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return nil;
	@try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static long long rygLongIvar(id obj, const char *name) {
	if (!obj) return -999;
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return -999;
	return *(long long *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

%group RYGChatFontsGroup

%hook _TtC31IGConsumerSubsDirectChatFontsUI33IGDirectChatFontSectionController

- (void)didUpdateToObject:(id)object {
	%orig;
	rygUnlockFontOption(object);
	objc_setAssociatedObject(self, _cmd, object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)didSelectItemAtIndex:(long long)index {
	id opt = rygObjIvar(self, "option")
	      ?: objc_getAssociatedObject(self, @selector(didUpdateToObject:));
	rygUnlockFontOption(opt);
	gPendingFontStyle = rygLongIvar(opt, "fontStyle");
	%orig;
}

%end

%hook _TtC31IGConsumerSubsDirectChatFontsUI40IGDirectCustomizeChatSheetViewController

- (void)viewWillDisappear:(BOOL)animated {
	%orig;
	if (gPendingFontStyle < 0) return;
	NSString *tid = gActiveThreadID ?: [RYGChatBgThreadPickerVC activeThreadID];
	rygSetFontForThread(tid, gPendingFontStyle);
	gForcedFontStyle = gPendingFontStyle;
	gPendingFontStyle = -1;
	RYGNotifySuccess(RYG_NOTIF_CHAT_FONT, RYGLocalized(@"Chat font saved"),
	                 RYGLocalized(@"Reopen this chat to see the new font"));
}

%end

%hook IGDirectThreadMetadata

- (long long)chatFontStyle {
	if (gForcedFontStyle >= 0) return gForcedFontStyle;
	return %orig;
}

%end

%hook IGDirectThreadViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	NSString *tid = rygThreadIDOfVC(self);
	if (tid.length) gActiveThreadID = [tid copy];
	gForcedFontStyle = rygFontForThread(tid);
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;
	gForcedFontStyle = -1;
	gPendingFontStyle = -1;
}

%end

%end

%ctor {
	if (![RYGUtils getBoolPref:@"igt_ip_chatfonts"]) return;
	if (!NSClassFromString(@"_TtC31IGConsumerSubsDirectChatFontsUI33IGDirectChatFontSectionController")) return;
	%init(RYGChatFontsGroup);
}
