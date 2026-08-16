// Adds a "My Backgrounds" nav button to IG's native chat theme picker.

#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGPopupChrome.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgThreadPickerVC.h"
#import "RYGChatBgIvars.h"
#import <objc/runtime.h>

static void rygSetInjectedButton(UIViewController *vc) {
	UIBarButtonItem *old = vc.navigationItem.rightBarButtonItem;
	if (old && objc_getAssociatedObject(old, @selector(ryg_bgInjected))) return;

	UIBarButtonItem *item = RYGChromeBarButtonItem(@"photo.on.rectangle.angled", 18.0, vc, @selector(ryg_openMyBackgrounds), NULL);
	objc_setAssociatedObject(item, @selector(ryg_bgInjected), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	vc.navigationItem.rightBarButtonItem = item;
}

static NSString *rygThemePickerThreadID(id vc) {
	id key = RYGBgIvarValue(vc, "_threadKey") ?: RYGBgIvarValue(vc, "threadKey");
	NSString *tid = RYGBgReadTidFromContainer(key);
	return tid.length ? tid : [RYGChatBgThreadPickerVC activeThreadID];
}

static NSDictionary *rygThemePickerMetadata(id vc) {
	id meta = RYGBgIvarValue(vc, "_threadMetadata") ?: RYGBgIvarValue(vc, "threadMetadata");
	if (!meta) return nil;

	NSString *threadName = RYGBgStringIvar(meta, "_threadTitle") ?: @"";
	BOOL isGroup = [RYGBgIvarValue(meta, "_isGroup") boolValue];

	NSMutableArray *userPks = [NSMutableArray new];
	NSMutableArray *usersOut = [NSMutableArray new];

	id users = RYGBgIvarValue(meta, "_users");
	if ([users isKindOfClass:NSArray.class]) {
		for (id u in (NSArray *)users) {
			NSString *pk = RYGBgStringIvar(u, "_pk") ?: RYGBgStringIvar(u, "_id");
			NSString *uname = RYGBgStringIvar(u, "_username");
			NSString *full = RYGBgStringIvar(u, "_fullName")
				?: RYGBgStringIvar(u, "_full_name")
				?: RYGBgStringIvar(u, "_displayName")
				?: RYGBgStringIvar(u, "_name");

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

static void rygOpenMyBackgroundsFrom(UIViewController *vc) {
	// The picker VC owns the active threadKey directly — pull tid from there
	// first; fall back to the cache for paths that bypass the chat VC.
	NSString *tid = rygThemePickerThreadID(vc);

	// Capture title + recipients so the chats list shows real names.
	NSDictionary *meta = rygThemePickerMetadata(vc);
	if (tid.length && meta.count) {
		[[RYGChatBackgroundManager shared] setMetadata:meta forThreadID:tid];
	}

	RYGChatBgThreadPickerVC *picker = [[RYGChatBgThreadPickerVC alloc] initWithThreadID:tid];

	__weak UIViewController *weakVC = vc;
	objc_setAssociatedObject(picker, @selector(ryg_dismissCallback), ^{
		[weakVC dismissViewControllerAnimated:YES completion:nil];
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);

	[RYGPopupChrome presentVC:picker from:vc];
}

%group RYGChatBgPickerInjectGroup

%hook IGDirectThreadThemePickerViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	rygSetInjectedButton(self);
}

%new
- (void)ryg_openMyBackgrounds {
	rygOpenMyBackgroundsFrom(self);
}

%end

%end

// IG's newer "Customize chat" sheet (Theme + Font tabs) embeds the old theme
// picker and has no nav bar, so the bar-button never surfaces — hang the button
// as a chrome subview in the top-trailing corner instead.
%group RYGChatBgCustomizeSheetGroup

%hook _TtC31IGConsumerSubsDirectChatFontsUI40IGDirectCustomizeChatSheetViewController

- (void)viewDidLayoutSubviews {
	%orig;

	UIViewController *vc = (UIViewController *)self;
	if (objc_getAssociatedObject(self, @selector(ryg_bgInjected))) return;

	RYGChromeButton *btn = [[RYGChromeButton alloc] initWithSymbol:@"photo.on.rectangle.angled" pointSize:18.0 diameter:36.0];
	[btn addTarget:self action:@selector(ryg_openMyBackgrounds) forControlEvents:UIControlEventTouchUpInside];
	[vc.view addSubview:btn];

	btn.translatesAutoresizingMaskIntoConstraints = NO;
	id title = RYGBgIvarValue(self, "titleLabel");
	NSLayoutYAxisAnchor *yAnchor = [title isKindOfClass:UIView.class] ? ((UIView *)title).centerYAnchor : vc.view.safeAreaLayoutGuide.topAnchor;
	CGFloat yConst = [title isKindOfClass:UIView.class] ? 0.0 : 12.0;
	[NSLayoutConstraint activateConstraints:@[
		[btn.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-16.0],
		[btn.centerYAnchor constraintEqualToAnchor:yAnchor constant:yConst],
		[btn.widthAnchor constraintEqualToConstant:36.0],
		[btn.heightAnchor constraintEqualToConstant:36.0],
	]];

	objc_setAssociatedObject(self, @selector(ryg_bgInjected), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)ryg_openMyBackgrounds {
	rygOpenMyBackgroundsFrom((UIViewController *)self);
}

%end

%end

%ctor {
	if (![RYGUtils getBoolPref:RYGPrefChatBackgroundEnabled]) return;
	%init(RYGChatBgPickerInjectGroup);
	if (NSClassFromString(@"_TtC31IGConsumerSubsDirectChatFontsUI40IGDirectCustomizeChatSheetViewController"))
		%init(RYGChatBgCustomizeSheetGroup);
}