#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

%group HideMetaAI

// Direct

// Meta AI button functionality on direct search bar
%hook IGDirectInboxViewController
- (void)searchBarMetaAIButtonTappedOnSearchBar:(id)arg1 {
	return;
}
%end

// AI agents in direct new message view
%hook IGDirectRecipientGenAIBotsResult
- (id)initWithGenAIBots:(id)arg1 lastFetchedTimestamp:(id)arg2 {
	return nil;
}
%end

// Meta AI in message composer
%hook IGDirectCommandSystemListViewController
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig;
	NSMutableArray *filteredObjs = nil;

	for (id obj in originalObjs) {
		BOOL shouldHide = NO;

		if ([obj isKindOfClass:%c(IGDirectCommandSystemViewModel)]) {
			IGDirectCommandSystemRow *cmdSystemRow = [(IGDirectCommandSystemViewModel *)obj row];
			IGDirectCommandSystemResult *command = MSHookIvar<IGDirectCommandSystemResult *>(cmdSystemRow, "_commandResult_command");

			// Meta AI
			if ([[command title] isEqualToString:@"Meta AI"]) shouldHide = YES;

			// Meta AI (Imagine)
			else if ([[command commandString] hasPrefix:@"/imagine"]) shouldHide = YES;
		}

		// Populate new objs array
		if (shouldHide) {
			if (!filteredObjs) {
				filteredObjs = [NSMutableArray arrayWithCapacity:originalObjs.count];
				NSUInteger idx = [originalObjs indexOfObjectIdenticalTo:obj];
				if (idx) [filteredObjs addObjectsFromArray:[originalObjs subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filteredObjs) [filteredObjs addObject:obj];
	}

	return filteredObjs ? filteredObjs.copy : originalObjs;
}
%end

// Suggested AI chats in direct inbox header
%hook IGDirectInboxNavigationHeaderView
- (id)initWithFrame:(CGRect)arg1
			  title:(id)arg2
		  titleView:(id)arg3
  directInboxConfig:(IGDirectInboxConfig *)config
		userSession:(id)arg5
	loggingDelegate:(id)arg6
{
	IGDirectInboxConfig *patched = [config copy];
	@try {
		[patched setValue:@NO forKey:@"shouldShowAIChatsEntrypointButton"];
	} @catch (...) {}

	return %orig(arg1, arg2, arg3, patched, arg5, arg6);
}
%end

// Meta AI "imagine" in media picker
%hook IGDirectMediaPickerViewController
- (id)initWithUserSession:(id)arg1
				   config:(IGDirectMediaPickerConfig *)config
			 capabilities:(id)arg3
		   threadMetadata:(id)arg4
			messageSender:(id)arg5
	threadAnalyticsLogger:(id)arg6
	 multimodalPerfLogger:(id)arg7
	 localSendSpeedLogger:(id)arg8
   sendAttributionFactory:(id)arg9
{
	IGDirectMediaPickerConfig *patched = [config copy];
	@try {
		[[patched valueForKey:@"galleryConfig"] setValue:@NO forKey:@"isImagineEntryPointEnabled"];
	} @catch (...) {}

	return %orig(arg1, patched, arg3, arg4, arg5, arg6, arg7, arg8, arg9);
}
%end

// Write with meta ai in message composer
%hook IGDirectComposer
- (id)initWithLayoutSpecProvider:(id)arg1
					 userSession:(id)arg2
				 userLauncherSet:(id)arg3
						  config:(IGDirectComposerConfig *)config
						   style:(id)arg5
							text:(id)arg6
{
	return %orig(arg1, arg2, arg3, [self patchConfig:config], arg5, arg6);
}

- (id)initWithLayoutSpecProvider:(id)arg1
					 userSession:(id)arg2
				 userLauncherSet:(id)arg3
						  config:(IGDirectComposerConfig *)config
						   style:(id)arg5
							text:(id)arg6
		   shouldUpdateModeLater:(BOOL)arg7
{
	return %orig(arg1, arg2, arg3, [self patchConfig:config], arg5, arg6, arg7);
}

- (id)_initializeWithLayoutSpecProvider:(id)arg1
							userSession:(id)arg2
						userLauncherSet:(id)arg3
								 config:(IGDirectComposerConfig *)config
								  style:(id)arg5
								   text:(id)arg6
				  shouldUpdateModeLater:(BOOL)arg7
{
	return %orig(arg1, arg2, arg3, [self patchConfig:config], arg5, arg6, arg7);
}

- (void)setConfig:(IGDirectComposerConfig *)config {
	%orig([self patchConfig:config]);
}

%new - (IGDirectComposerConfig *)patchConfig:(IGDirectComposerConfig *)config {
	IGDirectComposerConfig *patched = [config copy];

	// writeWithAIEnabled
	@try {
		[patched setValue:@NO forKey:@"writeWithAIEnabled"];
	} @catch (...) {}

	return patched;
}
%end

// Demangled name: IGAIRewrite.IGAIRewriteStoryRepliesPresenter
%hook _TtC11IGAIRewrite32IGAIRewriteStoryRepliesPresenter
- (BOOL)shouldShowAIRewriteButton:(id)arg1 input:(id)arg2 {
	return NO;
}
%end

// Direct sticker tray picker view
%hook IGStickerTrayListAdapterDataSource
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig;
	NSMutableArray *filteredObjs = nil;

	for (id obj in originalObjs) {
		BOOL shouldHide = [obj isKindOfClass:%c(IGDirectUnifiedComposerAIStickerModel)];

		// Populate new objs array
		if (shouldHide) {
			if (!filteredObjs) {
				filteredObjs = [NSMutableArray arrayWithCapacity:originalObjs.count];
				NSUInteger idx = [originalObjs indexOfObjectIdenticalTo:obj];
				if (idx) [filteredObjs addObjectsFromArray:[originalObjs subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filteredObjs) [filteredObjs addObject:obj];
	}

	return filteredObjs ? filteredObjs.copy : originalObjs;
}
%end

// Long press menu on messages
// Demangled name: IGDirectMessageMenuConfiguration.IGDirectMessageMenuConfiguration
%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration
+ (id)menuConfigurationWithEligibleOptions:(id)options
						  messageViewModel:(id)arg2
							   contentType:(id)arg3
								 isSticker:(_Bool)arg4
							isMusicSticker:(_Bool)arg5
						  directNuxManager:(id)arg6
					   sessionUserDefaults:(id)arg7
							   launcherSet:(id)arg8
							   userSession:(id)arg9
								tapHandler:(id)arg10
{
	// 31: Restyle
	// 41: Make AI image
	NSMutableArray *newOptions = nil;
	for (id option in options) {
		BOOL shouldHide = [option isEqual:@31] || [option isEqual:@41];

		if (shouldHide) {
			if (!newOptions) {
				newOptions = [NSMutableArray arrayWithCapacity:[options count]];
				NSUInteger idx = [options indexOfObjectIdenticalTo:option];
				if (idx) [newOptions addObjectsFromArray:[options subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (newOptions) [newOptions addObject:option];
	}

	return %orig(newOptions ?: options, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}
%end

// Expanded in-chat photo UI
// Demangled name: IGDirectAggregatedMediaViewerComponentsSwift.IGDirectAggregatedMediaViewerViewControllerTitleViewModelObject
%hook _TtC44IGDirectAggregatedMediaViewerComponentsSwift63IGDirectAggregatedMediaViewerViewControllerTitleViewModelObject
- (id)initWithAuthorProfileImage:(id)arg1
				  authorUsername:(id)arg2
					  canForward:(_Bool)arg3
						 canSave:(_Bool)arg4
				   canAddToStory:(_Bool)arg5
				canShowAIRestyle:(_Bool)arg6
					   canUnsend:(_Bool)arg7
					   canReport:(_Bool)arg8
				   displayConfig:(id)arg9
					   isPending:(_Bool)arg10
			 isMoreMenuListStyle:(_Bool)arg11
			 senderIsCurrentUser:(_Bool)arg12
			 shouldHideInfoViews:(_Bool)arg13
						subtitle:(id)arg14
					  entryPoint:(long long)arg15
					canTapAuthor:(_Bool)arg16
{
	return %orig(arg1, arg2, arg3, arg4, arg5, NO, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16);
}
%end

// AI generated DM channel themes
%hook IGDirectThreadThemePickerViewController
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig;
	NSMutableArray *filteredObjs = nil;

	for (id obj in originalObjs) {
		BOOL shouldHide = [obj isKindOfClass:%c(IGDirectThreadThemePickerOption)] && [[obj valueForKey:@"themeId"] isEqualToString:@"direct_ai_theme_creation"];

		// Populate new objs array
		if (shouldHide) {
			if (!filteredObjs) {
				filteredObjs = [NSMutableArray arrayWithCapacity:originalObjs.count];
				NSUInteger idx = [originalObjs indexOfObjectIdenticalTo:obj];
				if (idx) [filteredObjs addObjectsFromArray:[originalObjs subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filteredObjs) [filteredObjs addObject:obj];
	}

	return filteredObjs ? filteredObjs.copy : originalObjs;
}
%end

// "Click to summarize" pill under DM navigation bar
%hook IGDirectThreadViewMetaAISummaryFeatureController
- (id)initWithUserSession:(id)arg1 mutableStateProvider:(id)arg2 threadViewControllerFeatureDelegate:(id)arg3 presentingViewController:(id)arg4 {
	return nil;
}
%end

/////////////////////////////////////////////////////////////////////////////

// Explore

// Meta AI explore search summary
%hook IGDiscoveryListKitGQLDataSource
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig;
	NSMutableArray *filteredObjs = nil;

	for (id obj in originalObjs) {
		BOOL shouldHide = [obj isKindOfClass:%c(IGSearchMetaAIHCMModel)];

		// Populate new objs array
		if (shouldHide) {
			if (!filteredObjs) {
				filteredObjs = [NSMutableArray arrayWithCapacity:originalObjs.count];
				NSUInteger idx = [originalObjs indexOfObjectIdenticalTo:obj];
				if (idx) [filteredObjs addObjectsFromArray:[originalObjs subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filteredObjs) [filteredObjs addObject:obj];
	}

	return filteredObjs ? filteredObjs.copy : originalObjs;
}
%end

// Meta AI search bar ring button
%hook IGSearchBarDonutButton
- (void)didMoveToWindow {
	%orig;
	if (self.window) [self removeFromSuperview];
}
%end

/////////////////////////////////////////////////////////////////////////////

// Reels/Sundial

// Suggested AI searches in comment section
%hook IGCommentConfig
- (id)initWithUserSession:(id)session
commentThreadConfiguration:(IGCommentThreadConfiguration *)threadConfig
sponsoredSupportConfiguration:(id)supportConfig
		  CTAPresenterContext:(id)context
					replyText:(id)text
			  loggingDelegate:(id)loggingDelegate
	 presentingViewController:(id)vc
   childCommentThreadDelegate:(id)threadDelegate
{
	@try {
		[threadConfig setValue:@YES forKey:@"disableMetaAICarousel"];
	} @catch (...) {}

	return %orig(session, threadConfig, supportConfig, context, text, loggingDelegate, vc, threadDelegate);
}
%end

// Suggested AI searches in comment section (workaround if setting comment thread config fails)
%hook IGCommentThreadAICarousel
- (id)initWithLauncherSet:(id)arg1 hasSearchPrefix:(BOOL)arg2 {
	return nil;
}
%end

%hook _TtC34IGCommentThreadAICarouselPillSwift30IGCommentThreadAICarouselSwift
- (id)initWithLauncherSet:(id)arg1 hasSearchPrefix:(BOOL)arg2 {
	return nil;
}
%end

/////////////////////////////////////////////////////////////////////////////

// Story

// AI images "add to story" suggestion
// Demangled name: IGGalleryDestinationToolbar.IGGalleryDestinationToolbarView
%hook _TtC27IGGalleryDestinationToolbar31IGGalleryDestinationToolbarView
- (void)setTools:(id)tools {
	NSMutableArray *newTools = nil;

	for (id tool in tools) {
		BOOL shouldHide = [tool isEqual:@9] || [tool isEqual:@10] || [tool isEqual:@11];

		if (shouldHide) {
			if (!newTools) {
				newTools = [NSMutableArray arrayWithCapacity:[tools count]];
				NSUInteger idx = [tools indexOfObjectIdenticalTo:tool];
				if (idx) [newTools addObjectsFromArray:[tools subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (newTools) [newTools addObject:tool];
	}

	%orig(newTools ?: tools);
}
%end

// AI generated fonts in text entry
%hook IGCreationTextToolView
- (id)initWithMenuConfiguration:(unsigned long long)configuration userSession:(id)session creationEntryPoint:(long long)point isAIFontsEnabled:(_Bool)enabled genAINuxManager:(id)manager showFontBadge:(_Bool)badge {
	return %orig(configuration, session, point, NO, manager, badge);
}
%end

// Text rewrite in text entry
%hook IGStoryTextMentionLocationPickerView
- (id)initWithIsTextRewriteEnabled:(_Bool)arg1
			 isImageRewriteEnabled:(_Bool)arg2
	  isStackedToolSelectorEnabled:(_Bool)arg3
		  isMentionLocationVisible:(_Bool)arg4
		   isEnabledForFeedCaption:(_Bool)arg5
				  isFeedEntryPoint:(_Bool)arg6
{
	return %orig(NO, NO, arg3, arg4, arg5, arg6);
}
%end

// "Imagine background" in story editor vertical action bar
%hook _TtC17IGCreationOSSwift19IGCreationHeaderBar
- (void)setButtons:(id)buttons maxItems:(NSInteger)max {
	NSMutableArray *filteredObjs = nil;

	for (id obj in buttons) {
		BOOL shouldHide = NO;

		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		id buttonObject = [obj respondsToSelector:@selector(button)] ? [obj performSelector:@selector(button)] : nil;
		#pragma clang diagnostic pop
		IGCreationActionBarButton *button = [buttonObject isKindOfClass:UIButton.class] ? (IGCreationActionBarButton *)buttonObject : nil;
		if (button && [button.accessibilityIdentifier isEqualToString:@"contextual-background"]) shouldHide = YES;

		if (shouldHide) {
			if (!filteredObjs) {
				filteredObjs = [NSMutableArray arrayWithCapacity:[buttons count]];
				NSUInteger idx = [buttons indexOfObjectIdenticalTo:obj];
				if (idx) [filteredObjs addObjectsFromArray:[buttons subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filteredObjs) [filteredObjs addObject:obj];
	}

	%orig(filteredObjs ?: buttons, max);
}
%end

/////////////////////////////////////////////////////////////////////////////

// Other

// Meta AI-branded search bars
%hook IGSearchBar
- (id)initWithConfig:(IGSearchBarConfig *)config {
	return %orig([self sanitizePlaceholderForConfig:config]);
}

- (id)initWithConfig:(IGSearchBarConfig *)config userSession:(id)arg2 {
	return %orig([self sanitizePlaceholderForConfig:config], arg2);
}

- (void)setConfig:(IGSearchBarConfig *)config {
	%orig([self sanitizePlaceholderForConfig:config]);
}

%new - (IGSearchBarConfig *)sanitizePlaceholderForConfig:(IGSearchBarConfig *)config {
	NSString *placeholder = [config valueForKey:@"placeholder"];
	if (![placeholder containsString:@"Meta AI"]) return config;

	IGSearchBarConfig *patched = [config copy];

	// placeholder
	@try {
		[patched setValue:SCILocalized(@"Search") forKey:@"placeholder"];
	} @catch (...) {}

	// shouldAnimatePlaceholder
	@try {
		[patched setValue:@NO forKey:@"shouldAnimatePlaceholder"];
	} @catch (...) {}

	// leftIconStyle
	@try {
		[patched setValue:@0 forKey:@"leftIconStyle"];
	} @catch (...) {}

	// rightButtonStyle
	@try {
		[patched setValue:@0 forKey:@"rightButtonStyle"];
	} @catch (...) {}

	return patched;
}
%end

// Themed in-app buttons
%hook IGTapButton
- (void)didMoveToWindow {
	%orig;

	// Hide buttons that are associated with meta ai
	if (self.window && [self.accessibilityIdentifier containsString:@"meta_ai"]) {
		[self removeFromSuperview];
	}
}
%end

// Home feed meta ai button
%hook IGFloatingActionButton.IGFloatingActionButton
- (void)didMoveToSuperview {
	%orig;
	[self removeFromSuperview];
}
%end

// Native IGMetaAIInFeed.IGMetaAIInFeedUnitSectionController variant
// (Bloks variant is filtered at the model layer in HideFeedItems.xm).
%hook _TtC14IGMetaAIInFeed35IGMetaAIInFeedUnitSectionController
- (NSInteger)numberOfItems {
	return 0;
}

- (CGSize)sizeForItemAtIndex:(NSInteger)index {
	return CGSizeZero;
}
%end

// Share menu recipients
%hook IGDirectRecipientListViewController
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig;
	NSMutableArray *filteredObjs = nil;

	for (id obj in originalObjs) {
		BOOL shouldHide = NO;

		if ([obj isKindOfClass:%c(IGDirectRecipientCellViewModel)]) {
			// Meta AI (catch-all)
			shouldHide = [[[[obj recipient] threadName] lowercaseString] isEqualToString:@"meta ai"];
		}

		// Populate new objs array
		if (shouldHide) {
			if (!filteredObjs) {
				filteredObjs = [NSMutableArray arrayWithCapacity:originalObjs.count];
				NSUInteger idx = [originalObjs indexOfObjectIdenticalTo:obj];
				if (idx) [filteredObjs addObjectsFromArray:[originalObjs subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filteredObjs) [filteredObjs addObject:obj];
	}

	return filteredObjs ? filteredObjs.copy : originalObjs;
}
%end

%end

%ctor {
	if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
		%init(HideMetaAI);
	}
}
