#import "RYGSettingsBackup.h"
#import "TweakSettings.h"
#import "RYGSetting.h"
#import "../Utils.h"
#import "../Tweak.h"
#import "../RYGArchive.h"
#import "../RYGTempFiles.h"
#import "../RYGAccountScopedDefaults.h"
#import "../RYGAccountRegistry.h"
#import "../Features/ProfileAnalyzer/RYGProfileAnalyzerStorage.h"
#import "../Features/DeletedMessages/RYGDeletedMessagesStorage.h"
#import "../Features/ReadReceipts/RYGReadReceiptStorage.h"
#import "../Features/FollowRequests/RYGFollowRequestStorage.h"
#import "../Features/CallRecordings/RYGCallRecordingStorage.h"
#import "../Features/StoriesArchive/RYGStoriesArchiveStore.h"
#import "../Features/ChatBackground/RYGChatBackgroundManager.h"
#import "../Features/ExpFlags/RYGMobileConfig.h"
#import "../Gallery/RYGGalleryPaths.h"
#import "../Gallery/RYGGalleryCoreDataStack.h"
#import "../Downloader/RYGDownloadHistory.h"
#import "../Downloader/RYGDownloadCenter.h"
#import "../Downloader/RYGDownloadLedger.h"
#import "RYGBackupScopePickerVC.h"
#import "RYGBackupCrypto.h"
#import "RYGStorageUsage.h"
#import "../UI/RYGFeatureIcons.h"
#import <objc/runtime.h>

// Bits 0-6 are the fixed categories; each feature-data module claims its own bit
// from kRYGFeatureBitBase by its +featureDataModules index, so a new store is
// scopable with no other code change.
typedef NS_OPTIONS(NSInteger, RYGBackupCat) {
	RYGBackupCatSettings        = 1 << 0,
	RYGBackupCatFilters         = 1 << 1,
	RYGBackupCatHiddenLocked    = 1 << 2,
	RYGBackupCatAnalyzer        = 1 << 3,
	RYGBackupCatGallery         = 1 << 4,
	RYGBackupCatChatBackgrounds = 1 << 5,
	RYGBackupCatDeletedMessages = 1 << 6,
	RYGBackupCatStoriesArchive  = 1 << 7,
};

static const NSInteger kRYGFeatureBitBase = 8;

static const RYGBackupCat RYGBackupCatAllFixed =
	RYGBackupCatSettings | RYGBackupCatFilters | RYGBackupCatHiddenLocked | RYGBackupCatAnalyzer |
	RYGBackupCatGallery | RYGBackupCatChatBackgrounds | RYGBackupCatDeletedMessages | RYGBackupCatStoriesArchive;

static NSString *const kArcGallery        = @"files/gallery";
static NSString *const kArcChatBg         = @"files/chat_backgrounds";
static NSString *const kArcDeleted        = @"files/deleted_messages";
static NSString *const kArcStoriesArchive = @"files/stories_archive";
static NSString *const kArcFeatureData    = @"files/feature_data";

#pragma mark - Small helpers

static BOOL rygNonEmpty(id v) {
	if ([v isKindOfClass:NSArray.class]) return [(NSArray *)v count] > 0;
	if ([v isKindOfClass:NSDictionary.class]) return [(NSDictionary *)v count] > 0;
	if ([v isKindOfClass:NSString.class]) return [(NSString *)v length] > 0;
	return v != nil;
}

static BOOL rygValidJSON(id v) {
	return v && [NSJSONSerialization isValidJSONObject:@{ @"v": v }];
}

static NSString *rygDocsSub(NSString *sub) {
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	return [docs stringByAppendingPathComponent:sub];
}

static NSString *rygGalleryDir(void) { return [RYGGalleryPaths galleryDirectory]; }
static NSString *rygDeletedDir(void) { return [RYGDeletedMessagesStorage storageDirectory]; }
static NSString *rygStoriesArchiveDir(void) { return [RYGStoriesArchiveStore storageDirectory]; }
static NSString *rygChatBgDir(void) {
	NSString *p = [[RYGChatBackgroundManager shared] assetsDirectoryURL].path;
	return p.length ? p : rygDocsSub(@"RyukGram/ChatBackgrounds");
}

