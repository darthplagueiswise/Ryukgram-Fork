#import "TweakSettings.h"
#import "Sections/RYGSettingsSections.h"
#import "../RYGDefaults.h"
#import "../UI/RYGOptionSheet.h"
#import <objc/message.h>
#import "../UI/Notification/RYGNotificationSettings.h"
#import "RYGLinksSheet.h"
#import "RYGSettingsBackup.h"
#import "RYGFakeLocationSettingsVC.h"
#import "../Features/ProfileAnalyzer/RYGProfileAnalyzerViewController.h"
#import "../Features/DeletedMessages/RYGDeletedMessagesViewController.h"
#import "../Gallery/RYGGalleryViewController.h"
#import "../Features/StoriesArchive/RYGStoriesArchiveViewController.h"
#import "../Features/Feed/RYGHomeShortcutBadges.h"
#import "RYGExcludedChatsViewController.h"
#import "RYGHomeShortcutConfigViewController.h"
#import "../Features/StoriesAndMessages/RYGExcludedThreads.h"
#import "../Features/StoriesAndMessages/RYGExcludedStoryUsers.h"
#import "RYGExcludedStoryUsersViewController.h"
#import "RYGEmbedDomainViewController.h"
#import "RYGDateFormatPickerVC.h"
#import "RYGAppIconPickerViewController.h"
#import "../UI/RYGPopupChrome.h"
#import "../Features/ChatBackground/RYGChatBgSettingsVC.h"
#import "../Features/General/RYGCacheManager.h"
#import "../Features/General/RYGChangelog.h"
#import "../RYGFFmpeg.h"
#import "../Features/Experimental/RYGExperimentalGuard.h"
#import "../Features/Theme/RYGTheme.h"
#import "../Tweak.h"
#import "../ActionButton/RYGActionIcon.h"
#import "../ActionButton/RYGActionCatalog.h"
#import "RYGActionMenuConfigViewController.h"
#import "../UI/RYGActionIconListViewController.h"
#import "RYGSettingsViewController.h"
#import "../Lock/RYGLockSettingsBuilder.h"
#import "../Lock/RYGLockGate.h"
#import "../Lock/RYGLockGroups.h"
#import "../UI/RYGFeatureIcons.h"
#import <objc/runtime.h>

@implementation RYGTweakSettings

// MARK: - Sections

