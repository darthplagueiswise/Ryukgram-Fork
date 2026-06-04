// Adds a "My Backgrounds" nav button to IG's native chat theme picker.

#import "../../Utils.h"
#import "../../UI/SCIPopupChrome.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgThreadPickerVC.h"
#import "SCIChatBgIvars.h"
#import <objc/runtime.h>

static void sciSetInjectedButton(UIViewController *vc) {
	UIBarButtonItem *old = vc.navigationItem.rightBarButtonItem;
	if (old && objc_getAssociatedObject(old, @selector(sci_bgInjected))) return;

	UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"photo.on.rectangle.angled"]
															 style:UIBarButtonItemStylePlain
															target:vc
															action:@selector(sci_openMyBackgrounds)];
	objc_setAssociatedObject(item, @selector(sci_bgInjected), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	vc.navigationItem.rightBarButtonItem = item;
}

static NSString *sciThemePickerThreadID(id vc) {
	id key = SCIBgIvarValue(vc, "_threadKey");
	NSString *tid = SCIBgReadTidFromContainer(key);
	return tid.length ? tid : [SCIChatBgThreadPickerVC activeThreadID];
}

static NSDictionary *sciThemePickerMetadata(id vc) {
	id meta = SCIBgIvarValue(vc, "_threadMetadata");
	if (!meta) return nil;

	NSString *threadName = SCIBgStringIvar(meta, "_threadTitle") ?: @"";
	BOOL isGroup = [SCIBgIvarValue(meta, "_isGroup") boolValue];

	NSMutableArray *userPks = [NSMutableArray new];
	NSMutableArray *usersOut = [NSMutableArray new];

	id users = SCIBgIvarValue(meta, "_users");
	if ([users isKindOfClass:NSArray.class]) {
		for (id u in (NSArray *)users) {
			NSString *pk = SCIBgStringIvar(u, "_pk") ?: SCIBgStringIvar(u, "_id");
			NSString *uname = SCIBgStringIvar(u, "_username");
			NSString *full = SCIBgStringIvar(u, "_fullName")
				?: SCIBgStringIvar(u, "_full_name")
				?: SCIBgStringIvar(u, "_displayName")
				?: SCIBgStringIvar(u, "_name");

			if (pk.length) [userPks addObject:pk];

			NSMutableDictionary *info = [NSMutableDictionary new];
			if (pk.length) info[@"pk"] = pk;
			if (uname.length) info[@"username"] = uname;
			if (full.length) info[@"fullName"] = full;
			if (info.count) [usersOut addObject:info];
		}
	}

	if (!threadName.length && !userPks.count && !usersOut.count) return nil;

	return @{
		@"threadName": threadName,
		@"isGroup": @(isGroup),
		@"userPks": userPks,
		@"users": usersOut,
		@"updatedAt": @([[NSDate date] timeIntervalSince1970])
	};
}

%group SCIChatBgPickerInjectGroup

%hook IGDirectThreadThemePickerViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	sciSetInjectedButton(self);
}

%new
- (void)sci_openMyBackgrounds {
	// The picker VC owns the active threadKey directly — pull tid from there
	// first; fall back to the cache for paths that bypass the chat VC.
	NSString *tid = sciThemePickerThreadID(self);

	// Capture title + recipients so the chats list shows real names.
	NSDictionary *meta = sciThemePickerMetadata(self);
	if (tid.length && meta.count) {
		[[SCIChatBackgroundManager shared] setMetadata:meta forThreadID:tid];
	}

	SCIChatBgThreadPickerVC *picker = [[SCIChatBgThreadPickerVC alloc] initWithThreadID:tid];

	__weak UIViewController *weakSelf = self;
	objc_setAssociatedObject(picker, @selector(sci_dismissCallback), ^{
		[weakSelf dismissViewControllerAnimated:YES completion:nil];
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);

	[SCIPopupChrome presentVC:picker from:self];
}

%end

%end

%ctor {
	if (![SCIUtils getBoolPref:SCIPrefChatBackgroundEnabled]) return;
	%init(SCIChatBgPickerInjectGroup);
}