static void rygDirStats(NSString *dir, NSUInteger *outCount, unsigned long long *outBytes) {
	NSUInteger count = 0; unsigned long long bytes = 0;
	NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
	for (__unused NSString *rel in en) {
		if ([en.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) {
			count++;
			bytes += en.fileAttributes.fileSize;
		}
	}
	if (outCount) *outCount = count;
	if (outBytes) *outBytes = bytes;
}

static NSString *rygHumanSize(unsigned long long bytes) {
	return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

#pragma mark - Per-account file layout

// A nil `pks` filter always means "every account" — never "none".
static NSString *rygPKOwningRelativePath(NSString *rel) {
	return [RYGStorageUsage accountPKForRelativePath:rel];
}

static NSSet<NSString *> *rygPKsInDir(NSString *dir) {
	NSMutableSet *pks = [NSMutableSet set];
	for (NSString *rel in [[NSFileManager defaultManager] enumeratorAtPath:dir]) {
		NSString *pk = rygPKOwningRelativePath(rel);
		if (pk.length) [pks addObject:pk];
	}
	return pks;
}

static void rygDirStatsForPKs(NSString *dir, NSSet<NSString *> *pks, NSUInteger *outCount, unsigned long long *outBytes) {
	if (!pks) { rygDirStats(dir, outCount, outBytes); return; }
	NSUInteger count = 0; unsigned long long bytes = 0;
	NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
	for (NSString *rel in en) {
		if (![en.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) continue;
		NSString *pk = rygPKOwningRelativePath(rel);
		if (!pk.length || ![pks containsObject:pk]) continue;
		count++;
		bytes += en.fileAttributes.fileSize;
	}
	if (outCount) *outCount = count;
	if (outBytes) *outBytes = bytes;
}

// A temp copy of just the picked accounts' files, so archiver and merge blocks
// keep working on a plain directory.
static NSString *rygStagedDirForPKs(NSString *dir, NSSet<NSString *> *pks) {
	if (!pks) return dir;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSURL *staged = [RYGTempFiles claimWithExt:@"dir" ttl:900 tag:@"acct"];
	[fm removeItemAtURL:staged error:nil];
	[fm createDirectoryAtPath:staged.path withIntermediateDirectories:YES attributes:nil error:nil];

	NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
	for (NSString *rel in en) {
		if (![en.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) continue;
		NSString *pk = rygPKOwningRelativePath(rel);
		if (!pk.length || ![pks containsObject:pk]) continue;
		NSString *dst = [staged.path stringByAppendingPathComponent:rel];
		[fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
		[fm copyItemAtPath:[dir stringByAppendingPathComponent:rel] toPath:dst error:nil];
	}
	return staged.path;
}

static void rygRemoveFilesForPKs(NSString *dir, NSSet<NSString *> *pks) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableArray<NSString *> *victims = [NSMutableArray array];
	for (NSString *rel in [fm enumeratorAtPath:dir]) {
		NSString *pk = rygPKOwningRelativePath(rel);
		if (pk.length && (!pks || [pks containsObject:pk])) [victims addObject:rel];
	}
	for (NSString *rel in victims) [fm removeItemAtPath:[dir stringByAppendingPathComponent:rel] error:nil];
}

static NSSet<NSString *> *rygIntersect(NSSet *set, NSSet *filter) {
	if (!filter) return set;
	NSMutableSet *out = [set mutableCopy];
	[out intersectSet:filter];
	return out;
}

#pragma mark - Generic merge

// Stable identity for list elements so a re-import doesn't duplicate the same logical item.
static id rygElementIdentity(id v) {
	if (![v isKindOfClass:NSDictionary.class]) return v;
	for (NSString *k in @[ @"thread_id", @"threadId", @"message_id", @"messageId",
						   @"pk", @"user_id", @"userId", @"user_pk", @"id", @"identifier" ]) {
		id idv = ((NSDictionary *)v)[k];
		if ([idv isKindOfClass:NSString.class] || [idv isKindOfClass:NSNumber.class])
			return [NSString stringWithFormat:@"%@:%@", k, idv];
	}
	return v; // no recognizable id — whole-value equality
}

// Merge semantics: arrays union (local order first), dicts merge recursively,
// scalars / mismatched types — the backup's value wins.
static id rygMergedValue(id local, id imported) {
	if (!rygNonEmpty(local)) return imported;
	if (!rygNonEmpty(imported)) return local;
	if ([local isKindOfClass:NSArray.class] && [imported isKindOfClass:NSArray.class]) {
		NSMutableArray *out = [local mutableCopy];
		NSMutableSet *seen = [NSMutableSet set];
		for (id v in (NSArray *)local) [seen addObject:rygElementIdentity(v)];
		for (id v in (NSArray *)imported) {
			id key = rygElementIdentity(v);
			if ([seen containsObject:key]) continue;
			[seen addObject:key];
			[out addObject:v];
		}
		return out;
	}
	if ([local isKindOfClass:NSDictionary.class] && [imported isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *out = [local mutableCopy];
		for (id k in (NSDictionary *)imported) out[k] = rygMergedValue(out[k], ((NSDictionary *)imported)[k]);
		return out;
	}
	return imported;
}

@interface RYGSettingsBackup ()
+ (void)showError:(NSString *)message;
+ (void)showSuccessHUD:(NSString *)message;
+ (void)presentApplyConfirmationForData:(NSData *)data;
+ (void)pickFromFiles;
@end

@interface RYGBackupHelper : NSObject <UIDocumentPickerDelegate>
@property (nonatomic) BOOL expectingExportPick;
// Bundle export's loading pill — carried through to success on save.
@property (nonatomic, strong) RYGNotificationHandle *exportHandle;
@end

@implementation RYGBackupHelper

+ (instancetype)shared {
	static RYGBackupHelper *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [RYGBackupHelper new]; });
	return s;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (self.expectingExportPick) {
		self.expectingExportPick = NO;
		if (self.exportHandle) { [self.exportHandle success:RYGLocalized(@"Backup exported")]; self.exportHandle = nil; }
		else [RYGSettingsBackup showSuccessHUD:RYGLocalized(@"Backup exported")];
		return;
	}

	NSURL *url = urls.firstObject;
	if (!url) return;

	BOOL access = [url startAccessingSecurityScopedResource];
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (access) [url stopAccessingSecurityScopedResource];

	if (!data) {
		[RYGSettingsBackup showError:RYGLocalized(@"Could not read file.")];
		return;
	}

	[RYGSettingsBackup presentApplyConfirmationForData:data];
}

- (void)documentPickerWasCancelled:(__unused UIDocumentPickerViewController *)controller {
	self.expectingExportPick = NO;
	[self.exportHandle dismiss];
	self.exportHandle = nil;
}

@end

@implementation RYGSettingsBackup

#pragma mark - Key groups

+ (NSArray<NSString *> *)filterBaseKeys {
	return @[ @"excluded_threads", @"included_threads", @"excluded_story_users", @"included_story_users" ];
}

+ (NSArray<NSString *> *)hiddenLockedAccountKeys {
	return @[ @"hidden_chats", @"lock_chats_locked_entries", @"share_sheet_pinned_thread_ids", @"story_pinned_viewers" ];
}

+ (NSString *)hiddenLockedGlobalKey { return @"lock_chats_appearance_overrides"; }

+ (NSArray<NSString *> *)chatBgAccountKeys {
	return @[ @"chat_bg_default_asset", @"chat_bg_thread_map", @"chat_bg_thread_meta" ];
}

+ (NSArray<NSString *> *)chatBgGlobalKeys {
	return @[ @"chat_bg_library", @"chat_bg_per_image" ];
}

+ (NSString *)galleryFoldersKey { return @"gallery_folders"; }

// One entry per file-backed feature store, all exported under the "Feature data"
// category. A new store joins backup/restore/reset by adding a row here; its prefs
// are kept out of the portable Settings payload. `reset`/`merge`/`postImport` blocks
// are optional (fall back to dir removal / file-level copy-missing). `accountScoped` opts the
// store into the account filter; `resetPK` wipes one account, else the generic
// "<pk>.*" sweep is used.
+ (NSArray<NSDictionary *> *)featureDataModules {
	return @[
		@{
			@"id": @"read_receipts",
			@"title": RYGLocalized(@"Read receipts log"),
			@"prefs": @[ @"activity_read_mode", @"read_receipts_log_groups" ],
			@"dir": [RYGReadReceiptStorage storageDirectory],
			@"accountScoped": @YES,
			@"reset": [^{ [RYGReadReceiptStorage resetAll]; } copy],
			@"resetPK": [^(NSString *pk) { [RYGReadReceiptStorage resetForOwnerPK:pk]; } copy],
			@"merge": [^(NSString *extracted) { [RYGReadReceiptStorage mergeImportedStoreAtPath:extracted]; } copy],
		},
		@{
			@"id": @"follow_requests",
			@"title": RYGLocalized(@"Follow requests log"),
			@"prefs": @[ @"follow_requests_enabled", @"follow_requests_track_outgoing", @"follow_requests_track_incoming", @"follow_requests_check_interval", @"follow_requests_notify_accepted", @"follow_requests_notify_rejected", @"follow_requests_notify_received", @"follow_requests_notify_withdrawn" ],
			@"dir": [RYGFollowRequestStorage storageDirectory],
			@"accountScoped": @YES,
			@"reset": [^{ [RYGFollowRequestStorage resetAll]; } copy],
			@"resetPK": [^(NSString *pk) { [RYGFollowRequestStorage resetForOwnerPK:pk]; } copy],
			@"merge": [^(NSString *extracted) { [RYGFollowRequestStorage mergeImportedStoreAtPath:extracted]; } copy],
		},
		@{
			@"id": @"call_recordings",
			@"title": RYGLocalized(@"Call recordings"),
			@"prefs": @[ @"call_recordings_enabled", @"call_recordings_auto", @"call_recordings_audio", @"call_recordings_video", @"call_recordings_self_cam", @"call_recordings_pip_full", @"call_recordings_pip_x", @"call_recordings_pip_y", @"call_recordings_pip_size", @"call_recordings_ghost_mute", @"call_recordings_sync_gallery", @"call_recordings_retention" ],
			@"dir": [RYGCallRecordingStorage storageDirectory],
			@"accountScoped": @YES,
			@"reset": [^{ [RYGCallRecordingStorage resetAll]; } copy],
			@"resetPK": [^(NSString *pk) { [RYGCallRecordingStorage resetForOwnerPK:pk]; } copy],
			@"merge": [^(NSString *extracted) { [RYGCallRecordingStorage mergeImportedStoreAtPath:extracted]; } copy],
		},
		@{
			@"id": @"instants_auto_save",
			@"title": RYGLocalized(@"Auto-saved instants log"),
			@"prefs": @[],
			@"dir": [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"RyukGram/InstantsAutoSave"],
		},
		@{
			@"id": @"download_history",
			@"title": RYGLocalized(@"Download history"),
			@"prefs": @[ @"dl_history_retention", @"dl_max_concurrent", @"dl_auto_retry", @"dl_auto_retry_count" ],
			@"dir": [RYGDownloadHistory storageDirectory],
			@"reset": [^{ [[RYGDownloadCenter shared] clearHistory]; } copy],
		},
		@{
			@"id": @"duplicate_downloads",
			@"title": RYGLocalized(@"Duplicate download list"),
			@"prefs": @[ @"dl_duplicate_check" ],
			@"dir": [RYGDownloadLedger storageDirectory],
			@"reset": [^{ [RYGDownloadLedger clearAll]; } copy],
			@"merge": [^(NSString *extracted) { [RYGDownloadLedger mergeImportedStoreAtPath:extracted]; } copy],
		},
		@{
			@"id": @"mobile_config",
			@"title": RYGLocalized(@"MobileConfig overrides"),
			@"prefs": @[],
			@"dir": [RYGMobileConfig storageDirectory],
			@"reset": [^{ [RYGMobileConfig resetStore]; } copy],
			@"merge": [^(NSString *extracted) { [RYGMobileConfig mergeImportedStoreAtPath:extracted]; } copy],
			@"postImport": [^{ [RYGMobileConfig reloadStoreFromDisk]; [RYGSettingsBackup noteMobileConfigImport]; } copy],
		},
	];
}

// Restoring overrides never flips the master switch, so say so when it's off.
+ (void)noteMobileConfigImport {
	if ([RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		RYGNotifyInfo(RYG_NOTIF_BACKUP, RYGLocalized(@"MobileConfig overrides"),
					  RYGLocalized(@"Turn on the browser first, then restart Instagram"));
	});
}

#pragma mark - Feature-data module bits

+ (NSInteger)bitForFeatureIndex:(NSUInteger)i { return (NSInteger)1 << (kRYGFeatureBitBase + (NSInteger)i); }

+ (NSInteger)featureDataMask {
	NSInteger m = 0;
	NSUInteger n = [self featureDataModules].count;
	for (NSUInteger i = 0; i < n; i++) m |= [self bitForFeatureIndex:i];
	return m;
}

+ (NSInteger)allScopeMask { return (NSInteger)RYGBackupCatAllFixed | [self featureDataMask]; }

// (module, bit) pairs, so callers iterate scoped modules without re-deriving indices.
+ (void)enumerateFeatureModules:(void (^)(NSDictionary *mod, NSInteger bit))block {
	NSArray *mods = [self featureDataModules];
	for (NSUInteger i = 0; i < mods.count; i++) block(mods[i], [self bitForFeatureIndex:i]);
}

// Keys kept out of the portable "Settings" payload: account-scoped ids/state
// (own categories), file-backed refs, the passcode hash, runtime markers.
+ (NSSet<NSString *> *)settingsExcludedKeys {
	NSMutableSet *s = [NSMutableSet set];
	[s addObjectsFromArray:[self filterBaseKeys]];
	[s addObjectsFromArray:[self hiddenLockedAccountKeys]];
	[s addObject:[self hiddenLockedGlobalKey]];
	[s addObjectsFromArray:[self chatBgAccountKeys]];
	[s addObjectsFromArray:[self chatBgGlobalKeys]];
	[s addObject:[self galleryFoldersKey]];
	for (NSDictionary *mod in [self featureDataModules]) [s addObjectsFromArray:mod[@"prefs"]];
	[s addObjectsFromArray:@[
		@"lock_passcode_blob",
		@"ryg_known_accounts",
		@"RyukGramFirstRun",
		@"ryg_changelog_last_seen_version",
		@"ryg_donate_launch_count",
		@"ryg_donate_snooze_until_launch",
		@"ryg_donate_prompt_silenced",
		@"ryg_donate_campaign",
		@"ryg_exp_warning_seen",
		// Restoring overrides must never arm the engine that applies them.
		@"ryg_metaconfig_enabled",
		@"ryg_metaconfig_warning_seen",
		@"deleted_messages_seen",
		@"read_receipts_seen",
		// One-time on-device migration markers — must never travel in a backup,
		// or another device would skip its own gallery/pref migration.
		@"ryg_gallery_store_migrated_v2",
		@"ryg_defaults_migrated_v1",
		// Auto-clear run state — another device's stamps would stall the schedule here.
		@"cache_last_auto_clear_ts",
		@"cache_last_known_size",
		@"cache_auto_clear_in_progress",
		@"cache_auto_clear_last_result",
		@"cache_auto_clear_fail_count",
	]];
	return s;
}

+ (NSSet<NSString *> *)allPrefKeys {
	NSMutableSet *keys = [NSMutableSet set];
	[self collectKeysFromSections:[RYGTweakSettings sections] into:keys];
	[keys addObjectsFromArray:[[RYGUtils rygRegisteredDefaults] allKeys]];
	return keys;
}

+ (NSSet<NSString *> *)settingsKeys {
	NSMutableSet *keys = [[self allPrefKeys] mutableCopy];
	[keys minusSet:[self settingsExcludedKeys]];
	return keys;
}

+ (void)collectKeysFromSections:(NSArray *)sections into:(NSMutableSet *)keys {
	for (id section in sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;
		for (id row in ((NSDictionary *)section)[@"rows"]) {
			if (![row isKindOfClass:RYGSetting.class]) continue;
			RYGSetting *s = row;
			if (s.defaultsKey.length) [keys addObject:s.defaultsKey];
			if (s.baseMenu) [self collectKeysFromMenu:s.baseMenu into:keys];
			if (s.navSections) [self collectKeysFromSections:s.navSections into:keys];
		}
	}
}

+ (void)collectKeysFromMenu:(UIMenu *)menu into:(NSMutableSet *)keys {
	for (id child in menu.children) {
		if ([child isKindOfClass:UIMenu.class]) { [self collectKeysFromMenu:child into:keys]; continue; }
		if (![child isKindOfClass:UICommand.class]) continue;
		id pl = [(UICommand *)child propertyList];
		if (![pl isKindOfClass:NSDictionary.class]) continue;
		NSString *k = ((NSDictionary *)pl)[@"defaultsKey"];
		if ([k isKindOfClass:NSString.class] && k.length) [keys addObject:k];
	}
}

#pragma mark - Per-account collect / restore

// Migrate any bare (pre-login) values into the current account's scoped keys
// so the per-PK enumeration doesn't miss them.
+ (void)migrateCurrentAccountForKeys:(NSArray<NSString *> *)keys {
	for (NSString *k in keys) (void)[RYGAccountScopedDefaults objectForKey:k];
}

+ (NSArray<NSString *> *)knownPKsForKeys:(NSArray<NSString *> *)keys {
	NSMutableSet *pks = [NSMutableSet setWithArray:[RYGAccountScopedDefaults allKnownPKsForBaseKeys:keys]];
	NSString *cur = [RYGUtils currentUserPK];
	if (cur.length && ![cur isEqualToString:@"0"]) [pks addObject:cur];
	return pks.allObjects;
}

// { "<pk>": { key: value } } across every account that has data.
+ (NSDictionary *)collectPerPKForKeys:(NSArray<NSString *> *)keys pks:(NSSet<NSString *> *)pks {
	[self migrateCurrentAccountForKeys:keys];
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *pk in [self knownPKsForKeys:keys]) {
		if (pks && ![pks containsObject:pk]) continue;
		NSMutableDictionary *bucket = [NSMutableDictionary dictionary];
		for (NSString *k in keys) {
			id v = [RYGAccountScopedDefaults objectForKey:k pk:pk];
			if (rygNonEmpty(v) && rygValidJSON(v)) bucket[k] = v;
		}
		if (bucket.count) out[pk] = bucket;
	}
	return out;
}

+ (void)restorePerPK:(NSDictionary *)map keys:(NSArray<NSString *> *)keys pks:(NSSet<NSString *> *)pks merge:(BOOL)merge {
	if (![map isKindOfClass:NSDictionary.class]) return;
	NSSet *allowed = [NSSet setWithArray:keys];
	for (NSString *pk in map) {
		if (pks && ![pks containsObject:pk]) continue;
		NSDictionary *bucket = map[pk];
		if (![bucket isKindOfClass:NSDictionary.class]) continue;
		for (NSString *k in bucket) {
			if (![allowed containsObject:k]) continue;
			id v = bucket[k];
			if (merge) v = rygMergedValue([RYGAccountScopedDefaults objectForKey:k pk:pk], v);
			[RYGAccountScopedDefaults setObject:v forKey:k pk:pk];
		}
	}
}

+ (void)clearPerPKForKeys:(NSArray<NSString *> *)keys pks:(NSSet<NSString *> *)pks {
	for (NSString *pk in [self knownPKsForKeys:keys]) {
		if (pks && ![pks containsObject:pk]) continue;
		for (NSString *k in keys) [RYGAccountScopedDefaults removeObjectForKey:k pk:pk];
	}
	// The bare key is pre-login residue owned by no account.
	if (!pks) for (NSString *k in keys) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
}

#pragma mark - Envelope build

+ (NSUInteger)dirFileCount:(NSString *)dir { NSUInteger c = 0; rygDirStats(dir, &c, NULL); return c; }

// Recorded into the manifest so the import preview shows the backup's size,
// not this device's.
+ (NSDictionary *)fileStatsForDir:(NSString *)dir pks:(NSSet<NSString *> *)pks {
	NSUInteger n = 0; unsigned long long b = 0;
	rygDirStatsForPKs(dir, pks, &n, &b);
	return @{ @"has_files": @(n > 0), @"file_count": @(n), @"byte_size": @(b) };
}

+ (NSDictionary *)accountsDictForPKs:(NSSet<NSString *> *)pks {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	NSDictionary *known = [RYGAccountRegistry allAccounts];
	for (NSString *pk in known) {
		if (pks && ![pks containsObject:pk]) continue;
		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		for (NSString *k in @[ @"username", @"full_name", @"profile_pic_url" ]) {
			id v = known[pk][k];
			if ([v isKindOfClass:NSString.class] && [v length]) info[k] = v;
		}
		if (info.count) out[pk] = info;
	}
	return out;
}

+ (NSDictionary *)buildEnvelopeForCategories:(RYGBackupCat)cats pks:(NSSet<NSString *> *)pks {
	NSMutableDictionary *root = [NSMutableDictionary dictionary];
	root[@"ryukgram_export"] = @YES;
	root[@"version"] = @3;
	root[@"exported_at"] = @([[NSDate date] timeIntervalSince1970]);
	root[@"accounts"] = [self accountsDictForPKs:pks];

	if (cats & RYGBackupCatSettings) {
		NSMutableDictionary *settings = [NSMutableDictionary dictionary];
		for (NSString *k in [self settingsKeys]) {
			id v = [NSUserDefaults.standardUserDefaults objectForKey:k];
			if (v && rygValidJSON(v)) settings[k] = v;
		}
		root[@"settings"] = settings;
	}

	if (cats & RYGBackupCatFilters) {
		root[@"filters"] = [self collectPerPKForKeys:[self filterBaseKeys] pks:pks];
	}

	if (cats & RYGBackupCatHiddenLocked) {
		NSMutableDictionary *hl = [NSMutableDictionary dictionary];
		hl[@"accounts"] = [self collectPerPKForKeys:[self hiddenLockedAccountKeys] pks:pks];
		id ov = [NSUserDefaults.standardUserDefaults objectForKey:[self hiddenLockedGlobalKey]];
		hl[@"global"] = (rygNonEmpty(ov) && rygValidJSON(ov)) ? @{ [self hiddenLockedGlobalKey]: ov } : @{};
		root[@"hidden_locked"] = hl;
	}

	if (cats & RYGBackupCatChatBackgrounds) {
		NSMutableDictionary *cb = [NSMutableDictionary dictionary];
		cb[@"accounts"] = [self collectPerPKForKeys:[self chatBgAccountKeys] pks:pks];
		NSMutableDictionary *global = [NSMutableDictionary dictionary];
		for (NSString *k in [self chatBgGlobalKeys]) {
			id v = [NSUserDefaults.standardUserDefaults objectForKey:k];
			if (rygNonEmpty(v) && rygValidJSON(v)) global[k] = v;
		}
		cb[@"global"] = global;
		[cb addEntriesFromDictionary:[self fileStatsForDir:rygChatBgDir() pks:nil]];
		root[@"chat_backgrounds"] = cb;
	}

	if (cats & RYGBackupCatGallery) {
		NSMutableDictionary *g = [NSMutableDictionary dictionary];
		id folders = [NSUserDefaults.standardUserDefaults objectForKey:[self galleryFoldersKey]];
		if (rygNonEmpty(folders) && rygValidJSON(folders)) g[[self galleryFoldersKey]] = folders;
		[g addEntriesFromDictionary:[self fileStatsForDir:rygGalleryDir() pks:nil]];
		root[@"gallery"] = g;
	}

	if (cats & RYGBackupCatDeletedMessages) {
		NSMutableDictionary *dm = [[self fileStatsForDir:rygDeletedDir() pks:pks] mutableCopy];
		dm[@"accounts"] = rygIntersect(rygPKsInDir(rygDeletedDir()), pks).allObjects;
		root[@"deleted_messages"] = dm;
	}

	if (cats & RYGBackupCatStoriesArchive) {
		NSMutableDictionary *sa = [[self fileStatsForDir:rygStoriesArchiveDir() pks:pks] mutableCopy];
		sa[@"accounts"] = rygIntersect(rygPKsInDir(rygStoriesArchiveDir()), pks).allObjects;
		root[@"stories_archive"] = sa;
	}

	NSMutableDictionary *fd = [NSMutableDictionary dictionary];
	[self enumerateFeatureModules:^(NSDictionary *mod, NSInteger bit) {
		if (!(cats & bit)) return;
		BOOL scoped = [mod[@"accountScoped"] boolValue];
		NSSet *modPKs = scoped ? pks : nil;
		NSMutableDictionary *entry = [NSMutableDictionary dictionary];
		NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
		for (NSString *k in mod[@"prefs"]) {
			id v = [NSUserDefaults.standardUserDefaults objectForKey:k];
			if (v && rygValidJSON(v)) prefs[k] = v;
		}
		entry[@"prefs"] = prefs;
		[entry addEntriesFromDictionary:[self fileStatsForDir:mod[@"dir"] pks:modPKs]];
		if (scoped) entry[@"accounts"] = rygIntersect(rygPKsInDir(mod[@"dir"]), pks).allObjects;
		fd[mod[@"id"]] = entry;
	}];
	if (fd.count) root[@"feature_data"] = fd;

	if (cats & RYGBackupCatAnalyzer) {
		root[@"analyzer"] = [self analyzerDictForPKs:pks] ?: @{};
	}

	return root;
}

// Analyzer files are "<pk>.<slot>.json" in a flat dir — filter by filename.
+ (NSDictionary *)analyzerDictForPKs:(NSSet<NSString *> *)pks {
	NSDictionary *all = [RYGProfileAnalyzerStorage exportedDict] ?: @{};
	if (!pks) return all;
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *name in all) {
		NSString *pk = rygPKOwningRelativePath(name);
		if (pk.length && [pks containsObject:pk]) out[name] = all[name];
	}
	return out;
}

+ (NSDictionary<NSString *, NSString *> *)archiveRootDirsForCategories:(RYGBackupCat)cats pks:(NSSet<NSString *> *)pks {
	NSMutableDictionary *roots = [NSMutableDictionary dictionary];
	if ((cats & RYGBackupCatGallery) && [self dirFileCount:rygGalleryDir()] > 0) {
		[[RYGGalleryCoreDataStack shared] checkpointStoreForExport]; // fold WAL in so the archived sqlite is complete
		roots[kArcGallery] = rygGalleryDir();
	}
	if ((cats & RYGBackupCatChatBackgrounds) && [self dirFileCount:rygChatBgDir()] > 0) roots[kArcChatBg] = rygChatBgDir();
	if (cats & RYGBackupCatDeletedMessages) {
		NSString *dir = rygStagedDirForPKs(rygDeletedDir(), pks);
		if ([self dirFileCount:dir] > 0) roots[kArcDeleted] = dir;
	}
	if (cats & RYGBackupCatStoriesArchive) {
		[RYGStoriesArchiveStore checkpointAllForExport]; // fold WAL in so archived sqlite is complete
		NSString *dir = rygStagedDirForPKs(rygStoriesArchiveDir(), pks);
		if ([self dirFileCount:dir] > 0) roots[kArcStoriesArchive] = dir;
	}
	[self enumerateFeatureModules:^(NSDictionary *mod, NSInteger bit) {
		if (!(cats & bit)) return;
		void (^prepareExport)(void) = mod[@"prepareExport"];
		if (prepareExport) prepareExport(); // e.g. fold a live CoreData WAL into the file before staging
		NSString *dir = rygStagedDirForPKs(mod[@"dir"], [mod[@"accountScoped"] boolValue] ? pks : nil);
		if ([self dirFileCount:dir] > 0)
			roots[[kArcFeatureData stringByAppendingPathComponent:mod[@"id"]]] = dir;
	}];
	return roots;
}

+ (NSData *)serializeJSON:(NSDictionary *)dict {
	NSError *err = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:(dict ?: @{})
												   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
													 error:&err];
	if (err) NSLog(@"[RyukGram] backup: serialize failed: %@", err);
	return data;
}

