// Per-tab settings cell builders live in SCISettings_<Tab>.m under this folder
// as categories on SCITweakSettings. TweakSettings.m's +sections stitches them.

#import "../TweakSettings.h"
#import "../SCISetting.h"
#import "../SCISymbol.h"
#import "../SCISettingsBackup.h"
#import "../SCIActionMenuConfigViewController.h"
#import "../SCIExcludedChatsViewController.h"
#import "../SCIExcludedStoryUsersViewController.h"
#import "../SCIEmbedDomainViewController.h"
#import "../SCIHomeShortcutConfigViewController.h"
#import "../../ActionButton/SCIActionCatalog.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "../../Features/StoriesAndMessages/SCIExcludedThreads.h"
#import "../../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import "../../Features/ChatBackground/SCIChatBgSettingsVC.h"
#import "../../Features/DeletedMessages/SCIDeletedMessagesViewController.h"
#import "../../Features/General/SCICacheManager.h"
#import "../../Features/General/SCIChangelog.h"
#import "../../Features/Theme/SCITheme.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../../UI/Notification/SCINotificationSettings.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../UI/SCIIconPicker.h"
#import "../../Utils.h"

NS_ASSUME_NONNULL_BEGIN

// Top-most VC walker. Skips a VC mid-dismiss so present: doesn't no-op behind
// the dismissal animation and eat the next tap.
static inline UIViewController * _Nullable sciTopVC(void) {
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
@interface SCITweakSettings (SectionsHelpers)
+ (NSArray *)aboutNavSections;
+ (NSArray *)experimentalNavSections;
+ (NSDictionary *)enhancedDownloadsSection;
+ (NSArray *)advancedEncodingNavSections;
+ (SCISetting *)experimentalEntryCell;
+ (SCISetting *)actionIconNavCell;
+ (SCISetting *)dateFormatNavCell;
+ (SCISetting *)galleryAlbumNameCell;
+ (SCISetting *)autoClearCacheMenuCell;
+ (SCISetting *)preserveMessagesDBCell;
+ (SCISetting *)autoCheckCacheSizeCell;
+ (SCISetting *)clearCacheButtonCell;
+ (void)presentLocalizationExport;
+ (void)presentLocalizationImport;
+ (void)presentLocalizationReset;
+ (void)promptFakeCountForKey:(NSString *)key title:(NSString *)title;
@end

@interface SCITweakSettings (Sections)
+ (SCISetting *)generalNavCell;
+ (SCISetting *)feedNavCell;
+ (SCISetting *)storiesNavCell;
+ (SCISetting *)reelsNavCell;
+ (SCISetting *)messagesNavCell;
+ (SCISetting *)profileNavCell;
+ (SCISetting *)interfaceNavCell;
+ (SCISetting *)mediaSavingNavCell;
+ (SCISetting *)confirmActionsNavCell;
+ (SCISetting *)themeNavCell;
+ (SCISetting *)backupNavCell;
+ (SCISetting *)advancedNavCell;
+ (SCISetting *)devNavCell;
+ (SCISetting *)debugNavCell;
+ (SCISetting *)aboutNavCell;
@end

NS_ASSUME_NONNULL_END