+ (NSArray *)sections {
	NSMutableArray *sections = [NSMutableArray array];

	if ([RYGUtils allTweakOptionsDisabled]) {
		RYGSetting *warn = [RYGSetting buttonCellWithTitle:RYGLocalized(@"All tweak options are disabled")
												  subtitle:RYGLocalized(@"Tap to re-enable everything")
													  icon:[RYGSymbol symbolWithIGName:@"warning" fallback:@"exclamationmark.triangle.fill"]
													action:^{
			[RYGUtils setPref:@(NO) forKey:@"ryg_disable_all"];
			[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
			[RYGUtils showRestartConfirmation];
		}];
		warn.titleColor = [UIColor systemRedColor];
		[sections addObject:@{ @"header": @"", @"rows": @[warn] }];
	}

	[sections addObjectsFromArray:@[
		@{
			@"header": @"",
			@"rows": @[
				({
					RYGSetting *s = [RYGSetting buttonCellWithTitle:@"RyukGram"
														   subtitle:[NSString stringWithFormat:RYGLocalized(@"%@ — GitHub, Telegram, Donate"), RYGVersionString]
															   icon:nil
															 action:^{
						UIWindow *win = nil;
						for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) { win = w; break; }
						UIViewController *top = win.rootViewController;
						while (top.presentedViewController) top = top.presentedViewController;
						[RYGLinksSheet presentFrom:top];
					}];
					s.bundleImageName = @"ryukgram";
					s.titleColor = [UIColor labelColor];
					s;
				})
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				[self generalNavCell],
				[self feedNavCell],
				[self storiesNavCell],
				[self reelsNavCell],
				[self messagesNavCell],
				[self instantsNavCell],
				[self profileNavCell],
				({ RYGSetting *s = [self interfaceNavCell]; s.whatsNewID = @"ui_interface"; s; }),
				[self mediaSavingNavCell],
				[self confirmActionsNavCell]
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				({
					RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Profile Analyzer")
										subtitle:@""
											icon:[RYGFeatureIcons profileAnalyzer]
										  action:^{
						UIWindow *kw = nil;
						for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) { kw = w; break; }
						UIViewController *top = kw.rootViewController;
						while (top.presentedViewController) top = top.presentedViewController;
						[RYGLockGate runGated:RYGLockGroupProfileAnalyzer from:top then:^{
							UIViewController *t = kw.rootViewController;
							while (t.presentedViewController) t = t.presentedViewController;
							RYGProfileAnalyzerViewController *pa = [[RYGProfileAnalyzerViewController alloc] init];
							if ([t isKindOfClass:[UINavigationController class]]) [(UINavigationController *)t pushViewController:pa animated:YES];
							else if (t.navigationController) [t.navigationController pushViewController:pa animated:YES];
						}];
					}];
					s.whatsNewID = @"ui_profileanalyzer";
					s;
				}),
				({
					RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Stories archive")
										subtitle:@""
											icon:[RYGSymbol symbolWithIGName:@"ig_icon_story_highlight_pano_outline_24" fallback:@"clock.arrow.circlepath"]
									 navSections:@[
										@{
											@"header": RYGLocalized(@"Archiving"),
											@"footer": RYGLocalized(@"Saves each story you post, with its photo or video, kept separately for each account."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Enable stories archive") subtitle:RYGLocalized(@"Save your stories before they expire") defaultsKey:@"ryg_stories_archive" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Viewers"),
											@"footer": RYGLocalized(@"A story's viewer list keeps growing for its full day, then Instagram serves it for one more. Auto-update grabs the final list once a story is a day old, so the counts you keep are complete."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Save and update viewers") subtitle:RYGLocalized(@"Keep each story's viewers and likers, refreshed to the final list") defaultsKey:@"ryg_stories_archive_auto_viewers"],
												[RYGSetting menuCellWithTitle:RYGLocalized(@"Update viewers") subtitle:RYGLocalized(@"How often to refresh viewers for stories still live") menu:[self menus][@"stories_archive_viewer_refresh"]],
											]
										},
										@{
											@"header": RYGLocalized(@"Pinned viewers"),
											@"footer": RYGLocalized(@"Get notified when a pinned viewer sees or likes your story. Pin viewers and manage the list from the viewer settings."),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Notify me about pinned viewers") subtitle:RYGLocalized(@"A heads-up when a pinned viewer sees or likes your story") defaultsKey:@"ryg_stories_archive_notify_pinned"],
												[RYGSetting buttonCellWithTitle:RYGLocalized(@"Viewer list & pins")
																	   subtitle:RYGLocalized(@"Turn on the viewer list and manage pinned viewers")
																		   icon:[RYGSymbol symbolWithIGName:@"ig_icon_edit_list_outline_24" fallback:@"pin.fill"]
																		 action:^{
													UIWindow *kw = nil;
													for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) { kw = w; break; }
													if (kw) [RYGUtils showSettingsVC:kw atTopLevelEntry:RYGLocalized(@"Stories") scrollToSection:RYGLocalized(@"Viewers list")];
												}],
											]
										},
										@{
											@"header": @"",
											@"rows": @[
												({ RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Open archive")
																	   subtitle:@""
																		   icon:[RYGSymbol symbolWithIGName:@"archive_outline_20" fallback:@"square.grid.2x2"]
																		 action:^{ [RYGStoriesArchiveViewController presentFrom:nil]; }];
												   s.badgeCount = ^NSInteger{ return [RYGHomeShortcutBadges countForActionID:@"stories_archive"]; };
												   s; }),
											]
										},
									 ]];
					s.whatsNewID = @"ui_storiesarchive";
					s;
				}),
				({ RYGSetting *s = [self followRequestsNavCell]; s.whatsNewID = @"ui_followrequests"; s; }),
				({
					RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Gallery")
									   subtitle:@""
										   icon:[RYGFeatureIcons gallery]
										 action:^{ [RYGGalleryViewController presentGallery]; }];
					s.whatsNewID = @"ui_gallery";
					s;
				}),
				[RYGSetting navigationCellWithTitle:RYGLocalized(@"Fake location")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"location_arrow" fallback:@"location.fill.viewfinder"]
									 viewController:[[RYGFakeLocationSettingsVC alloc] init]],
				[self themeNavCell],
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				({ RYGSetting *s = [RYGLockSettingsBuilder topLevelNavCell]; s.whatsNewID = @"ui_lock"; s; }),
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				({ RYGSetting *s = [self backupNavCell]; s.whatsNewID = @"ui_backup"; s; }),
				[self advancedNavCell],
				[self debugNavCell]
			]
		},
		@{
			@"header": @"",
			@"rows": @[
				[self aboutNavCell]
			]
		},
	]];

	return sections;
}

// MARK: - Action button icon

+ (RYGSetting *)actionIconNavCell {
	RYGSetting *cell = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Action button icon")
									  subtitle:RYGLocalized(@"Shared icon, or override per button")
										  icon:[RYGSymbol symbolWithIGName:@"more_horizontal" fallback:@"ellipsis.circle"]
								viewController:[RYGActionIconListViewController new]];
	cell.whatsNewID = @"ui_actionicon";
	return cell;
}

// MARK: - Date format

+ (RYGSetting *)dateFormatNavCell {
	RYGSetting *cell = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Date format")
												 subtitle:@""
													 icon:nil
										   viewController:[[RYGDateFormatPickerVC alloc] init]];
	cell.dynamicTitle = ^{
		NSString *ex = [RYGDateFormatPickerVC currentFormatExample];
		return [NSString stringWithFormat:RYGLocalized(@"Date format — %@"), ex];
	};
	cell.whatsNewID = @"ui_dateformat";
	return cell;
}

// MARK: - Title

+ (NSString *)title {
	return RYGLocalized(@"settings.title");
}

@end