#pragma mark - Apply

+ (void)applyGlobalKey:(NSString *)key value:(id)v merge:(BOOL)merge {
	if (!rygNonEmpty(v)) return;
	if (merge) v = rygMergedValue([NSUserDefaults.standardUserDefaults objectForKey:key], v);
	[NSUserDefaults.standardUserDefaults setObject:v forKey:key];
}

// Re-key a pre-rename backup so its old-prefix keys restore onto the new ones.
+ (id)rekeyLegacyImport:(id)obj {
	if ([obj isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
		for (NSString *k in (NSDictionary *)obj) {
			NSString *nk = k;
			if ([k isKindOfClass:NSString.class]) {
				if ([k hasPrefix:@"sci_"])         nk = [@"ryg_" stringByAppendingString:[k substringFromIndex:4]];
				else if ([k hasPrefix:@"SCInsta"]) nk = [@"RyukGram" stringByAppendingString:[k substringFromIndex:7]];
				else if ([k hasPrefix:@"SCI"])     nk = [@"RYG" stringByAppendingString:[k substringFromIndex:3]];
			}
			out[nk] = [self rekeyLegacyImport:((NSDictionary *)obj)[k]];
		}
		return out;
	}
	if ([obj isKindOfClass:NSArray.class]) {
		NSMutableArray *a = [NSMutableArray arrayWithCapacity:[obj count]];
		for (id e in (NSArray *)obj) [a addObject:[self rekeyLegacyImport:e]];
		return a;
	}
	return obj;
}

+ (BOOL)applyImport:(NSDictionary *)root filesDir:(NSString *)filesDir scope:(RYGBackupCat)scope pks:(NSSet<NSString *> *)pks merge:(BOOL)merge {
	if (![root isKindOfClass:NSDictionary.class]) return NO;
	root = [self rekeyLegacyImport:root];
	[RYGAccountRegistry mergeAccounts:root[@"accounts"]];
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL any = NO;

	if ((scope & RYGBackupCatSettings) && [root[@"settings"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *settings = root[@"settings"];
		NSSet *keys = [self settingsKeys];
		// Merge keeps local values for keys the backup doesn't carry; replace
		// resets them to defaults first. Either way the backup's keys apply.
		if (!merge) for (NSString *k in keys) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
		for (NSString *k in settings) if ([keys containsObject:k]) [NSUserDefaults.standardUserDefaults setObject:settings[k] forKey:k];
		any = YES;
	}

	if ((scope & RYGBackupCatFilters) && [root[@"filters"] isKindOfClass:NSDictionary.class]) {
		[self restorePerPK:root[@"filters"] keys:[self filterBaseKeys] pks:pks merge:merge];
		any = YES;
	}

	if ((scope & RYGBackupCatHiddenLocked) && [root[@"hidden_locked"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *hl = root[@"hidden_locked"];
		[self restorePerPK:hl[@"accounts"] keys:[self hiddenLockedAccountKeys] pks:pks merge:merge];
		NSDictionary *global = [hl[@"global"] isKindOfClass:NSDictionary.class] ? hl[@"global"] : nil;
		[self applyGlobalKey:[self hiddenLockedGlobalKey] value:global[[self hiddenLockedGlobalKey]] merge:merge];
		any = YES;
	}

	if ((scope & RYGBackupCatChatBackgrounds) && [root[@"chat_backgrounds"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *cb = root[@"chat_backgrounds"];
		[self restorePerPK:cb[@"accounts"] keys:[self chatBgAccountKeys] pks:pks merge:merge];
		NSDictionary *global = [cb[@"global"] isKindOfClass:NSDictionary.class] ? cb[@"global"] : @{};
		for (NSString *k in [self chatBgGlobalKeys]) [self applyGlobalKey:k value:global[k] merge:merge];
		// Assets are content-named images: merge adds the missing ones, replace swaps the dir.
		NSString *extracted = [filesDir stringByAppendingPathComponent:kArcChatBg];
		if (merge) [self mergeDir:rygChatBgDir() fromExtracted:extracted fm:fm];
		else [self restoreDir:rygChatBgDir() fromExtracted:extracted fm:fm];
		any = YES;
	}

	if ((scope & RYGBackupCatGallery) && [root[@"gallery"] isKindOfClass:NSDictionary.class]) {
		[self applyGlobalKey:[self galleryFoldersKey] value:root[@"gallery"][[self galleryFoldersKey]] merge:merge];
		NSString *extracted = [filesDir stringByAppendingPathComponent:kArcGallery];
		// Row-level import into the live store for both modes — never swaps the
		// sqlite, so an old/legacy backup store can't strand the migration flag.
		// merge = dedup by content; replace = wipe existing rows + media first.
		[[RYGGalleryCoreDataStack shared] importGalleryFromArchiveDirectory:extracted replace:!merge];
		any = YES;
	}

	if ((scope & RYGBackupCatDeletedMessages) && [root[@"deleted_messages"] isKindOfClass:NSDictionary.class]) {
		NSString *extracted = rygStagedDirForPKs([filesDir stringByAppendingPathComponent:kArcDeleted], pks);
		if (merge) [RYGDeletedMessagesStorage mergeImportedStoreAtPath:extracted];
		else if (pks) [self replaceDir:rygDeletedDir() fromExtracted:extracted pks:pks
							   resetPK:^(NSString *pk) { [RYGDeletedMessagesStorage resetForOwnerPK:pk]; } fm:fm];
		else [self restoreDir:rygDeletedDir() fromExtracted:extracted fm:fm];
		any = YES;
	}

	if ((scope & RYGBackupCatStoriesArchive) && [root[@"stories_archive"] isKindOfClass:NSDictionary.class]) {
		NSString *extracted = rygStagedDirForPKs([filesDir stringByAppendingPathComponent:kArcStoriesArchive], pks);
		if (merge) [RYGStoriesArchiveStore mergeImportedStoreAtPath:extracted];
		else if (pks) [self replaceDir:rygStoriesArchiveDir() fromExtracted:extracted pks:pks
							   resetPK:^(NSString *pk) { [RYGStoriesArchiveStore resetForPK:pk]; } fm:fm];
		else [self restoreDir:rygStoriesArchiveDir() fromExtracted:extracted fm:fm];
		any = YES;
	}

	if ([root[@"feature_data"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *fd = root[@"feature_data"];
		__block BOOL anyModule = NO;
		[self enumerateFeatureModules:^(NSDictionary *mod, NSInteger bit) {
			if (!(scope & bit)) return;
			NSDictionary *entry = [fd[mod[@"id"]] isKindOfClass:NSDictionary.class] ? fd[mod[@"id"]] : nil;
			if (!entry) return;
			NSSet *modPKs = [mod[@"accountScoped"] boolValue] ? pks : nil;
			// A store's prefs are shared, so an account filter leaves them alone.
			if (!modPKs) {
				NSDictionary *prefs = [entry[@"prefs"] isKindOfClass:NSDictionary.class] ? entry[@"prefs"] : @{};
				for (NSString *k in mod[@"prefs"]) if (prefs[k]) [NSUserDefaults.standardUserDefaults setObject:prefs[k] forKey:k];
			}
			NSString *extracted = [self extractedDirForModule:mod[@"id"] filesDir:filesDir];
			if (extracted) extracted = rygStagedDirForPKs(extracted, modPKs);
			if (merge) {
				if (extracted) {
					void (^mergeBlock)(NSString *) = mod[@"merge"];
					if (mergeBlock) mergeBlock(extracted);
					else [self mergeDir:mod[@"dir"] fromExtracted:extracted fm:fm];
				}
			} else if (modPKs) {
				[self replaceDir:mod[@"dir"] fromExtracted:extracted pks:modPKs resetPK:mod[@"resetPK"] fm:fm];
			} else {
				// Reset first so a stale in-memory cache can't resurrect wiped state.
				void (^resetBlock)(void) = mod[@"reset"];
				if (resetBlock) resetBlock(); else [fm removeItemAtPath:mod[@"dir"] error:nil];
				[self restoreDir:mod[@"dir"] fromExtracted:extracted fm:fm];
			}
			void (^postImport)(void) = mod[@"postImport"];
			if (postImport) postImport(); // e.g. reload a live in-memory store from the files that just landed
			anyModule = YES;
		}];
		if (anyModule) any = YES;
	}

	if ((scope & RYGBackupCatAnalyzer) && [root[@"analyzer"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *incoming = [self analyzerImportDict:root[@"analyzer"] pks:pks merge:merge];
		[RYGProfileAnalyzerStorage importFromDict:incoming];
		any = YES;
	}

	NSLog(@"[RyukGram][Backup] applied scope=%ld accounts=%lu merge=%d any=%d",
		  (long)scope, (unsigned long)(pks ? pks.count : 0), merge, any);
	if (any) [NSUserDefaults.standardUserDefaults synchronize];
	return any;
}

// importFromDict: rewrites the whole store, so unpicked accounts get handed
// back their own files verbatim.
+ (NSDictionary *)analyzerImportDict:(NSDictionary *)incoming pks:(NSSet<NSString *> *)pks merge:(BOOL)merge {
	NSDictionary *local = [RYGProfileAnalyzerStorage exportedDict] ?: @{};
	if (!pks) return merge ? rygMergedValue(local, incoming) : incoming;

	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *name in local) {
		NSString *pk = rygPKOwningRelativePath(name);
		if (!pk.length || ![pks containsObject:pk]) out[name] = local[name];
	}
	for (NSString *name in incoming) {
		NSString *pk = rygPKOwningRelativePath(name);
		if (!pk.length || ![pks containsObject:pk]) continue;
		out[name] = merge ? rygMergedValue(local[name], incoming[name]) : incoming[name];
	}
	return out;
}

// Replace narrowed to the picked accounts — everyone else's records survive.
+ (void)replaceDir:(NSString *)target
	 fromExtracted:(NSString *)extracted
			   pks:(NSSet<NSString *> *)pks
		   resetPK:(void (^)(NSString *pk))resetPK
				fm:(NSFileManager *)fm {
	if (resetPK) for (NSString *pk in pks) resetPK(pk);
	else rygRemoveFilesForPKs(target, pks);
	[self mergeDir:target fromExtracted:extracted fm:fm];
}

// Module files live under files/feature_data/<id>; dev-era backups used files/<id>.
+ (NSString *)extractedDirForModule:(NSString *)moduleId filesDir:(NSString *)filesDir {
	if (!filesDir.length) return nil;
	BOOL isDir = NO;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *p = [[filesDir stringByAppendingPathComponent:kArcFeatureData] stringByAppendingPathComponent:moduleId];
	if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) return p;
	p = [[filesDir stringByAppendingPathComponent:@"files"] stringByAppendingPathComponent:moduleId];
	if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) return p;
	return nil;
}

// moveItem can fail across volumes, so fall back to copy.
+ (void)restoreDir:(NSString *)target fromExtracted:(NSString *)extracted fm:(NSFileManager *)fm {
	BOOL isDir = NO;
	if (!extracted.length || ![fm fileExistsAtPath:extracted isDirectory:&isDir] || !isDir) return;
	[fm removeItemAtPath:target error:nil];
	[fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
	if (![fm moveItemAtPath:extracted toPath:target error:nil]) {
		[fm copyItemAtPath:extracted toPath:target error:nil];
	}
}

// Existing local files win on a name clash.
+ (void)mergeDir:(NSString *)target fromExtracted:(NSString *)extracted fm:(NSFileManager *)fm {
	BOOL isDir = NO;
	if (!extracted.length || ![fm fileExistsAtPath:extracted isDirectory:&isDir] || !isDir) return;
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:extracted];
	for (NSString *rel in en) {
		if (![en.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) continue;
		NSString *dst = [target stringByAppendingPathComponent:rel];
		if ([fm fileExistsAtPath:dst]) continue;
		[fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
		[fm copyItemAtPath:[extracted stringByAppendingPathComponent:rel] toPath:dst error:nil];
	}
}

#pragma mark - Reset

+ (void)resetForScope:(RYGBackupCat)scope pks:(NSSet<NSString *> *)pks {
	NSFileManager *fm = [NSFileManager defaultManager];

	if (scope & RYGBackupCatSettings) {
		for (NSString *k in [self settingsKeys]) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
	}
	if (scope & RYGBackupCatFilters) [self clearPerPKForKeys:[self filterBaseKeys] pks:pks];
	if (scope & RYGBackupCatHiddenLocked) {
		[self clearPerPKForKeys:[self hiddenLockedAccountKeys] pks:pks];
		if (!pks) [NSUserDefaults.standardUserDefaults removeObjectForKey:[self hiddenLockedGlobalKey]];
	}
	if (scope & RYGBackupCatChatBackgrounds) {
		[self clearPerPKForKeys:[self chatBgAccountKeys] pks:pks];
		if (!pks) {
			for (NSString *k in [self chatBgGlobalKeys]) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
			[fm removeItemAtPath:rygChatBgDir() error:nil];
		}
	}
	if (scope & RYGBackupCatGallery) {
		[NSUserDefaults.standardUserDefaults removeObjectForKey:[self galleryFoldersKey]];
		[fm removeItemAtPath:rygGalleryDir() error:nil];
	}
	if (scope & RYGBackupCatDeletedMessages) {
		if (pks) for (NSString *pk in pks) [RYGDeletedMessagesStorage resetForOwnerPK:pk];
		else [RYGDeletedMessagesStorage resetAll];
	}
	if (scope & RYGBackupCatStoriesArchive) {
		if (pks) for (NSString *pk in pks) [RYGStoriesArchiveStore resetForPK:pk];
		else [RYGStoriesArchiveStore resetAll];
	}
	[self enumerateFeatureModules:^(NSDictionary *mod, NSInteger bit) {
		if (!(scope & bit)) return;
		NSSet *modPKs = [mod[@"accountScoped"] boolValue] ? pks : nil;
		if (modPKs) {
			void (^resetPK)(NSString *) = mod[@"resetPK"];
			if (resetPK) for (NSString *pk in modPKs) resetPK(pk);
			else rygRemoveFilesForPKs(mod[@"dir"], modPKs);
			return;
		}
		for (NSString *k in mod[@"prefs"]) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
		void (^resetBlock)(void) = mod[@"reset"];
		if (resetBlock) resetBlock(); else [fm removeItemAtPath:mod[@"dir"] error:nil];
	}];
	if (scope & RYGBackupCatAnalyzer) {
		if (pks) {
			// resetForUserPK: spares the header cache and visit log.
			for (NSString *pk in pks) [RYGProfileAnalyzerStorage resetForUserPK:pk];
			rygRemoveFilesForPKs([RYGProfileAnalyzerStorage storageDirectory], pks);
		} else {
			[RYGProfileAnalyzerStorage resetAll];
		}
	}

	[NSUserDefaults.standardUserDefaults synchronize];
}

#pragma mark - Categories present in an envelope

+ (RYGBackupCat)categoriesInEnvelope:(NSDictionary *)root {
	__block RYGBackupCat c = 0;
	if ([root[@"settings"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatSettings;
	if ([root[@"filters"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatFilters;
	if ([root[@"hidden_locked"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatHiddenLocked;
	if ([root[@"chat_backgrounds"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatChatBackgrounds;
	if ([root[@"gallery"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatGallery;
	if ([root[@"deleted_messages"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatDeletedMessages;
	if ([root[@"stories_archive"] isKindOfClass:NSDictionary.class]) c |= RYGBackupCatStoriesArchive;
	NSDictionary *fd = [root[@"feature_data"] isKindOfClass:NSDictionary.class] ? root[@"feature_data"] : nil;
	if (fd.count) {
		[self enumerateFeatureModules:^(NSDictionary *mod, NSInteger bit) {
			if ([fd[mod[@"id"]] isKindOfClass:NSDictionary.class]) c |= bit;
		}];
	}
	if ([root[@"analyzer"] isKindOfClass:NSDictionary.class] && [(NSDictionary *)root[@"analyzer"] count]) c |= RYGBackupCatAnalyzer;
	return c;
}

#pragma mark - Accounts present in an envelope

+ (void)addPKKeysOf:(id)map to:(NSMutableSet *)pks {
	if (![map isKindOfClass:NSDictionary.class]) return;
	for (NSString *pk in (NSDictionary *)map) if ([pk isKindOfClass:NSString.class] && pk.length) [pks addObject:pk];
}

// Every account the envelope carries data for — what the filter can pick from.
+ (NSSet<NSString *> *)accountsInEnvelope:(NSDictionary *)root {
	NSMutableSet *pks = [NSMutableSet set];
	if (![root isKindOfClass:NSDictionary.class]) return pks;

	[self addPKKeysOf:root[@"filters"] to:pks];
	[self addPKKeysOf:[root[@"hidden_locked"] isKindOfClass:NSDictionary.class] ? root[@"hidden_locked"][@"accounts"] : nil to:pks];
	[self addPKKeysOf:[root[@"chat_backgrounds"] isKindOfClass:NSDictionary.class] ? root[@"chat_backgrounds"][@"accounts"] : nil to:pks];

	if ([root[@"analyzer"] isKindOfClass:NSDictionary.class]) {
		for (NSString *name in (NSDictionary *)root[@"analyzer"]) {
			NSString *pk = [name isKindOfClass:NSString.class] ? rygPKOwningRelativePath(name) : nil;
			if (pk.length) [pks addObject:pk];
		}
	}

	void (^addList)(id) = ^(id list) {
		if (![list isKindOfClass:NSArray.class]) return;
		for (NSString *pk in (NSArray *)list) if ([pk isKindOfClass:NSString.class] && pk.length) [pks addObject:pk];
	};
	addList([root[@"deleted_messages"] isKindOfClass:NSDictionary.class] ? root[@"deleted_messages"][@"accounts"] : nil);
	addList([root[@"stories_archive"] isKindOfClass:NSDictionary.class] ? root[@"stories_archive"][@"accounts"] : nil);
	if ([root[@"feature_data"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *fd = root[@"feature_data"];
		for (NSString *id_ in fd) if ([fd[id_] isKindOfClass:NSDictionary.class]) addList(fd[id_][@"accounts"]);
	}
	return pks;
}

// Accounts get bits by sorted position, in a mask space of their own.
+ (NSArray<NSString *> *)sortedAccountPKs:(NSSet<NSString *> *)pks {
	return [pks.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		NSComparisonResult byName = [[RYGAccountRegistry displayNameForPK:a] localizedCaseInsensitiveCompare:[RYGAccountRegistry displayNameForPK:b]];
		return byName != NSOrderedSame ? byName : [a compare:b];
	}];
}

+ (NSArray<NSDictionary *> *)accountRowsForPKs:(NSArray<NSString *> *)ordered {
	NSMutableArray *rows = [NSMutableArray array];
	NSString *current = [RYGUtils currentUserPK];
	for (NSUInteger i = 0; i < ordered.count && i < 62; i++) {
		NSString *pk = ordered[i];
		NSDictionary *info = [RYGAccountRegistry infoForPK:pk];
		NSString *fullName = [info[@"full_name"] isKindOfClass:NSString.class] ? info[@"full_name"] : nil;
		NSMutableArray *bits = [NSMutableArray array];
		if (fullName.length) [bits addObject:fullName];
		if ([pk isEqualToString:current]) [bits addObject:RYGLocalized(@"Signed in")];
		[rows addObject:@{
			@"bit": @((NSInteger)1 << i),
			@"title": [RYGAccountRegistry displayNameForPK:pk info:info],
			@"subtitle": [bits componentsJoinedByString:@" · "],
		}];
	}
	return rows;
}

+ (NSInteger)maskForAllAccounts:(NSArray<NSString *> *)ordered {
	NSInteger mask = 0;
	for (NSUInteger i = 0; i < ordered.count && i < 62; i++) mask |= (NSInteger)1 << i;
	return mask;
}

// nil when every account is picked — downstream reads nil as "no filter".
+ (NSSet<NSString *> *)pksForAccountMask:(NSInteger)mask ordered:(NSArray<NSString *> *)ordered {
	if (!ordered.count) return nil;
	NSMutableSet *out = [NSMutableSet set];
	for (NSUInteger i = 0; i < ordered.count && i < 62; i++) {
		if (mask & ((NSInteger)1 << i)) [out addObject:ordered[i]];
	}
	return out.count == ordered.count ? nil : out;
}

#pragma mark - Row descriptors (picker payload)

+ (NSString *)text:(id)v {
	return [v isKindOfClass:NSString.class] ? v : (v ? [v description] : @"");
}

+ (NSString *)displayValue:(id)v {
	if ([v isKindOfClass:NSNumber.class]) {
		NSNumber *n = v;
		const char *t = n.objCType;
		return (t && strcmp(t, "c") == 0) ? (n.boolValue ? @"on" : @"off") : n.stringValue;
	}
	if ([v isKindOfClass:NSString.class]) return v;
	if ([v isKindOfClass:NSArray.class]) return [NSString stringWithFormat:@"[%lu]", (unsigned long)[(NSArray *)v count]];
	if ([v isKindOfClass:NSDictionary.class]) return [NSString stringWithFormat:@"{%lu}", (unsigned long)[(NSDictionary *)v count]];
	return @"—";
}

+ (NSArray *)settingsDetailSections:(NSDictionary *)settings {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSString *k in [settings.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		[rows addObject:@{ @"title": k, @"value": [self displayValue:settings[k]] }];
	}
	return @[ @{ @"title": [NSString stringWithFormat:RYGLocalized(@"All preferences (%lu)"), (unsigned long)rows.count], @"rows": rows } ];
}

+ (NSArray *)perPKDetailSections:(NSDictionary *)map {
	NSMutableArray *sections = [NSMutableArray array];
	for (NSString *pk in [map.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		NSDictionary *bucket = [map[pk] isKindOfClass:NSDictionary.class] ? map[pk] : @{};
		NSMutableArray *rows = [NSMutableArray array];
		for (NSString *k in [bucket.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
			[rows addObject:@{ @"title": k, @"value": [self displayValue:bucket[k]] }];
		}
		if (!rows.count) [rows addObject:@{ @"title": RYGLocalized(@"(empty)"), @"value": @"" }];
		[sections addObject:@{ @"title": [NSString stringWithFormat:RYGLocalized(@"PK %@"), pk], @"rows": rows }];
	}
	return sections.count ? sections : @[ @{ @"title": @"", @"rows": @[ @{ @"title": RYGLocalized(@"(none)"), @"value": @"" } ] } ];
}

+ (NSArray *)analyzerDetailSections:(NSDictionary *)analyzer {
	NSMutableDictionary<NSString *, NSMutableDictionary *> *byPK = [NSMutableDictionary dictionary];
	for (NSString *file in analyzer) {
		NSArray *parts = [file componentsSeparatedByString:@"."];
		if (parts.count < 2) continue;
		NSMutableDictionary *slot = byPK[parts[0]] ?: [NSMutableDictionary dictionary];
		slot[parts[1]] = analyzer[file];
		byPK[parts[0]] = slot;
	}
	NSMutableArray *sections = [NSMutableArray array];
	for (NSString *pk in [byPK.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		NSDictionary *slot = byPK[pk];
		NSDictionary *hdr = [slot[@"header"] isKindOfClass:NSDictionary.class] ? slot[@"header"] : nil;
		NSString *username = [hdr[@"username"] isKindOfClass:NSString.class] ? hdr[@"username"] : nil;
		NSString *header = username.length ? [NSString stringWithFormat:@"@%@", username] : [NSString stringWithFormat:RYGLocalized(@"PK %@"), pk];
		NSMutableArray *rows = [NSMutableArray array];
		if (hdr) {
			[rows addObject:@{ @"title": RYGLocalized(@"Followers"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"follower_count"] integerValue]] }];
			[rows addObject:@{ @"title": RYGLocalized(@"Following"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"following_count"] integerValue]] }];
		}
		NSDictionary *snaphist = [slot[@"snaphistory"] isKindOfClass:NSDictionary.class] ? slot[@"snaphistory"] : nil;
		NSArray *snaps = [snaphist[@"snapshots"] isKindOfClass:NSArray.class] ? snaphist[@"snapshots"] : @[];
		[rows addObject:@{ @"title": RYGLocalized(@"Archived snapshots"), @"value": [NSString stringWithFormat:@"%lu", (unsigned long)snaps.count] }];
		[sections addObject:@{ @"title": header, @"rows": rows }];
	}
	return sections.count ? sections : @[ @{ @"title": @"", @"rows": @[ @{ @"title": RYGLocalized(@"(no analyzer data)"), @"value": @"" } ] } ];
}

+ (NSArray<NSDictionary *> *)rowDescriptorsForAvailable:(RYGBackupCat)available envelope:(NSDictionary *)env {
	NSMutableArray *rows = [NSMutableArray array];

	// `shared` marks rows an account filter can't narrow; the picker tags them.
	void (^addShared)(RYGBackupCat, NSString *, NSString *, RYGSymbol *, UIColor *, NSArray *, BOOL) =
	^(RYGBackupCat bit, NSString *title, NSString *subtitle, RYGSymbol *symbol, UIColor *color, NSArray *detail, BOOL shared) {
		if (!(available & bit)) return;
		NSMutableDictionary *d = [@{ @"bit": @(bit), @"title": title, @"subtitle": subtitle ?: @"", @"symbol": symbol, @"color": color, @"shared": @(shared) } mutableCopy];
		if (detail) d[@"detailSections"] = detail;
		[rows addObject:d];
	};
	void (^add)(RYGBackupCat, NSString *, NSString *, RYGSymbol *, UIColor *, NSArray *) =
	^(RYGBackupCat bit, NSString *title, NSString *subtitle, RYGSymbol *symbol, UIColor *color, NSArray *detail) {
		addShared(bit, title, subtitle, symbol, color, detail, NO);
	};

	NSDictionary *settings = [env[@"settings"] isKindOfClass:NSDictionary.class] ? env[@"settings"] : @{};
	addShared(RYGBackupCatSettings, RYGLocalized(@"Settings"),
		[NSString stringWithFormat:RYGLocalized(@"%lu preferences"), (unsigned long)settings.count],
		[RYGFeatureIcons settings], UIColor.systemBlueColor, [self settingsDetailSections:settings], YES);

	NSDictionary *filters = [env[@"filters"] isKindOfClass:NSDictionary.class] ? env[@"filters"] : @{};
	add(RYGBackupCatFilters, RYGLocalized(@"Chat & story filters"),
		[NSString stringWithFormat:RYGLocalized(@"%lu account(s)"), (unsigned long)filters.count],
		[RYGFeatureIcons filters], UIColor.systemOrangeColor, [self perPKDetailSections:filters]);

	NSDictionary *hl = [env[@"hidden_locked"] isKindOfClass:NSDictionary.class] ? env[@"hidden_locked"] : @{};
	NSDictionary *hlAcc = [hl[@"accounts"] isKindOfClass:NSDictionary.class] ? hl[@"accounts"] : @{};
	add(RYGBackupCatHiddenLocked, RYGLocalized(@"Hidden & locked chats"),
		[NSString stringWithFormat:RYGLocalized(@"%lu account(s)"), (unsigned long)hlAcc.count],
		[RYGFeatureIcons hiddenLockedChatsFilled], UIColor.systemIndigoColor, [self perPKDetailSections:hlAcc]);

	// File stats from the envelope (manifest on import) — describe the backup, not the device.
	NSDictionary *(^fileDict)(NSString *) = ^NSDictionary *(NSString *key) {
		return [env[key] isKindOfClass:NSDictionary.class] ? env[key] : @{};
	};

	NSDictionary *analyzer = [env[@"analyzer"] isKindOfClass:NSDictionary.class] ? env[@"analyzer"] : @{};
	NSMutableSet *aPks = [NSMutableSet set];
	for (NSString *f in analyzer) { NSArray *p = [f componentsSeparatedByString:@"."]; if (p.count) [aPks addObject:p[0]]; }
	add(RYGBackupCatAnalyzer, RYGLocalized(@"Profile Analyzer data"),
		[NSString stringWithFormat:RYGLocalized(@"%lu account(s)"), (unsigned long)aPks.count],
		[RYGFeatureIcons profileAnalyzer], UIColor.systemPurpleColor, [self analyzerDetailSections:analyzer]);

	NSDictionary *sa = fileDict(@"stories_archive");
	add(RYGBackupCatStoriesArchive, RYGLocalized(@"Stories archive"),
		[NSString stringWithFormat:RYGLocalized(@"%lu file(s) · %@"),
			(unsigned long)[sa[@"file_count"] unsignedIntegerValue], rygHumanSize([sa[@"byte_size"] unsignedLongLongValue])],
		[RYGFeatureIcons storiesArchive], UIColor.systemCyanColor, nil);

	NSDictionary *gal = fileDict(@"gallery");
	addShared(RYGBackupCatGallery, RYGLocalized(@"Gallery"),
		[NSString stringWithFormat:RYGLocalized(@"%lu file(s) · %@"),
			(unsigned long)[gal[@"file_count"] unsignedIntegerValue], rygHumanSize([gal[@"byte_size"] unsignedLongLongValue])],
		[RYGFeatureIcons gallery], UIColor.systemPinkColor, nil, YES);

	NSDictionary *cb = fileDict(@"chat_backgrounds");
	NSDictionary *cbAcc = [cb[@"accounts"] isKindOfClass:NSDictionary.class] ? cb[@"accounts"] : @{};
	add(RYGBackupCatChatBackgrounds, RYGLocalized(@"Chat backgrounds"),
		[NSString stringWithFormat:RYGLocalized(@"%lu account(s) · %lu image(s) · %@"),
			(unsigned long)cbAcc.count, (unsigned long)[cb[@"file_count"] unsignedIntegerValue], rygHumanSize([cb[@"byte_size"] unsignedLongLongValue])],
		[RYGFeatureIcons chatBackgroundsFilled], UIColor.systemTealColor, nil);

	NSDictionary *del = fileDict(@"deleted_messages");
	if (available & RYGBackupCatDeletedMessages) {
		NSString *logSub = [NSString stringWithFormat:RYGLocalized(@"%lu file(s) · %@"),
			(unsigned long)[del[@"file_count"] unsignedIntegerValue], rygHumanSize([del[@"byte_size"] unsignedLongLongValue])];
		[rows addObject:@{
			@"isGroup": @YES,
			@"groupMask": @(RYGBackupCatDeletedMessages),
			@"submodules": @[ @{
				@"bit": @(RYGBackupCatDeletedMessages),
				@"shared": @NO,
				@"title": RYGLocalized(@"Message log"),
				@"subtitle": logSub,
				@"detailSections": @[ @{ @"title": RYGLocalized(@"Message log"),
										 @"rows": @[ @{ @"title": RYGLocalized(@"Files"), @"value": logSub } ] } ],
			} ],
			@"title": RYGLocalized(@"Deleted messages"),
			@"subtitle": logSub,
			@"symbol": [RYGFeatureIcons deletedMessagesFilled],
			@"color": UIColor.systemBrownColor,
		}];
	}

	// Single "Feature data" row drilling into a tickable sub-list, both derived
	// from +featureDataModules — sub-rows carry no per-module icon by design.
	NSDictionary *fd = fileDict(@"feature_data");
	NSArray *mods = [self featureDataModules];
	NSMutableArray *submodules = [NSMutableArray array];
	NSUInteger fdFiles = 0; unsigned long long fdBytes = 0; NSInteger groupMask = 0;

	for (NSUInteger i = 0; i < mods.count; i++) {
		NSInteger bit = [self bitForFeatureIndex:i];
		if (!(available & bit)) continue;
		NSDictionary *mod = mods[i];
		NSDictionary *entry = [fd[mod[@"id"]] isKindOfClass:NSDictionary.class] ? fd[mod[@"id"]] : nil;
		NSUInteger files = [entry[@"file_count"] unsignedIntegerValue];
		unsigned long long bytes = [entry[@"byte_size"] unsignedLongLongValue];
		NSDictionary *prefs = [entry[@"prefs"] isKindOfClass:NSDictionary.class] ? entry[@"prefs"] : @{};

		NSMutableArray *modRows = [NSMutableArray array];
		for (NSString *k in [prefs.allKeys sortedArrayUsingSelector:@selector(compare:)])
			[modRows addObject:@{ @"title": k, @"value": [self displayValue:prefs[k]] }];
		[modRows addObject:@{ @"title": RYGLocalized(@"Files"),
							  @"value": [NSString stringWithFormat:RYGLocalized(@"%lu file(s) · %@"), (unsigned long)files, rygHumanSize(bytes)] }];

		[submodules addObject:@{
			@"bit": @(bit),
			@"shared": @(![mod[@"accountScoped"] boolValue]),
			@"title": mod[@"title"] ?: mod[@"id"],
			@"subtitle": [NSString stringWithFormat:RYGLocalized(@"%lu file(s) · %@"), (unsigned long)files, rygHumanSize(bytes)],
			@"detailSections": @[ @{ @"title": mod[@"title"] ?: mod[@"id"], @"rows": modRows } ],
		}];
		fdFiles += files; fdBytes += bytes; groupMask |= bit;
	}

	if (submodules.count) {
		[rows addObject:@{
			@"isGroup": @YES,
			@"groupMask": @(groupMask),
			@"submodules": submodules,
			@"title": RYGLocalized(@"Feature data"),
			@"subtitle": [NSString stringWithFormat:RYGLocalized(@"%lu file(s) · %@"), (unsigned long)fdFiles, rygHumanSize(fdBytes)],
			@"symbol": [RYGFeatureIcons featureData],
			@"color": UIColor.systemGreenColor,
		}];
	}

	return rows;
}

#pragma mark - Picker presentation

// Presents at once and spins; `loader` runs off-main (scanning the gallery and
// analyzer stores would stall the tap) and returns @{ envelope, available, initial }.
+ (void)presentPickerTitle:(NSString *)continueTitle
				   message:(NSString *)message
					loader:(NSDictionary *(^)(void))loader
		   showsImportMode:(BOOL)showsImportMode
			 showsEncrypt:(BOOL)showsEncrypt
				   handler:(void(^)(NSInteger scope, NSSet<NSString *> *pks, BOOL merge, NSString *password))handler {
	RYGBackupScopePickerVC *vc = [RYGBackupScopePickerVC new];
	vc.title = continueTitle;
	vc.continueTitle = continueTitle;
	vc.headerMessage = message;
	vc.showsImportMode = showsImportMode;
	vc.showsEncryptOption = showsEncrypt;
	vc.loadingContent = YES;

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[topMostController() presentViewController:nav animated:YES completion:nil];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSDictionary *loaded = loader() ?: @{};
		NSDictionary *envelope = loaded[@"envelope"];
		NSInteger available = [loaded[@"available"] integerValue];
		NSInteger initial = [loaded[@"initial"] integerValue] & available;

		NSArray *rows = [self rowDescriptorsForAvailable:available envelope:envelope];
		// A single account has nothing to filter, so the section stays hidden.
		NSArray<NSString *> *ordered = [self sortedAccountPKs:[self accountsInEnvelope:envelope]];
		BOOL filterable = ordered.count > 1;
		NSData *raw = [self serializeJSON:envelope];

		NSDictionary *payload = @{
			@"rows": rows,
			@"accountRows": filterable ? [self accountRowsForPKs:ordered] : @[],
			@"initialSelection": @(initial),
			@"initialAccountSelection": @(filterable ? [self maskForAllAccounts:ordered] : 0),
			@"rawJSON": [[NSString alloc] initWithData:(raw ?: [NSData data]) encoding:NSUTF8StringEncoding] ?: @"{}",
		};

		dispatch_async(dispatch_get_main_queue(), ^{
			vc.onContinue = ^(NSInteger chosen, NSInteger accounts, BOOL merge, NSString *password) {
				if (handler) handler(chosen, [self pksForAccountMask:accounts ordered:ordered], merge, password);
			};
			[vc applyContent:payload];
			[RYGAccountRegistry resolveMissingNamesForPKs:ordered];
		});
	});
}

#pragma mark - Export

+ (void)presentExport {
	[self presentPickerTitle:RYGLocalized(@"Export")
					 message:RYGLocalized(@"Tick what to include. Tap a row to inspect it. Adding gallery, chat backgrounds or deleted messages produces a compressed .ryukbak bundle.")
					  loader:^{
		// Gallery + stories archive (large media) and feature-data (private logs) stay opt-in.
		return @{ @"envelope": [self buildEnvelopeForCategories:[self allScopeMask] pks:nil],
				  @"available": @([self allScopeMask]),
				  @"initial": @((NSInteger)RYGBackupCatAllFixed & ~RYGBackupCatGallery & ~RYGBackupCatStoriesArchive) };
	}
			 showsImportMode:NO
			 showsEncrypt:YES
					 handler:^(NSInteger scope, NSSet<NSString *> *pks, __unused BOOL merge, NSString *password) {
		[self writeExportForScope:scope pks:pks password:password];
	}];
}

+ (void)writeExportForScope:(NSInteger)scope pks:(NSSet<NSString *> *)pks password:(NSString *)password {
	NSDictionary *envelope = [self buildEnvelopeForCategories:scope pks:pks];
	NSDictionary<NSString *, NSString *> *roots = [self archiveRootDirsForCategories:scope pks:pks];
	NSData *payload = [self serializeJSON:envelope];
	NSString *stamp = [self timestampString];
	BOOL encrypt = password.length > 0;
	NSString *ext = encrypt ? @"ryukbak" : (roots.count ? @"ryukbak" : @"json");
	NSString *name = [NSString stringWithFormat:@"RyukGram-%@-backup-%@.%@", RYGVersionString, stamp, ext];

	// No media: small JSON, build inline (may still need off-main encryption).
	if (roots.count == 0) {
		NSURL *out = [RYGTempFiles claimNamedFile:name ttl:900 tag:@"backup"];
		if (!encrypt) {
			if (!payload || ![payload writeToURL:out options:NSDataWritingAtomic error:nil]) {
				[RYGTempFiles releaseURL:out];
				[self showError:RYGLocalized(@"Could not write backup file.")];
				return;
			}
			[self presentExportPickerForURL:out scope:scope archived:NO handle:nil];
			return;
		}
		RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_BACKUP, RYGLocalized(@"Encrypting backup…"), nil);
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSError *err = nil;
			NSData *enc = [RYGBackupCrypto encrypt:payload password:password contentType:RYGBackupContentJSON error:&err];
			BOOL ok = enc && [enc writeToURL:out options:NSDataWritingAtomic error:&err];
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!ok) { [h error:(err.localizedDescription ?: RYGLocalized(@"Could not write backup file."))]; [RYGTempFiles releaseURL:out]; return; }
				[self presentExportPickerForURL:out scope:scope archived:YES handle:h];
			});
		});
		return;
	}

	// Media bundle: compress (and optionally encrypt) off-main, pill carries to success.
	NSURL *out = [RYGTempFiles claimNamedFile:name ttl:900 tag:@"backup"];
	RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_BACKUP, RYGLocalized(@"Preparing backup…"), nil);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		BOOL ok;
		if (encrypt) {
			NSURL *tmp = [RYGTempFiles claimWithExt:@"ryukbak" ttl:300 tag:@"backupraw"];
			ok = [RYGArchive createArchiveAtURL:tmp rootDirs:roots extraFiles:@{ @"manifest.json": payload } error:&err];
			if (ok) {
				NSData *raw = [NSData dataWithContentsOfURL:tmp];
				NSData *enc = raw ? [RYGBackupCrypto encrypt:raw password:password contentType:RYGBackupContentArchive error:&err] : nil;
				ok = enc && [enc writeToURL:out options:NSDataWritingAtomic error:&err];
			}
			[RYGTempFiles releaseURL:tmp];
		} else {
			ok = [RYGArchive createArchiveAtURL:out rootDirs:roots extraFiles:@{ @"manifest.json": payload } error:&err];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!ok) {
				[h error:(err.localizedDescription ?: RYGLocalized(@"Could not write backup file."))];
				[RYGTempFiles releaseURL:out];
				return;
			}
			[self presentExportPickerForURL:out scope:scope archived:YES handle:h];
		});
	});
}

+ (void)presentExportPickerForURL:(NSURL *)out scope:(RYGBackupCat)scope archived:(BOOL)archived handle:(RYGNotificationHandle *)handle {
	unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:out.path error:nil] fileSize];
	NSLog(@"[RyukGram][Backup] export scope=%ld format=%@ size=%llu file=%@", (long)scope, archived ? @"ryukbak" : @"json", sz, out.lastPathComponent);

	UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[out]];
	RYGBackupHelper *helper = [RYGBackupHelper shared];
	helper.expectingExportPick = YES;
	helper.exportHandle = handle;
	p.delegate = helper;
	[topMostController() presentViewController:p animated:YES completion:nil];
}

#pragma mark - Import

+ (void)presentImport { [self pickFromFiles]; }

+ (void)pickFromFiles {
	UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json", @"public.text", @"public.data"]
																							  inMode:UIDocumentPickerModeImport];
	p.delegate = [RYGBackupHelper shared];
	p.allowsMultipleSelection = NO;
	[topMostController() presentViewController:p animated:YES completion:nil];
}

// Reshape a pre-v3 envelope. v2 "lists" were the active account's filters, so
// restore them onto the current account.
+ (NSDictionary *)normalizeLegacyEnvelope:(NSDictionary *)root {
	// Dev-era envelopes carried read receipts as a top-level section.
	if ([root[@"read_receipts"] isKindOfClass:NSDictionary.class] && ![root[@"feature_data"] isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *m = [root mutableCopy];
		m[@"feature_data"] = @{ @"read_receipts": root[@"read_receipts"] };
		[m removeObjectForKey:@"read_receipts"];
		root = m;
	}

	id lists = root[@"lists"];
	if (![lists isKindOfClass:NSDictionary.class]) return root;

	NSDictionary *l = lists;
	NSMutableDictionary *out = [root mutableCopy];
	[out removeObjectForKey:@"lists"];

	id embed = l[@"embed_custom_domains"];
	if (rygNonEmpty(embed)) {
		NSMutableDictionary *s = [([out[@"settings"] isKindOfClass:NSDictionary.class] ? out[@"settings"] : @{}) mutableCopy];
		s[@"embed_custom_domains"] = embed;
		out[@"settings"] = s;
	}

	NSMutableDictionary *bucket = [NSMutableDictionary dictionary];
	for (NSString *k in [self filterBaseKeys]) if (rygNonEmpty(l[k])) bucket[k] = l[k];

	NSString *pk = [RYGUtils currentUserPK];
	if (bucket.count && pk.length && ![pk isEqualToString:@"0"]) out[@"filters"] = @{ pk: bucket };

	return out;
}

// Re-prompts on a wrong password instead of aborting the import.
+ (void)promptDecryptForData:(NSData *)data attempt:(NSInteger)attempt {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Encrypted backup")
															 message:attempt > 0 ? RYGLocalized(@"Wrong password. Try again.") : RYGLocalized(@"Enter the password used to protect this backup.")
													  preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = RYGLocalized(@"Password");
		tf.secureTextEntry = YES;
		tf.textContentType = UITextContentTypePassword;
	}];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Unlock") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		NSString *pw = a.textFields.firstObject.text ?: @"";
		if (!pw.length) { [self promptDecryptForData:data attempt:attempt + 1]; return; }
		RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_BACKUP, RYGLocalized(@"Decrypting backup…"), nil);
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSError *err = nil;
			NSData *plain = [RYGBackupCrypto decrypt:data password:pw contentType:NULL error:&err];
			dispatch_async(dispatch_get_main_queue(), ^{
				[h dismiss];
				if (!plain) {
					if (err.code == 1) [self promptDecryptForData:data attempt:attempt + 1];
					else [self showError:err.localizedDescription ?: RYGLocalized(@"Could not read the backup archive.")];
					return;
				}
				[self presentApplyConfirmationForData:plain];
			});
		});
	}]];
	[topMostController() presentViewController:a animated:YES completion:nil];
}

+ (void)presentApplyConfirmationForData:(NSData *)data {
	if ([RYGBackupCrypto dataIsEncrypted:data]) {
		[self promptDecryptForData:data attempt:0];
		return;
	}

	if (![RYGArchive dataLooksLikeArchive:data]) {
		id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		NSDictionary *root = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
		// Legacy/raw settings file: a bare prefs dict with no envelope wrapper.
		if (root && !root[@"ryukgram_export"] && ![self categoriesInEnvelope:root]) {
			root = @{ @"ryukgram_export": @YES, @"settings": root };
		}
		[self continueImportWithRoot:[self normalizeLegacyEnvelope:root] filesDir:nil];
		return;
	}

	// Archive: write + decompress off the main thread (large galleries).
	NSURL *blob = [RYGTempFiles claimWithExt:@"ryukbak" ttl:600 tag:@"imp"];
	NSURL *destDir = [RYGTempFiles claimWithExt:@"dir" ttl:600 tag:@"imp"];
	[[NSFileManager defaultManager] removeItemAtURL:destDir error:nil];

	RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_BACKUP, RYGLocalized(@"Reading backup…"), nil);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		BOOL ok = [data writeToURL:blob options:NSDataWritingAtomic error:&err] &&
				  [RYGArchive extractArchiveAtURL:blob toDirectory:destDir.path error:&err];
		[RYGTempFiles releaseURL:blob];

		NSDictionary *root = nil;
		if (ok) {
			NSData *manifest = [NSData dataWithContentsOfFile:[destDir.path stringByAppendingPathComponent:@"manifest.json"]];
			id parsed = manifest ? [NSJSONSerialization JSONObjectWithData:manifest options:0 error:nil] : nil;
			root = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[h dismiss];
			if (!root) {
				[[NSFileManager defaultManager] removeItemAtURL:destDir error:nil];
				[self showError:err.localizedDescription ?: RYGLocalized(@"Could not read the backup archive.")];
				return;
			}
			[self continueImportWithRoot:[self normalizeLegacyEnvelope:root] filesDir:destDir.path];
		});
	});
}

