// Caches the active threadID off IGDirectThreadViewController's session ivar so
// surfaces detached from the chat hierarchy can still resolve the right chat.

#import "../../Utils.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgThreadPickerVC.h"
#import "SCIChatBgIvars.h"

static NSString *sciReadThreadIDFromVC(id vc) {
	id session = SCIBgIvarValue(vc, "_threadSession");
	return SCIBgReadTidFromContainer(SCIBgFindThreadKey(session));
}

static void sciUpdateActiveThreadID(id vc) {
	NSString *tid = sciReadThreadIDFromVC(vc);
	if (tid.length && ![tid isEqualToString:[SCIChatBgThreadPickerVC activeThreadID]]) {
		[SCIChatBgThreadPickerVC setActiveThreadID:tid];
	}
}

%group SCIChatBgThemeButtonGroup

%hook IGDirectThreadViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	sciUpdateActiveThreadID(self);
}

- (void)viewDidLayoutSubviews {
	%orig;
	sciUpdateActiveThreadID(self);
}

- (void)messageListViewControllerShouldPresentThemePicker:(id)arg1 {
	sciUpdateActiveThreadID(self);
	%orig;
}

%end

%end

%ctor {
	if (![SCIUtils getBoolPref:SCIPrefChatBackgroundEnabled]) return;
	%init(SCIChatBgThemeButtonGroup);
}