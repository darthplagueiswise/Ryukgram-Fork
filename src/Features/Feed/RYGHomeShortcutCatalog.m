#import "RYGHomeShortcutCatalog.h"
#import "RYGHomeShortcutBadges.h"
#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import <objc/runtime.h>
#import "../../Gallery/RYGGalleryViewController.h"
#import "../../Downloader/RYGDownloadManagerViewController.h"
#import "../General/RYGChangelog.h"
#import "../ProfileAnalyzer/RYGProfileAnalyzerViewController.h"
#import "../StoriesArchive/RYGStoriesArchiveViewController.h"
#import "GridFeed/RYGGridFeedSettingsViewController.h"
#import "../DeletedMessages/RYGDeletedMessagesViewController.h"
#import "../CallRecordings/RYGCallRecordingsViewController.h"
#import "../ReadReceipts/RYGReadReceiptLogViewController.h"
#import "../FollowRequests/RYGFollowRequestsViewController.h"
#import "../HiddenChats/RYGHiddenChatsViewController.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../UI/RYGFeatureIcons.h"
#import "../../Lock/RYGLockGate.h"
#import "../../Lock/RYGLockGroups.h"
#import "../../Lock/UI/RYGLockSecurityViewController.h"
#import "../../Lock/UI/RYGLockedChatsViewController.h"
#import "../../Settings/RYGFakeLocationSettingsVC.h"
#import "../General/RYGCacheManager.h"
#import "../../Settings/TweakSettings.h"

NSString *const kRYGHomeShortcutActionsPrefKey = @"home_shortcut_actions";
NSString *const kRYGHomeShortcutEnabledPrefKey = @"home_shortcut_enabled";
NSString *const kRYGHomeShortcutIconPrefKey	= @"home_shortcut_icon";

NSNotificationName const RYGHomeShortcutConfigDidChangeNotification = @"RYGHomeShortcutConfigDidChangeNotification";

static const void *kRYGShortcutSigKey = &kRYGShortcutSigKey;
static const void *kRYGShortcutBadgeKey = &kRYGShortcutBadgeKey;

@interface RYGHomeShortcutAction ()
- (instancetype)initWithID:(NSString *)aid title:(NSString *)title symbol:(NSString *)sym;
@end

@implementation RYGHomeShortcutAction
- (instancetype)initWithID:(NSString *)aid title:(NSString *)title symbol:(NSString *)sym {
	if ((self = [super init])) {
		_actionID = aid.copy;
		_title = title.copy;
		_symbol = sym.copy;
	}
	return self;
}
@end

@implementation RYGHomeShortcutCatalog

+ (NSArray<RYGHomeShortcutAction *> *)allActions {
	static NSArray<RYGHomeShortcutAction *> *cat = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		RYGHomeShortcutAction *(^make)(NSString *, NSString *, NSString *) = ^(NSString *aid, NSString *t, NSString *s) {
			return [[RYGHomeShortcutAction alloc] initWithID:aid title:t symbol:s];
		};
		cat = @[
			make(@"grid_feed",		  RYGLocalized(@"Grid feed"),		 @"ig_icon_photo_grid_tall_filled_24"),
			make(@"gallery",		  RYGLocalized(@"Gallery"),		  [RYGFeatureIcons gallery].igName),
			make(@"download_manager", RYGLocalized(@"Downloads"),		@"ig_icon_download_outline_24"),
			make(@"settings",		 RYGLocalized(@"Settings"),		 @"ig_icon_settings_outline_24"),
			make(@"security_privacy", RYGLocalized(@"Security & Privacy"), @"ig_icon_lock_pano_outline_24"),
			make(@"hidden_chats",	 RYGLocalized(@"Hidden chats"),	 @"ig_icon_direct_off_prism_outline_24"),
			make(@"locked_chats",	 RYGLocalized(@"Locked chats"),	 @"ig_icon_news_off_outline_24"),
			make(@"profile_analyzer", RYGLocalized(@"Profile Analyzer"), [RYGFeatureIcons profileAnalyzer].igName),
			make(@"stories_archive",  RYGLocalized(@"Stories archive"),  @"ig_icon_story_highlight_pano_outline_24"),
			make(@"deleted_messages", RYGLocalized(@"Deleted messages"), [RYGFeatureIcons deletedMessages].igName),
			make(@"call_recordings",  RYGLocalized(@"Call recordings"),  [RYGFeatureIcons callRecordings].igName),
			make(@"read_receipts",	RYGLocalized(@"Activity log"),	[RYGFeatureIcons readReceipts].igName),
			make(@"follow_requests",  RYGLocalized(@"Follow Requests"),  [RYGFeatureIcons followRequests].igName),
			make(@"fake_location",	RYGLocalized(@"Fake location"),	@"location_arrow"),
			make(@"mobileconfig",	RYGLocalized(@"MobileConfig"),	[RYGFeatureIcons mobileConfig].igName),
			make(@"clear_cache",	  RYGLocalized(@"Clear cache"),	  @"trash"),
			make(@"changelog",		RYGLocalized(@"Changelog"),		@"doc.text"),
		];
	});
	return cat;
}