+ (void)continueImportWithRoot:(NSDictionary *)root filesDir:(NSString *)filesDir {
	void (^cleanup)(void) = ^{ if (filesDir) [[NSFileManager defaultManager] removeItemAtPath:filesDir error:nil]; };

	if (![root isKindOfClass:NSDictionary.class]) { cleanup(); [self showError:RYGLocalized(@"File is not a valid RyukGram backup.")]; return; }

	NSInteger available = [self categoriesInEnvelope:root];
	NSLog(@"[RyukGram][Backup] import source=%@ version=%@ available=%ld", filesDir ? @"ryukbak" : @"json", root[@"version"], (long)available);
	if (!available) { cleanup(); [self showError:RYGLocalized(@"Backup has no importable sections.")]; return; }

	[self presentPickerTitle:RYGLocalized(@"Apply")
					 message:RYGLocalized(@"Tick what to apply. Rows not in this backup are hidden.")
					  loader:^{
		return @{ @"envelope": root, @"available": @(available), @"initial": @(available) };
	}
			 showsImportMode:YES
			 showsEncrypt:NO
					 handler:^(NSInteger scope, NSSet<NSString *> *pks, BOOL merge, __unused NSString *password) {
		NSString *confirmMsg = merge
			? RYGLocalized(@"The backup will be merged into your existing data — nothing is deleted, duplicates are combined. A restart may be needed for everything to take effect.")
			: RYGLocalized(@"Existing data for the ticked items will be replaced. A restart may be needed for everything to take effect.");
		UIAlertController *confirm = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Apply backup?")
																		 message:confirmMsg
																  preferredStyle:UIAlertControllerStyleAlert];
		[confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *_) { cleanup(); }]];
		[confirm addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply") style:(merge ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive) handler:^(__unused UIAlertAction *_) {
			RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_BACKUP, RYGLocalized(@"Applying backup…"), nil);
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				BOOL applied = [self applyImport:root filesDir:filesDir scope:scope pks:pks merge:merge];
				cleanup();
				dispatch_async(dispatch_get_main_queue(), ^{
					[h dismiss];
					if (!applied) { [self showError:RYGLocalized(@"Nothing was applied.")]; return; }
					[self showSuccessHUD:RYGLocalized(@"Import complete")];
					[RYGUtils showRestartConfirmation];
				});
			});
		}]];
		[topMostController() presentViewController:confirm animated:YES completion:nil];
	}];
}

