// Caches the active threadID off IGDirectThreadViewController's session ivar so
// surfaces detached from the chat hierarchy can still resolve the right chat.

#import "../../Utils.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgThreadPickerVC.h"
#import "RYGChatBgIvars.h"

static NSString *rygReadThreadIDFromVC(id vc) {
	id session = RYGBgIvarValue(vc, "_threadSession");
	return RYGBgReadTidFromContainer(RYGBgFindThreadKey(session));
}

static void rygUpdateActiveThreadID(id vc) {
	NSString *tid = rygReadThreadIDFromVC(vc);
	if (tid.length && ![tid isEqualToString:[RYGChatBgThreadPickerVC activeThreadID]]) {
		[RYGChatBgThreadPickerVC setActiveThreadID:tid];
	}
}

%group RYGChatBgThemeButtonGroup

%hook IGDirectThreadViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	rygUpdateActiveThreadID(self);
}

- (void)viewDidLayoutSubviews {
	%orig;
	rygUpdateActiveThreadID(self);
}

- (void)messageListViewControllerShouldPresentThemePicker:(id)arg1 {
	rygUpdateActiveThreadID(self);
	%orig;
}

%end

%end

%ctor {
	if (![RYGUtils getBoolPref:RYGPrefChatBackgroundEnabled]) return;
	%init(RYGChatBgThemeButtonGroup);
}