+ (RYGHomeShortcutAction *)actionForID:(NSString *)actionID {
	for (RYGHomeShortcutAction *a in [self allActions]) {
		if ([a.actionID isEqualToString:actionID]) return a;
	}
	return nil;
}

+ (NSArray<NSString *> *)availableIcons {
	static NSArray<NSString *> *names = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		names = @[
			@"bolt", @"bolt.fill", @"bolt.circle", @"bolt.circle.fill",
			@"bolt.shield", @"bolt.shield.fill",
			@"sparkle", @"sparkles", @"wand.and.stars", @"wand.and.stars.inverse",
			@"square.grid.2x2", @"square.grid.2x2.fill",
			@"square.grid.3x3", @"square.grid.3x3.fill",
			@"circle.grid.2x2", @"circle.grid.2x2.fill",
			@"circle.grid.3x3", @"circle.grid.3x3.fill",
			@"apps.iphone", @"app.badge", @"app.badge.fill",
			@"square.stack", @"square.stack.fill", @"square.stack.3d.up", @"square.stack.3d.up.fill",
			@"ellipsis", @"ellipsis.circle", @"ellipsis.circle.fill", @"ellipsis.rectangle", @"ellipsis.rectangle.fill",
			@"line.3.horizontal", @"line.3.horizontal.circle", @"line.3.horizontal.circle.fill",
			@"gear", @"gearshape", @"gearshape.fill", @"gearshape.2", @"gearshape.2.fill",
			@"slider.horizontal.3", @"slider.vertical.3",
			@"wrench", @"wrench.fill",
			@"wrench.adjustable", @"wrench.adjustable.fill",
			@"wrench.and.screwdriver", @"wrench.and.screwdriver.fill",
			@"hammer", @"hammer.fill", @"hammer.circle", @"hammer.circle.fill",
			@"command", @"command.circle", @"command.circle.fill", @"command.square", @"command.square.fill",
			@"star", @"star.fill", @"star.circle", @"star.circle.fill",
			@"crown", @"crown.fill",
			@"flame", @"flame.fill",
			@"sun.max", @"sun.max.fill", @"moon", @"moon.fill",
			@"heart", @"heart.fill", @"heart.circle", @"heart.circle.fill",
			@"plus.circle", @"plus.circle.fill", @"plus.app", @"plus.app.fill",
			@"plus.square", @"plus.square.fill",
			@"power", @"power.circle", @"power.circle.fill",
			@"hare", @"hare.fill",
			@"globe", @"globe.americas", @"globe.americas.fill",
			@"safari", @"safari.fill",
			@"arrow.up.right.square", @"arrow.up.right.square.fill",
			@"arrow.up.forward.app", @"arrow.up.forward.app.fill",
			@"link", @"link.circle", @"link.circle.fill",
			@"chevron.right.circle", @"chevron.right.circle.fill",
			@"house", @"house.fill", @"house.circle", @"house.circle.fill",
			@"cube", @"cube.fill", @"shippingbox", @"shippingbox.fill",
			@"gift", @"gift.fill", @"gift.circle", @"gift.circle.fill",
			@"leaf", @"leaf.fill",
		];
	});
	return names;
}