#pragma mark - Reset

+ (NSString *)resetConfirmationMessageForPKs:(NSSet<NSString *> *)pks {
	if (!pks.count) return RYGLocalized(@"This can't be undone.");
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *pk in [self sortedAccountPKs:pks]) [names addObject:[RYGAccountRegistry displayNameForPK:pk]];
	return [NSString stringWithFormat:RYGLocalized(@"Per-account data is cleared for %@ only. Shared data follows its own tick. This can't be undone."),
			[names componentsJoinedByString:@", "]];
}

+ (void)presentReset {
	[self presentPickerTitle:RYGLocalized(@"Reset")
					 message:RYGLocalized(@"Ticked data will be cleared. Tap a row to see what's stored.")
					  loader:^{
		return @{ @"envelope": [self buildEnvelopeForCategories:[self allScopeMask] pks:nil],
				  @"available": @([self allScopeMask]),
				  @"initial": @(0) };
	}
			 showsImportMode:NO
			 showsEncrypt:NO
					 handler:^(NSInteger scope, NSSet<NSString *> *pks, __unused BOOL merge, __unused NSString *password) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Reset selected data?")
																	   message:[self resetConfirmationMessageForPKs:pks]
																preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
			[self resetForScope:scope pks:pks];
			// Restart drops in-memory caches so a wiped store can't resurrect from them.
			RYGBackupCat needsRestart = RYGBackupCatSettings | RYGBackupCatGallery | RYGBackupCatChatBackgrounds | RYGBackupCatDeletedMessages | RYGBackupCatStoriesArchive;
			if (scope & needsRestart) [RYGUtils showRestartConfirmation];
			else [self showSuccessHUD:RYGLocalized(@"Reset complete")];
		}]];
		[topMostController() presentViewController:alert animated:YES completion:nil];
	}];
}

