#import "RYGSettingsSections.h"

@implementation RYGTweakSettings (Section_General)

+ (RYGSetting *)generalNavCell {
	return [RYGSetting navigationCellWithTitle:RYGLocalized(@"General")
										   subtitle:@""
											   icon:[RYGSymbol symbolWithIGName:@"settings" fallback:@"gear"]
										navSections:@[@{
											@"header": @"",
											@"rows": @[
												[RYGSetting navigationCellWithTitle:RYGLocalized(@"Hide ads")
												subtitle:RYGLocalized(@"Choose which surfaces hide ads")
													icon:nil
											 navSections:@[@{
												@"header": @"",
												@"footer": RYGLocalized(@"Master switch. When off, all per-surface toggles below are ignored."),
												@"rows": @[
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide ads") subtitle:RYGLocalized(@"Removes ads across enabled surfaces") defaultsKey:@"hide_ads"],
												]
											},
											@{
												@"header": RYGLocalized(@"Surfaces"),
												@"rows": @[
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Feed") subtitle:RYGLocalized(@"Sponsored posts in main, contextual, video, and chaining feeds") defaultsKey:@"hide_ads_feed"],
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Stories") subtitle:RYGLocalized(@"Story ads and sponsored entries in the story tray") defaultsKey:@"hide_ads_stories"],
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Reels") subtitle:RYGLocalized(@"Sponsored reels in the sundial feed") defaultsKey:@"hide_ads_reels"],
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Explore & search") subtitle:RYGLocalized(@"Sponsored posts on the explore grid") defaultsKey:@"hide_ads_explore"],
													[RYGSetting switchCellWithTitle:RYGLocalized(@"Shopping") subtitle:RYGLocalized(@"Commerce carousels in comments and shoppable CTAs on reels") defaultsKey:@"hide_ads_shopping"],
												]
											}]],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide Meta AI") subtitle:RYGLocalized(@"Strips the Meta AI buttons and entry points from the app") defaultsKey:@"hide_meta_ai" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide metrics") subtitle:RYGLocalized(@"Hides like/comment/share counts on posts and reels") defaultsKey:@"hide_metrics"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Do not save recent searches") subtitle:RYGLocalized(@"Stops search bars from saving your recent searches") defaultsKey:@"no_recent_searches"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Open link from clipboard") subtitle:RYGLocalized(@"Long-press the search tab to open a copied Instagram link") defaultsKey:@"paste_link_from_search"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Copy description") subtitle:RYGLocalized(@"Long press a caption to copy its text") defaultsKey:@"copy_description"],
											]
										},
										@{
											@"header": RYGLocalized(@"Instagram Plus"),
											@"footer": RYGLocalized(@"Turn on Instagram's paid subscriber features inside the app."),
											@"rows": @[
												[self instaPlusNavCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Date format"),
											@"footer": RYGLocalized(@"Replace IG's relative timestamps (\"3d ago\") with a custom format. Toggle which surfaces it applies to inside the picker."),
											@"rows": @[
												[self dateFormatNavCell],
											]
										},
										@{
											@"header": RYGLocalized(@"Browser"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Open links in external browser") subtitle:RYGLocalized(@"Opens links in Safari instead of Instagram's in-app browser") defaultsKey:@"open_links_external"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Strip tracking from links") subtitle:RYGLocalized(@"Removes Instagram tracking wrappers (l.instagram.com) and UTM/fbclid params from URLs") defaultsKey:@"strip_browser_tracking"],
											]
										},
										@{
											@"header": RYGLocalized(@"Sharing"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Replace domain in shared links") subtitle:RYGLocalized(@"Rewrites copied/shared links to use an embed-friendly domain for previews in Discord, Telegram, etc.") defaultsKey:@"embed_links"],
												({
													RYGSetting *s = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Embed domain")
																	   subtitle:@""
																		   icon:nil
																		 action:^(void) {
														UIWindow *win = nil;
														for (UIWindow *w in [UIApplication sharedApplication].windows)
															if (w.isKeyWindow) { win = w; break; }
														UIViewController *top = win.rootViewController;
														while (top.presentedViewController) top = top.presentedViewController;
														if ([top isKindOfClass:[UINavigationController class]])
															[(UINavigationController *)top pushViewController:[RYGEmbedDomainViewController new] animated:YES];
														else if (top.navigationController)
															[top.navigationController pushViewController:[RYGEmbedDomainViewController new] animated:YES];
													}];
													s.dynamicTitle = ^{ return [NSString stringWithFormat:RYGLocalized(@"Embed domain: %@"), [RYGUtils getStringPref:@"embed_link_domain"] ?: @"kkinstagram.com"]; };
													s;
												}),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Strip tracking params") subtitle:RYGLocalized(@"Removes igsh, utm_source, and other tracking parameters from shared links") defaultsKey:@"strip_tracking_params"],
											]
										},
										@{
											@"header": RYGLocalized(@"Audio page"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Download audio") subtitle:RYGLocalized(@"Adds a download button next to share/save on the reels audio page") defaultsKey:@"audio_page_download"],
											]
										},
										@{
											@"header": RYGLocalized(@"Comments"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Copy comment text") subtitle:RYGLocalized(@"Adds a copy option to the comment long-press menu") defaultsKey:@"copy_comment"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Download GIF & image comments") subtitle:RYGLocalized(@"Adds download, copy and expand options to GIF and image comments") defaultsKey:@"download_gif_comment"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Custom GIF in comments") subtitle:RYGLocalized(@"Long-press the GIF button to paste any Giphy URL") defaultsKey:@"custom_gif_comment"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Favorite GIFs") subtitle:RYGLocalized(@"Long-press a GIF in the picker to pin it — favorites show first") defaultsKey:@"gif_favorites_enabled"],
											]
										},
										@{
											@"header": RYGLocalized(@"Focus/distractions"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested users") subtitle:RYGLocalized(@"Removes suggested accounts to follow outside the feed") defaultsKey:@"no_suggested_users" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"No suggested chats") subtitle:RYGLocalized(@"Removes suggested broadcast channels from your inbox") defaultsKey:@"no_suggested_chats"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide DM search suggestions") subtitle:RYGLocalized(@"Removes suggested accounts and channels from direct message search") defaultsKey:@"no_dm_search_suggestions"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Skip sensitive content covers") subtitle:RYGLocalized(@"Auto-reveals sensitive media") defaultsKey:@"skip_sensitive_content"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Block surveys") subtitle:RYGLocalized(@"Stops Instagram's in-app surveys and feedback prompts") defaultsKey:@"suppress_surveys" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Search & Explore"),
											@"footer": RYGLocalized(@"Stat pills on the posts and reels in search and explore. Open Card details to pick which stats show, reorder them, then apply."),
											@"rows": @[
												({ RYGSetting *s = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Card details")
																		   subtitle:RYGLocalized(@"Views, likes, comments, shares, reposts, date")
																			   icon:nil
																	 viewController:[RYGSearchCardDetailsViewController new]];
												   s.whatsNewID = @"ui_searchcard"; s; }),
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide explore posts grid") subtitle:RYGLocalized(@"Removes the suggested posts grid on the explore tab") defaultsKey:@"hide_explore_grid" requiresRestart:YES],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Hide trending searches") subtitle:RYGLocalized(@"Removes trending searches under the explore search bar") defaultsKey:@"hide_trending_searches" requiresRestart:YES],
											]
										},
										@{
											@"header": RYGLocalized(@"Live"),
											@"rows": @[
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Anonymous live viewing") subtitle:RYGLocalized(@"Blocks the viewer-count heartbeat so the broadcaster doesn't see you — you also won't see the viewer count") defaultsKey:@"live_anonymous_view"],
												[RYGSetting switchCellWithTitle:RYGLocalized(@"Toggle live comments") subtitle:RYGLocalized(@"Long-press the heart button in a live to hide or show the comments") defaultsKey:@"live_hide_comments"],
											]
										},
										]
				];
}

@end