+ (NSArray<NSString *> *)enabledActionIDs {
	if (![RYGUtils getBoolPref:kRYGHomeShortcutEnabledPrefKey]) return @[];
	NSMutableArray<NSString *> *out = [NSMutableArray array];
	for (NSDictionary *row in [RYGUtils getArrayPref:kRYGHomeShortcutActionsPrefKey]) {
		if (![row isKindOfClass:[NSDictionary class]]) continue;
		NSString *aid = row[@"id"];
		if (![aid isKindOfClass:[NSString class]] || !aid.length) continue;
		if (![row[@"enabled"] boolValue]) continue;
		if (![self actionForID:aid]) continue;
		[out addObject:aid];
	}
	return out;
}

+ (void)fireActionID:(NSString *)actionID contextView:(UIView *)contextView {
	if ([actionID isEqualToString:@"grid_feed"]) {
		[RYGPopupChrome presentVC:[RYGGridFeedSettingsViewController new]
		                     from:[RYGUtils nearestViewControllerForView:contextView]];
		return;
	}
	if ([actionID isEqualToString:@"gallery"]) {
		[RYGGalleryViewController presentGallery];
		return;
	}
	if ([actionID isEqualToString:@"stories_archive"]) {
		[RYGStoriesArchiveViewController presentFrom:[RYGUtils nearestViewControllerForView:contextView]];
		return;
	}
	if ([actionID isEqualToString:@"download_manager"]) {
		[RYGDownloadManagerViewController present];
		return;
	}
	if ([actionID isEqualToString:@"settings"]) {
		UIWindow *w = contextView.window ?: UIApplication.sharedApplication.keyWindow;
		if (w) [RYGUtils showSettingsVC:w];
		return;
	}
	if ([actionID isEqualToString:@"profile_analyzer"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate presentLockedVC:[RYGProfileAnalyzerViewController new]
		                    forGroup:RYGLockGroupProfileAnalyzer
		                        from:top];
		return;
	}
	if ([actionID isEqualToString:@"deleted_messages"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGDeletedMessagesViewController presentFromViewController:top];
		return;
	}
	if ([actionID isEqualToString:@"call_recordings"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGCallRecordingsViewController presentFromViewController:top];
		return;
	}
	if ([actionID isEqualToString:@"read_receipts"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGReadReceiptLogViewController presentFromViewController:top];
		return;
	}
	if ([actionID isEqualToString:@"follow_requests"]) {
		[RYGPopupChrome presentVC:[RYGFollowRequestsViewController new] from:[RYGUtils nearestViewControllerForView:contextView]];
		return;
	}
	if ([actionID isEqualToString:@"changelog"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		if (top) [RYGChangelog presentAllFromViewController:top];
		return;
	}
	// Settings-adjacent shortcuts honour the Settings group lock; locked chats uses the Chats group.
	if ([actionID isEqualToString:@"security_privacy"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate runGated:RYGLockGroupSettings from:top then:^{
			[RYGPopupChrome presentVC:[RYGLockSecurityViewController new] from:[RYGUtils nearestViewControllerForView:contextView]];
		}];
		return;
	}
	if ([actionID isEqualToString:@"hidden_chats"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate runGated:RYGLockGroupSettings from:top then:^{
			[RYGPopupChrome presentVC:[RYGHiddenChatsViewController new] from:[RYGUtils nearestViewControllerForView:contextView]];
		}];
		return;
	}
	if ([actionID isEqualToString:@"locked_chats"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate presentLockedVC:[RYGLockedChatsViewController new]
		                    forGroup:RYGLockGroupChats
		                        from:top];
		return;
	}
	if ([actionID isEqualToString:@"fake_location"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate runGated:RYGLockGroupSettings from:top then:^{
			[RYGPopupChrome presentVC:[RYGFakeLocationSettingsVC new] from:[RYGUtils nearestViewControllerForView:contextView]];
		}];
		return;
	}
	if ([actionID isEqualToString:@"mobileconfig"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate runGated:RYGLockGroupSettings from:top then:^{
			[RYGTweakSettings openMobileConfigBrowser];
		}];
		return;
	}
	if ([actionID isEqualToString:@"clear_cache"]) {
		UIViewController *top = [RYGUtils nearestViewControllerForView:contextView];
		[RYGLockGate runGated:RYGLockGroupSettings from:top then:^{
			[RYGTweakSettings presentClearCacheConfirmation];
		}];
		return;
	}
}

+ (NSString *)currentSymbol {
	NSString *userIcon = [RYGUtils getStringPref:kRYGHomeShortcutIconPrefKey];
	if (userIcon.length && ![userIcon isEqualToString:@"auto"]) return userIcon;
	NSArray<NSString *> *ids = [self enabledActionIDs];
	if (ids.count == 1) {
		RYGHomeShortcutAction *a = [self actionForID:ids.firstObject];
		if (a.symbol.length) return a.symbol;
	}
	return @"ellipsis.circle";
}

+ (void)invalidateButton:(RYGChromeButton *)button {
	objc_setAssociatedObject(button, kRYGShortcutSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)configureButton:(RYGChromeButton *)button {
	NSArray<NSString *> *ids = [self enabledActionIDs];
	NSString *symbol = [self currentSymbol];
	NSString *sig = [NSString stringWithFormat:@"%@|%@", symbol, [ids componentsJoinedByString:@","]];
	if ([objc_getAssociatedObject(button, kRYGShortcutSigKey) isEqualToString:sig]) return;
	objc_setAssociatedObject(button, kRYGShortcutSigKey, sig, OBJC_ASSOCIATION_COPY_NONATOMIC);

	button.menu = nil;
	button.showsMenuAsPrimaryAction = NO;
	[button removeActionForIdentifier:@"ryg.home.shortcut" forControlEvents:UIControlEventTouchUpInside];

	button.iconTint = UIColor.labelColor;
	button.symbolName = symbol;

	__weak RYGChromeButton *wb = button;
	if (ids.count == 1) {
		NSString *actionID = ids.firstObject;
		UIAction *tap = [UIAction actionWithTitle:@"" image:nil identifier:@"ryg.home.shortcut" handler:^(__unused UIAction *ac) {
			[self fireActionID:actionID contextView:wb];
		}];
		[button addAction:tap forControlEvents:UIControlEventTouchUpInside];
	} else {
		NSMutableArray<UIAction *> *items = [NSMutableArray array];
		for (NSString *actionID in ids) {
			RYGHomeShortcutAction *e = [self actionForID:actionID];
			if (!e) continue;
			UIImage *icon = e.symbol.length ? [RYGIcon imageNamed:e.symbol pointSize:18.0 weight:UIImageSymbolWeightRegular] : nil;
			UIAction *item = [UIAction actionWithTitle:(e.title ?: actionID) image:icon identifier:nil handler:^(__unused UIAction *ac) {
				[self fireActionID:actionID contextView:wb];
			}];
			NSInteger n = [RYGHomeShortcutBadges countForActionID:actionID];
			if (n > 0) item.subtitle = [NSString stringWithFormat:RYGLocalized(@"%ld new"), (long)n];
			[items addObject:item];
		}
		button.menu = [UIMenu menuWithTitle:@"" children:items];
		button.showsMenuAsPrimaryAction = YES;
	}
}

+ (void)updateBadgeOnButton:(RYGChromeButton *)button {
	NSArray<NSString *> *ids = [self enabledActionIDs];
	UIView *dot = objc_getAssociatedObject(button, kRYGShortcutBadgeKey);
	if ([RYGHomeShortcutBadges totalForActionIDs:ids] <= 0) { dot.hidden = YES; return; }

	if (!dot) {
		dot = [[UIView alloc] init];
		dot.backgroundColor = [UIColor colorWithRed:1.0 green:0.176 blue:0.235 alpha:1.0];
		dot.layer.borderColor = UIColor.systemBackgroundColor.CGColor;
		dot.layer.borderWidth = 1.5;
		dot.userInteractionEnabled = NO;
		[button.captureContentView addSubview:dot];
		objc_setAssociatedObject(button, kRYGShortcutBadgeKey, dot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	dot.hidden = NO;

	CGFloat d = 11.0;
	CGFloat bw = button.bounds.size.width > 1.0 ? button.bounds.size.width : button.diameter;
	CGFloat r = button.symbolPointSize * 0.5;
	dot.frame = CGRectMake(bw / 2.0 + r - d / 2.0, bw / 2.0 - r - d / 2.0, d, d);
	dot.layer.cornerRadius = d / 2.0;
	[button.captureContentView bringSubviewToFront:dot];
}

@end