#pragma mark - Clearing from the Storage screen

// Storage lists stores, not prefs — ids map onto data categories only.
+ (NSInteger)scopeForStorageID:(NSString *)storageID {
	NSDictionary *fixed = @{
		@"gallery": @(RYGBackupCatGallery),
		@"chat_backgrounds": @(RYGBackupCatChatBackgrounds),
		@"deleted_messages": @(RYGBackupCatDeletedMessages),
		@"analyzer": @(RYGBackupCatAnalyzer),
		@"stories_archive": @(RYGBackupCatStoriesArchive),
	};
	if (fixed[storageID]) return [fixed[storageID] integerValue];

	__block NSInteger scope = 0;
	[self enumerateFeatureModules:^(NSDictionary *mod, NSInteger bit) {
		if ([mod[@"id"] isEqualToString:storageID]) scope = bit;
	}];
	return scope;
}

+ (NSInteger)allStorageScope {
	NSInteger scope = RYGBackupCatGallery | RYGBackupCatChatBackgrounds | RYGBackupCatDeletedMessages | RYGBackupCatAnalyzer | RYGBackupCatStoriesArchive;
	return scope | [self featureDataMask];
}

+ (void)confirmClearTitle:(NSString *)title
				  message:(NSString *)message
					 work:(dispatch_block_t)work
					 done:(void (^)(BOOL))done {
	if (!work) { if (done) done(NO); return; }

	UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *_) {
		if (done) done(NO);
	}]];
	[a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		RYGNotificationHandle *h = RYGNotifyLoading(RYG_NOTIF_BACKUP, RYGLocalized(@"Working…"), nil);
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			work();
			dispatch_async(dispatch_get_main_queue(), ^{
				[h success:RYGLocalized(@"Clear completed")];
				if (done) done(YES);
			});
		});
	}]];
	[topMostController() presentViewController:a animated:YES completion:nil];
}

