// Per-tab settings cell builders live in RYGSettings_<Tab>.m under this folder
// as categories on RYGTweakSettings. TweakSettings.m's +sections stitches them.

#import "../TweakSettings.h"
#import "../RYGSetting.h"
#import "../RYGSymbol.h"
#import "../RYGSettingsBackup.h"
#import "../RYGActionMenuConfigViewController.h"
#import "../RYGExcludedChatsViewController.h"
#import "../RYGExcludedStoryUsersViewController.h"
#import "../RYGEmbedDomainViewController.h"
#import "../RYGHomeShortcutConfigViewController.h"
#import "../RYGProfileCardDetailsViewController.h"
#import "../RYGSearchCardDetailsViewController.h"
#import "../../ActionButton/RYGActionCatalog.h"
#import "../../ActionButton/RYGActionIcon.h"
#import "../../Features/StoriesAndMessages/RYGExcludedThreads.h"
#import "../../Features/StoriesAndMessages/RYGExcludedStoryUsers.h"
#import "../../Features/ChatBackground/RYGChatBgSettingsVC.h"
#import "../../Features/DeletedMessages/RYGDeletedMessagesViewController.h"
#import "../../Features/FollowRequests/RYGFollowRequestsViewController.h"
#import "../../Features/General/RYGCacheManager.h"
#import "../../Features/General/RYGChangelog.h"
#import "../../Features/Theme/RYGTheme.h"
#import "../../Gallery/RYGGalleryViewController.h"
#import "../../UI/Notification/RYGNotificationSettings.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"

NS_ASSUME_NONNULL_BEGIN

// Top-most VC walker. Skips a VC mid-dismiss so present: doesn't no-op behind
// the dismissal animation and eat the next tap.
static inline UIViewController * _Nullable rygTopVC(void) {
	UIViewController *top = nil;
	for (UIWindow *w in UIApplication.sharedApplication.windows) {
		if (!w.isKeyWindow) continue;
		top = w.rootViewController;
		while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
			top = top.presentedViewController;
		}
	}
	return top;
}

// Cross-section helpers. Declared once here so any section file can call
// [self <selector>] without importing the implementing file.
@interface RYGTweakSettings (SectionsHelpers)
+ (NSArray *)aboutNavSections;
+ (NSArray *)experimentalNavSections;
+ (NSDictionary *)enhancedDownloadsSection;
+ (NSArray *)advancedEncodingNavSections;
+ (RYGSetting *)experimentalEntryCell;
+ (RYGSetting *)actionIconNavCell;
+ (RYGSetting *)dateFormatNavCell;
+ (RYGSetting *)galleryAlbumNameCell;
+ (RYGSetting *)autoClearCacheMenuCell;
+ (RYGSetting *)preserveMessagesDBCell;
+ (RYGSetting *)autoCheckCacheSizeCell;
+ (RYGSetting *)clearCacheButtonCell;
+ (void)presentLocalizationExport;
+ (void)presentLocalizationImport;
+ (void)presentLocalizationReset;
+ (void)promptFakeCountForKey:(NSString *)key title:(NSString *)title;
+ (void)promptFakeTextForKey:(NSString *)key title:(NSString *)title;
+ (void)promptFakeValueForKey:(NSString *)key title:(NSString *)title placeholder:(NSString *)placeholder numeric:(BOOL)numeric;
@end

@interface RYGTweakSettings (Sections)
+ (RYGSetting *)generalNavCell;
+ (RYGSetting *)feedNavCell;
+ (RYGSetting *)storiesNavCell;
+ (RYGSetting *)reelsNavCell;
+ (RYGSetting *)messagesNavCell;
+ (RYGSetting *)instantsNavCell;
+ (RYGSetting *)profileNavCell;
+ (RYGSetting *)followIndicatorListsCell;
+ (RYGSetting *)followRequestsNavCell;
+ (RYGSetting *)interfaceNavCell;
+ (RYGSetting *)mediaSavingNavCell;
+ (RYGSetting *)confirmActionsNavCell;
+ (RYGSetting *)themeNavCell;
+ (RYGSetting *)backupNavCell;
+ (RYGSetting *)advancedNavCell;
+ (RYGSetting *)debugNavCell;
+ (RYGSetting *)aboutNavCell;
+ (RYGSetting *)instaPlusNavCell;
@end

NS_ASSUME_NONNULL_END