+ (void)confirmClearTitle:(NSString *)title
				  message:(NSString *)message
					scope:(NSInteger)scope
					  pks:(NSSet<NSString *> *)pks
					 done:(void (^)(BOOL))done {
	if (!scope) { if (done) done(NO); return; }
	[self confirmClearTitle:title message:message work:^{ [self resetForScope:scope pks:pks]; } done:done];
}

+ (void)presentClearConfirmationForStorageID:(NSString *)storageID
								   accountPK:(NSString *)accountPK
									   label:(NSString *)label
										done:(void (^)(BOOL))done {
	NSString *title = accountPK.length
		? [NSString stringWithFormat:@"%@ · %@", label, [RYGAccountRegistry displayNameForPK:accountPK]]
		: label;

	[self confirmClearTitle:title
					message:RYGLocalized(@"This can't be undone.")
					  scope:[self scopeForStorageID:storageID]
						pks:accountPK.length ? [NSSet setWithObject:accountPK] : nil
					   done:done];
}

+ (void)presentClearConfirmationWithLabel:(NSString *)label
									work:(dispatch_block_t)work
									done:(void (^)(BOOL))done {
	[self confirmClearTitle:label message:RYGLocalized(@"This can't be undone.") work:work done:done];
}

+ (void)presentClearAllStorageConfirmationDone:(void (^)(BOOL))done {
	[self confirmClearTitle:RYGLocalized(@"Clear all data")
					message:RYGLocalized(@"Every stored gallery item, log and recording is deleted from this device. Your settings are kept — use Reset to restore those to defaults. This can't be undone.")
					  scope:[self allStorageScope]
						pks:nil
					   done:done];
}

#pragma mark - Misc

+ (NSString *)timestampString {
	NSDateFormatter *fmt = [NSDateFormatter new];
	fmt.dateFormat = @"yyyyMMdd-HHmmss";
	return [fmt stringFromDate:[NSDate date]];
}

+ (void)showSuccessHUD:(NSString *)message { RYGNotifySuccess(RYG_NOTIF_BACKUP, message, nil); }
+ (void)showError:(NSString *)message { RYGNotifyError(RYG_NOTIF_BACKUP, RYGLocalized(@"Backup failed"), message); }

@end
