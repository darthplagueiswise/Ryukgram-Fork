#import "SCISettingsBackup.h"
#import "TweakSettings.h"
#import "SCISetting.h"
#import "../Utils.h"
#import "../Tweak.h"
#import "../SCIArchive.h"
#import "../SCITempFiles.h"
#import "../SCIAccountScopedDefaults.h"
#import "../Features/ProfileAnalyzer/SCIProfileAnalyzerStorage.h"
#import "../Features/DeletedMessages/SCIDeletedMessagesStorage.h"
#import "../Features/ChatBackground/SCIChatBackgroundManager.h"
#import "../Gallery/SCIGalleryPaths.h"
#import "SCIBackupScopePickerVC.h"
#import <objc/runtime.h>

typedef NS_OPTIONS(NSInteger, SCIBackupCat) {
	SCIBackupCatSettings        = 1 << 0,
	SCIBackupCatFilters         = 1 << 1,
	SCIBackupCatHiddenLocked    = 1 << 2,
	SCIBackupCatAnalyzer        = 1 << 3,
	SCIBackupCatGallery         = 1 << 4,
	SCIBackupCatChatBackgrounds = 1 << 5,
	SCIBackupCatDeletedMessages = 1 << 6,
};

static const SCIBackupCat SCIBackupCatAll =
	SCIBackupCatSettings | SCIBackupCatFilters | SCIBackupCatHiddenLocked | SCIBackupCatAnalyzer |
	SCIBackupCatGallery | SCIBackupCatChatBackgrounds | SCIBackupCatDeletedMessages;

// In-archive prefixes for the file-backed dirs.
static NSString *const kArcGallery = @"files/gallery";
static NSString *const kArcChatBg  = @"files/chat_backgrounds";
static NSString *const kArcDeleted = @"files/deleted_messages";

#pragma mark - Small helpers

static BOOL sciNonEmpty(id v) {
	if ([v isKindOfClass:NSArray.class]) return [(NSArray *)v count] > 0;
	if ([v isKindOfClass:NSDictionary.class]) return [(NSDictionary *)v count] > 0;
	if ([v isKindOfClass:NSString.class]) return [(NSString *)v length] > 0;
	return v != nil;
}

static BOOL sciValidJSON(id v) {
	return v && [NSJSONSerialization isValidJSONObject:@{ @"v": v }];
}

static NSString *sciDocsSub(NSString *sub) {
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	return [docs stringByAppendingPathComponent:sub];
}

// Reuse each feature's own path — single source of truth, no drift.
static NSString *sciGalleryDir(void) { return [SCIGalleryPaths galleryDirectory]; }
static NSString *sciDeletedDir(void) { return [SCIDeletedMessagesStorage storageDirectory]; }
static NSString *sciChatBgDir(void) {
	NSString *p = [[SCIChatBackgroundManager shared] assetsDirectoryURL].path;
	return p.length ? p : sciDocsSub(@"RyukGram/ChatBackgrounds");
}

static void sciDirStats(NSString *dir, NSUInteger *outCount, unsigned long long *outBytes) {
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

static NSString *sciHumanSize(unsigned long long bytes) {
	return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@interface SCISettingsBackup ()
+ (void)showError:(NSString *)message;
+ (void)showSuccessHUD:(NSString *)message;
+ (void)presentApplyConfirmationForData:(NSData *)data;
+ (void)pickFromFiles;
@end

@interface SCIBackupHelper : NSObject <UIDocumentPickerDelegate>
@property (nonatomic) BOOL expectingExportPick;
// Bundle export's loading pill — carried through to success on save.
@property (nonatomic, strong) SCINotificationHandle *exportHandle;
@end

@implementation SCIBackupHelper

+ (instancetype)shared {
	static SCIBackupHelper *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [SCIBackupHelper new]; });
	return s;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (self.expectingExportPick) {
		self.expectingExportPick = NO;
		if (self.exportHandle) { [self.exportHandle success:SCILocalized(@"Backup exported")]; self.exportHandle = nil; }
		else [SCISettingsBackup showSuccessHUD:SCILocalized(@"Backup exported")];
		return;
	}

	NSURL *url = urls.firstObject;
	if (!url) return;

	BOOL access = [url startAccessingSecurityScopedResource];
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (access) [url stopAccessingSecurityScopedResource];

	if (!data) {
		[SCISettingsBackup showError:SCILocalized(@"Could not read file.")];
		return;
	}

	[SCISettingsBackup presentApplyConfirmationForData:data];
}

- (void)documentPickerWasCancelled:(__unused UIDocumentPickerViewController *)controller {
	self.expectingExportPick = NO;
	[self.exportHandle dismiss];
	self.exportHandle = nil;
}

@end

@implementation SCISettingsBackup

#pragma mark - Key groups

+ (NSArray<NSString *> *)filterBaseKeys {
	return @[ @"excluded_threads", @"included_threads", @"excluded_story_users", @"included_story_users" ];
}

+ (NSArray<NSString *> *)hiddenLockedAccountKeys {
	return @[ @"hidden_chats", @"lock_chats_locked_entries", @"share_sheet_pinned_thread_ids" ];
}

+ (NSString *)hiddenLockedGlobalKey { return @"lock_chats_appearance_overrides"; }

+ (NSArray<NSString *> *)chatBgAccountKeys {
	return @[ @"chat_bg_default_asset", @"chat_bg_thread_map", @"chat_bg_thread_meta" ];
}

+ (NSArray<NSString *> *)chatBgGlobalKeys {
	return @[ @"chat_bg_library", @"chat_bg_per_image" ];
}

+ (NSString *)galleryFoldersKey { return @"gallery_folders"; }

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
	[s addObjectsFromArray:@[
		@"lock_passcode_blob",
		@"SCInstaFirstRun",
		@"sci_changelog_last_seen_version",
		@"sci_exp_warning_seen",
		@"sci_internal_gate_crash_pending_keys",
		@"sci_internal_gate_crash_disabled_keys",
		@"sci_internal_gate_crash_last_source",
		@"deleted_messages_seen",
	]];
	return s;
}

+ (NSSet<NSString *> *)allPrefKeys {
	NSMutableSet *keys = [NSMutableSet set];
	[self collectKeysFromSections:[SCITweakSettings sections] into:keys];
	[keys addObjectsFromArray:[[SCIUtils sciRegisteredDefaults] allKeys]];
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
			if (![row isKindOfClass:SCISetting.class]) continue;
			SCISetting *s = row;
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
	for (NSString *k in keys) (void)[SCIAccountScopedDefaults objectForKey:k];
}

+ (NSArray<NSString *> *)knownPKsForKeys:(NSArray<NSString *> *)keys {
	NSMutableSet *pks = [NSMutableSet setWithArray:[SCIAccountScopedDefaults allKnownPKsForBaseKeys:keys]];
	NSString *cur = [SCIUtils currentUserPK];
	if (cur.length && ![cur isEqualToString:@"0"]) [pks addObject:cur];
	return pks.allObjects;
}

// { "<pk>": { key: value } } across every account that has data.
+ (NSDictionary *)collectPerPKForKeys:(NSArray<NSString *> *)keys {
	[self migrateCurrentAccountForKeys:keys];
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *pk in [self knownPKsForKeys:keys]) {
		NSMutableDictionary *bucket = [NSMutableDictionary dictionary];
		for (NSString *k in keys) {
			id v = [SCIAccountScopedDefaults objectForKey:k pk:pk];
			if (sciNonEmpty(v) && sciValidJSON(v)) bucket[k] = v;
		}
		if (bucket.count) out[pk] = bucket;
	}
	return out;
}

+ (void)restorePerPK:(NSDictionary *)map keys:(NSArray<NSString *> *)keys {
	if (![map isKindOfClass:NSDictionary.class]) return;
	NSSet *allowed = [NSSet setWithArray:keys];
	for (NSString *pk in map) {
		NSDictionary *bucket = map[pk];
		if (![bucket isKindOfClass:NSDictionary.class]) continue;
		for (NSString *k in bucket) {
			if ([allowed containsObject:k]) [SCIAccountScopedDefaults setObject:bucket[k] forKey:k pk:pk];
		}
	}
}

+ (void)clearPerPKForKeys:(NSArray<NSString *> *)keys {
	for (NSString *pk in [self knownPKsForKeys:keys]) {
		for (NSString *k in keys) [SCIAccountScopedDefaults removeObjectForKey:k pk:pk];
	}
	for (NSString *k in keys) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
}

#pragma mark - Envelope build

+ (NSUInteger)dirFileCount:(NSString *)dir { NSUInteger c = 0; sciDirStats(dir, &c, NULL); return c; }

// Recorded into the manifest so the import preview shows the backup's size,
// not this device's.
+ (NSDictionary *)fileStatsForDir:(NSString *)dir {
	NSUInteger n = 0; unsigned long long b = 0;
	sciDirStats(dir, &n, &b);
	return @{ @"has_files": @(n > 0), @"file_count": @(n), @"byte_size": @(b) };
}

+ (NSDictionary *)buildEnvelopeForCategories:(SCIBackupCat)cats {
	NSMutableDictionary *root = [NSMutableDictionary dictionary];
	root[@"ryukgram_export"] = @YES;
	root[@"version"] = @3;
	root[@"exported_at"] = @([[NSDate date] timeIntervalSince1970]);

	if (cats & SCIBackupCatSettings) {
		NSMutableDictionary *settings = [NSMutableDictionary dictionary];
		for (NSString *k in [self settingsKeys]) {
			id v = [NSUserDefaults.standardUserDefaults objectForKey:k];
			if (v && sciValidJSON(v)) settings[k] = v;
		}
		root[@"settings"] = settings;
	}

	if (cats & SCIBackupCatFilters) {
		root[@"filters"] = [self collectPerPKForKeys:[self filterBaseKeys]];
	}

	if (cats & SCIBackupCatHiddenLocked) {
		NSMutableDictionary *hl = [NSMutableDictionary dictionary];
		hl[@"accounts"] = [self collectPerPKForKeys:[self hiddenLockedAccountKeys]];
		id ov = [NSUserDefaults.standardUserDefaults objectForKey:[self hiddenLockedGlobalKey]];
		hl[@"global"] = (sciNonEmpty(ov) && sciValidJSON(ov)) ? @{ [self hiddenLockedGlobalKey]: ov } : @{};
		root[@"hidden_locked"] = hl;
	}

	if (cats & SCIBackupCatChatBackgrounds) {
		NSMutableDictionary *cb = [NSMutableDictionary dictionary];
		cb[@"accounts"] = [self collectPerPKForKeys:[self chatBgAccountKeys]];
		NSMutableDictionary *global = [NSMutableDictionary dictionary];
		for (NSString *k in [self chatBgGlobalKeys]) {
			id v = [NSUserDefaults.standardUserDefaults objectForKey:k];
			if (sciNonEmpty(v) && sciValidJSON(v)) global[k] = v;
		}
		cb[@"global"] = global;
		[cb addEntriesFromDictionary:[self fileStatsForDir:sciChatBgDir()]];
		root[@"chat_backgrounds"] = cb;
	}

	if (cats & SCIBackupCatGallery) {
		NSMutableDictionary *g = [NSMutableDictionary dictionary];
		id folders = [NSUserDefaults.standardUserDefaults objectForKey:[self galleryFoldersKey]];
		if (sciNonEmpty(folders) && sciValidJSON(folders)) g[[self galleryFoldersKey]] = folders;
		[g addEntriesFromDictionary:[self fileStatsForDir:sciGalleryDir()]];
		root[@"gallery"] = g;
	}

	if (cats & SCIBackupCatDeletedMessages) {
		root[@"deleted_messages"] = [self fileStatsForDir:sciDeletedDir()];
	}

	if (cats & SCIBackupCatAnalyzer) {
		root[@"analyzer"] = [SCIProfileAnalyzerStorage exportedDict] ?: @{};
	}

	return root;
}

+ (NSDictionary<NSString *, NSString *> *)archiveRootDirsForCategories:(SCIBackupCat)cats {
	NSMutableDictionary *roots = [NSMutableDictionary dictionary];
	if ((cats & SCIBackupCatGallery) && [self dirFileCount:sciGalleryDir()] > 0) roots[kArcGallery] = sciGalleryDir();
	if ((cats & SCIBackupCatChatBackgrounds) && [self dirFileCount:sciChatBgDir()] > 0) roots[kArcChatBg] = sciChatBgDir();
	if ((cats & SCIBackupCatDeletedMessages) && [self dirFileCount:sciDeletedDir()] > 0) roots[kArcDeleted] = sciDeletedDir();
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

+ (BOOL)applyImport:(NSDictionary *)root filesDir:(NSString *)filesDir scope:(SCIBackupCat)scope {
	if (![root isKindOfClass:NSDictionary.class]) return NO;
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL any = NO;

	if ((scope & SCIBackupCatSettings) && [root[@"settings"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *settings = root[@"settings"];
		NSSet *keys = [self settingsKeys];
		for (NSString *k in keys) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
		for (NSString *k in settings) if ([keys containsObject:k]) [NSUserDefaults.standardUserDefaults setObject:settings[k] forKey:k];
		any = YES;
	}

	if ((scope & SCIBackupCatFilters) && [root[@"filters"] isKindOfClass:NSDictionary.class]) {
		[self restorePerPK:root[@"filters"] keys:[self filterBaseKeys]];
		any = YES;
	}

	if ((scope & SCIBackupCatHiddenLocked) && [root[@"hidden_locked"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *hl = root[@"hidden_locked"];
		[self restorePerPK:hl[@"accounts"] keys:[self hiddenLockedAccountKeys]];
		NSDictionary *global = [hl[@"global"] isKindOfClass:NSDictionary.class] ? hl[@"global"] : nil;
		id ov = global[[self hiddenLockedGlobalKey]];
		if (sciNonEmpty(ov)) [NSUserDefaults.standardUserDefaults setObject:ov forKey:[self hiddenLockedGlobalKey]];
		any = YES;
	}

	if ((scope & SCIBackupCatChatBackgrounds) && [root[@"chat_backgrounds"] isKindOfClass:NSDictionary.class]) {
		NSDictionary *cb = root[@"chat_backgrounds"];
		[self restorePerPK:cb[@"accounts"] keys:[self chatBgAccountKeys]];
		NSDictionary *global = [cb[@"global"] isKindOfClass:NSDictionary.class] ? cb[@"global"] : @{};
		for (NSString *k in [self chatBgGlobalKeys]) if (global[k]) [NSUserDefaults.standardUserDefaults setObject:global[k] forKey:k];
		[self restoreDir:sciChatBgDir() fromExtracted:[filesDir stringByAppendingPathComponent:kArcChatBg] fm:fm];
		any = YES;
	}

	if ((scope & SCIBackupCatGallery) && [root[@"gallery"] isKindOfClass:NSDictionary.class]) {
		id folders = root[@"gallery"][[self galleryFoldersKey]];
		if (folders) [NSUserDefaults.standardUserDefaults setObject:folders forKey:[self galleryFoldersKey]];
		[self restoreDir:sciGalleryDir() fromExtracted:[filesDir stringByAppendingPathComponent:kArcGallery] fm:fm];
		any = YES;
	}

	if ((scope & SCIBackupCatDeletedMessages) && [root[@"deleted_messages"] isKindOfClass:NSDictionary.class]) {
		[self restoreDir:sciDeletedDir() fromExtracted:[filesDir stringByAppendingPathComponent:kArcDeleted] fm:fm];
		any = YES;
	}

	if ((scope & SCIBackupCatAnalyzer) && [root[@"analyzer"] isKindOfClass:NSDictionary.class]) {
		[SCIProfileAnalyzerStorage importFromDict:root[@"analyzer"]];
		any = YES;
	}

	NSLog(@"[SCInsta][Backup] applied scope=%ld any=%d", (long)scope, any);
	if (any) [NSUserDefaults.standardUserDefaults synchronize];
	return any;
}

// Replace `target` with the extracted copy (move, fall back to copy cross-volume).
+ (void)restoreDir:(NSString *)target fromExtracted:(NSString *)extracted fm:(NSFileManager *)fm {
	BOOL isDir = NO;
	if (!extracted.length || ![fm fileExistsAtPath:extracted isDirectory:&isDir] || !isDir) return;
	[fm removeItemAtPath:target error:nil];
	[fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
	if (![fm moveItemAtPath:extracted toPath:target error:nil]) {
		[fm copyItemAtPath:extracted toPath:target error:nil];
	}
}

#pragma mark - Reset

+ (void)resetForScope:(SCIBackupCat)scope {
	NSFileManager *fm = [NSFileManager defaultManager];

	if (scope & SCIBackupCatSettings) {
		for (NSString *k in [self settingsKeys]) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
	}
	if (scope & SCIBackupCatFilters) [self clearPerPKForKeys:[self filterBaseKeys]];
	if (scope & SCIBackupCatHiddenLocked) {
		[self clearPerPKForKeys:[self hiddenLockedAccountKeys]];
		[NSUserDefaults.standardUserDefaults removeObjectForKey:[self hiddenLockedGlobalKey]];
	}
	if (scope & SCIBackupCatChatBackgrounds) {
		[self clearPerPKForKeys:[self chatBgAccountKeys]];
		for (NSString *k in [self chatBgGlobalKeys]) [NSUserDefaults.standardUserDefaults removeObjectForKey:k];
		[fm removeItemAtPath:sciChatBgDir() error:nil];
	}
	if (scope & SCIBackupCatGallery) {
		[NSUserDefaults.standardUserDefaults removeObjectForKey:[self galleryFoldersKey]];
		[fm removeItemAtPath:sciGalleryDir() error:nil];
	}
	if (scope & SCIBackupCatDeletedMessages) [fm removeItemAtPath:sciDeletedDir() error:nil];
	if (scope & SCIBackupCatAnalyzer) [SCIProfileAnalyzerStorage resetAll];

	[NSUserDefaults.standardUserDefaults synchronize];
}

#pragma mark - Categories present in an envelope

+ (SCIBackupCat)categoriesInEnvelope:(NSDictionary *)root {
	SCIBackupCat c = 0;
	if ([root[@"settings"] isKindOfClass:NSDictionary.class]) c |= SCIBackupCatSettings;
	if ([root[@"filters"] isKindOfClass:NSDictionary.class]) c |= SCIBackupCatFilters;
	if ([root[@"hidden_locked"] isKindOfClass:NSDictionary.class]) c |= SCIBackupCatHiddenLocked;
	if ([root[@"chat_backgrounds"] isKindOfClass:NSDictionary.class]) c |= SCIBackupCatChatBackgrounds;
	if ([root[@"gallery"] isKindOfClass:NSDictionary.class]) c |= SCIBackupCatGallery;
	if ([root[@"deleted_messages"] isKindOfClass:NSDictionary.class]) c |= SCIBackupCatDeletedMessages;
	if ([root[@"analyzer"] isKindOfClass:NSDictionary.class] && [(NSDictionary *)root[@"analyzer"] count]) c |= SCIBackupCatAnalyzer;
	return c;
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
	return @[ @{ @"title": [NSString stringWithFormat:SCILocalized(@"All preferences (%lu)"), (unsigned long)rows.count], @"rows": rows } ];
}

+ (NSArray *)perPKDetailSections:(NSDictionary *)map {
	NSMutableArray *sections = [NSMutableArray array];
	for (NSString *pk in [map.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		NSDictionary *bucket = [map[pk] isKindOfClass:NSDictionary.class] ? map[pk] : @{};
		NSMutableArray *rows = [NSMutableArray array];
		for (NSString *k in [bucket.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
			[rows addObject:@{ @"title": k, @"value": [self displayValue:bucket[k]] }];
		}
		if (!rows.count) [rows addObject:@{ @"title": SCILocalized(@"(empty)"), @"value": @"" }];
		[sections addObject:@{ @"title": [NSString stringWithFormat:SCILocalized(@"PK %@"), pk], @"rows": rows }];
	}
	return sections.count ? sections : @[ @{ @"title": @"", @"rows": @[ @{ @"title": SCILocalized(@"(none)"), @"value": @"" } ] } ];
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
		NSString *header = username.length ? [NSString stringWithFormat:@"@%@", username] : [NSString stringWithFormat:SCILocalized(@"PK %@"), pk];
		NSMutableArray *rows = [NSMutableArray array];
		if (hdr) {
			[rows addObject:@{ @"title": SCILocalized(@"Followers"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"follower_count"] integerValue]] }];
			[rows addObject:@{ @"title": SCILocalized(@"Following"), @"value": [NSString stringWithFormat:@"%ld", (long)[hdr[@"following_count"] integerValue]] }];
		}
		NSDictionary *snaphist = [slot[@"snaphistory"] isKindOfClass:NSDictionary.class] ? slot[@"snaphistory"] : nil;
		NSArray *snaps = [snaphist[@"snapshots"] isKindOfClass:NSArray.class] ? snaphist[@"snapshots"] : @[];
		[rows addObject:@{ @"title": SCILocalized(@"Archived snapshots"), @"value": [NSString stringWithFormat:@"%lu", (unsigned long)snaps.count] }];
		[sections addObject:@{ @"title": header, @"rows": rows }];
	}
	return sections.count ? sections : @[ @{ @"title": @"", @"rows": @[ @{ @"title": SCILocalized(@"(no analyzer data)"), @"value": @"" } ] } ];
}

// Ordered row descriptors for the picker. `available` gates which rows show.
+ (NSArray<NSDictionary *> *)rowDescriptorsForAvailable:(SCIBackupCat)available envelope:(NSDictionary *)env {
	NSMutableArray *rows = [NSMutableArray array];

	void (^add)(SCIBackupCat, NSString *, NSString *, NSString *, UIColor *, NSArray *) =
	^(SCIBackupCat bit, NSString *title, NSString *subtitle, NSString *symbol, UIColor *color, NSArray *detail) {
		if (!(available & bit)) return;
		NSMutableDictionary *d = [@{ @"bit": @(bit), @"title": title, @"subtitle": subtitle ?: @"", @"symbol": symbol, @"color": color } mutableCopy];
		if (detail) d[@"detailSections"] = detail;
		[rows addObject:d];
	};

	NSDictionary *settings = [env[@"settings"] isKindOfClass:NSDictionary.class] ? env[@"settings"] : @{};
	add(SCIBackupCatSettings, SCILocalized(@"Settings"),
		[NSString stringWithFormat:SCILocalized(@"%lu preferences"), (unsigned long)settings.count],
		@"slider.horizontal.3", UIColor.systemBlueColor, [self settingsDetailSections:settings]);

	NSDictionary *filters = [env[@"filters"] isKindOfClass:NSDictionary.class] ? env[@"filters"] : @{};
	add(SCIBackupCatFilters, SCILocalized(@"Chat & story filters"),
		[NSString stringWithFormat:SCILocalized(@"%lu account(s)"), (unsigned long)filters.count],
		@"person.crop.circle.badge.xmark", UIColor.systemOrangeColor, [self perPKDetailSections:filters]);

	NSDictionary *hl = [env[@"hidden_locked"] isKindOfClass:NSDictionary.class] ? env[@"hidden_locked"] : @{};
	NSDictionary *hlAcc = [hl[@"accounts"] isKindOfClass:NSDictionary.class] ? hl[@"accounts"] : @{};
	add(SCIBackupCatHiddenLocked, SCILocalized(@"Hidden & locked chats"),
		[NSString stringWithFormat:SCILocalized(@"%lu account(s)"), (unsigned long)hlAcc.count],
		@"lock.fill", UIColor.systemIndigoColor, [self perPKDetailSections:hlAcc]);

	NSDictionary *analyzer = [env[@"analyzer"] isKindOfClass:NSDictionary.class] ? env[@"analyzer"] : @{};
	NSMutableSet *aPks = [NSMutableSet set];
	for (NSString *f in analyzer) { NSArray *p = [f componentsSeparatedByString:@"."]; if (p.count) [aPks addObject:p[0]]; }
	add(SCIBackupCatAnalyzer, SCILocalized(@"Profile Analyzer data"),
		[NSString stringWithFormat:SCILocalized(@"%lu account(s)"), (unsigned long)aPks.count],
		@"person.fill.viewfinder", ([SCIUtils SCIColor_Primary] ?: UIColor.systemBlueColor), [self analyzerDetailSections:analyzer]);

	// File stats from the envelope (manifest on import) — describe the backup, not the device.
	NSDictionary *(^fileDict)(NSString *) = ^NSDictionary *(NSString *key) {
		return [env[key] isKindOfClass:NSDictionary.class] ? env[key] : @{};
	};

	NSDictionary *gal = fileDict(@"gallery");
	add(SCIBackupCatGallery, SCILocalized(@"Gallery"),
		[NSString stringWithFormat:SCILocalized(@"%lu file(s) · %@"),
			(unsigned long)[gal[@"file_count"] unsignedIntegerValue], sciHumanSize([gal[@"byte_size"] unsignedLongLongValue])],
		@"photo.on.rectangle.angled", UIColor.systemPinkColor, nil);

	NSDictionary *cb = fileDict(@"chat_backgrounds");
	NSDictionary *cbAcc = [cb[@"accounts"] isKindOfClass:NSDictionary.class] ? cb[@"accounts"] : @{};
	add(SCIBackupCatChatBackgrounds, SCILocalized(@"Chat backgrounds"),
		[NSString stringWithFormat:SCILocalized(@"%lu account(s) · %lu image(s) · %@"),
			(unsigned long)cbAcc.count, (unsigned long)[cb[@"file_count"] unsignedIntegerValue], sciHumanSize([cb[@"byte_size"] unsignedLongLongValue])],
		@"photo.artframe", UIColor.systemTealColor, nil);

	NSDictionary *del = fileDict(@"deleted_messages");
	add(SCIBackupCatDeletedMessages, SCILocalized(@"Deleted messages"),
		[NSString stringWithFormat:SCILocalized(@"%lu file(s) · %@"),
			(unsigned long)[del[@"file_count"] unsignedIntegerValue], sciHumanSize([del[@"byte_size"] unsignedLongLongValue])],
		@"trash.fill", UIColor.systemBrownColor, nil);

	return rows;
}

#pragma mark - Picker presentation

+ (void)presentPickerTitle:(NSString *)continueTitle
				   message:(NSString *)message
				 available:(SCIBackupCat)available
				   initial:(SCIBackupCat)initial
				  envelope:(NSDictionary *)envelope
				   handler:(void(^)(SCIBackupCat))handler {
	SCIBackupScopePickerVC *vc = [SCIBackupScopePickerVC new];
	vc.title = continueTitle;
	vc.continueTitle = continueTitle;
	vc.headerMessage = message;
	vc.rows = [self rowDescriptorsForAvailable:available envelope:envelope];
	vc.initialSelection = (NSInteger)(initial & available);
	NSData *raw = [self serializeJSON:envelope];
	vc.rawJSON = [[NSString alloc] initWithData:(raw ?: [NSData data]) encoding:NSUTF8StringEncoding] ?: @"{}";
	vc.onContinue = ^(NSInteger chosen) { if (handler) handler((SCIBackupCat)chosen); };

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[topMostController() presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Export

+ (void)presentExport {
	NSDictionary *preview = [self buildEnvelopeForCategories:SCIBackupCatAll];
	// Export All preselects everything except Gallery (opt-in — can be large).
	SCIBackupCat initial = SCIBackupCatAll & ~SCIBackupCatGallery;

	[self presentPickerTitle:SCILocalized(@"Export")
					 message:SCILocalized(@"Tick what to include. Tap a row to inspect it. Adding gallery, chat backgrounds or deleted messages produces a compressed .ryukbak bundle.")
				   available:SCIBackupCatAll
					 initial:initial
					envelope:preview
					 handler:^(SCIBackupCat scope) {
		[self writeExportForScope:scope];
	}];
}

+ (void)writeExportForScope:(SCIBackupCat)scope {
	NSDictionary *envelope = [self buildEnvelopeForCategories:scope];
	NSDictionary<NSString *, NSString *> *roots = [self archiveRootDirsForCategories:scope];
	NSData *payload = [self serializeJSON:envelope];
	NSString *stamp = [self timestampString];

	// No media: small, write inline.
	if (roots.count == 0) {
		NSURL *out = [SCITempFiles claimNamedFile:[NSString stringWithFormat:@"RyukGram-backup-%@.json", stamp] ttl:900 tag:@"backup"];
		if (!payload || ![payload writeToURL:out options:NSDataWritingAtomic error:nil]) {
			[SCITempFiles releaseURL:out];
			[self showError:SCILocalized(@"Could not write backup file.")];
			return;
		}
		[self presentExportPickerForURL:out scope:scope archived:NO handle:nil];
		return;
	}

	// Media bundle: compress off-main (slow on a big gallery), pill carries to success.
	NSURL *out = [SCITempFiles claimNamedFile:[NSString stringWithFormat:@"RyukGram-backup-%@.ryukbak", stamp] ttl:900 tag:@"backup"];
	SCINotificationHandle *h = SCINotifyLoading(SCI_NOTIF_BACKUP, SCILocalized(@"Preparing backup…"), nil);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		BOOL ok = [SCIArchive createArchiveAtURL:out rootDirs:roots extraFiles:@{ @"manifest.json": payload } error:&err];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!ok) {
				[h error:(err.localizedDescription ?: SCILocalized(@"Could not write backup file."))];
				[SCITempFiles releaseURL:out];
				return;
			}
			[self presentExportPickerForURL:out scope:scope archived:YES handle:h];
		});
	});
}

+ (void)presentExportPickerForURL:(NSURL *)out scope:(SCIBackupCat)scope archived:(BOOL)archived handle:(SCINotificationHandle *)handle {
	unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:out.path error:nil] fileSize];
	NSLog(@"[SCInsta][Backup] export scope=%ld format=%@ size=%llu file=%@", (long)scope, archived ? @"ryukbak" : @"json", sz, out.lastPathComponent);

	UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[out]];
	SCIBackupHelper *helper = [SCIBackupHelper shared];
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
	p.delegate = [SCIBackupHelper shared];
	p.allowsMultipleSelection = NO;
	[topMostController() presentViewController:p animated:YES completion:nil];
}

// Reshape a pre-v3 envelope. v2 "lists" were the active account's filters, so
// restore them onto the current account.
+ (NSDictionary *)normalizeLegacyEnvelope:(NSDictionary *)root {
	id lists = root[@"lists"];
	if (![lists isKindOfClass:NSDictionary.class]) return root;

	NSDictionary *l = lists;
	NSMutableDictionary *out = [root mutableCopy];
	[out removeObjectForKey:@"lists"];

	id embed = l[@"embed_custom_domains"];
	if (sciNonEmpty(embed)) {
		NSMutableDictionary *s = [([out[@"settings"] isKindOfClass:NSDictionary.class] ? out[@"settings"] : @{}) mutableCopy];
		s[@"embed_custom_domains"] = embed;
		out[@"settings"] = s;
	}

	NSMutableDictionary *bucket = [NSMutableDictionary dictionary];
	for (NSString *k in [self filterBaseKeys]) if (sciNonEmpty(l[k])) bucket[k] = l[k];

	NSString *pk = [SCIUtils currentUserPK];
	if (bucket.count && pk.length && ![pk isEqualToString:@"0"]) out[@"filters"] = @{ pk: bucket };

	return out;
}

+ (void)presentApplyConfirmationForData:(NSData *)data {
	if (![SCIArchive dataLooksLikeArchive:data]) {
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
	NSURL *blob = [SCITempFiles claimWithExt:@"ryukbak" ttl:600 tag:@"imp"];
	NSURL *destDir = [SCITempFiles claimWithExt:@"dir" ttl:600 tag:@"imp"];
	[[NSFileManager defaultManager] removeItemAtURL:destDir error:nil];

	SCINotificationHandle *h = SCINotifyLoading(SCI_NOTIF_BACKUP, SCILocalized(@"Reading backup…"), nil);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		BOOL ok = [data writeToURL:blob options:NSDataWritingAtomic error:&err] &&
				  [SCIArchive extractArchiveAtURL:blob toDirectory:destDir.path error:&err];
		[SCITempFiles releaseURL:blob];

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
				[self showError:err.localizedDescription ?: SCILocalized(@"Could not read the backup archive.")];
				return;
			}
			[self continueImportWithRoot:[self normalizeLegacyEnvelope:root] filesDir:destDir.path];
		});
	});
}

+ (void)continueImportWithRoot:(NSDictionary *)root filesDir:(NSString *)filesDir {
	void (^cleanup)(void) = ^{ if (filesDir) [[NSFileManager defaultManager] removeItemAtPath:filesDir error:nil]; };

	if (![root isKindOfClass:NSDictionary.class]) { cleanup(); [self showError:SCILocalized(@"File is not a valid RyukGram backup.")]; return; }

	SCIBackupCat available = [self categoriesInEnvelope:root];
	NSLog(@"[SCInsta][Backup] import source=%@ version=%@ available=%ld", filesDir ? @"ryukbak" : @"json", root[@"version"], (long)available);
	if (!available) { cleanup(); [self showError:SCILocalized(@"Backup has no importable sections.")]; return; }

	[self presentPickerTitle:SCILocalized(@"Apply")
					 message:SCILocalized(@"Tick what to apply. Rows not in this backup are hidden.")
				   available:available
					 initial:available
					envelope:root
					 handler:^(SCIBackupCat scope) {
		UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Apply backup?")
																		 message:SCILocalized(@"Existing data for the ticked items will be replaced. A restart may be needed for everything to take effect.")
																  preferredStyle:UIAlertControllerStyleAlert];
		[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *_) { cleanup(); }]];
		[confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Apply") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
			SCINotificationHandle *h = SCINotifyLoading(SCI_NOTIF_BACKUP, SCILocalized(@"Applying backup…"), nil);
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				BOOL applied = [self applyImport:root filesDir:filesDir scope:scope];
				cleanup();
				dispatch_async(dispatch_get_main_queue(), ^{
					[h dismiss];
					if (!applied) { [self showError:SCILocalized(@"Nothing was applied.")]; return; }
					[self showSuccessHUD:SCILocalized(@"Import complete")];
					[SCIUtils showRestartConfirmation];
				});
			});
		}]];
		[topMostController() presentViewController:confirm animated:YES completion:nil];
	}];
}

#pragma mark - Reset

+ (void)presentReset {
	NSDictionary *preview = [self buildEnvelopeForCategories:SCIBackupCatAll];
	[self presentPickerTitle:SCILocalized(@"Reset")
					 message:SCILocalized(@"Ticked data will be cleared. Tap a row to see what's stored.")
				   available:SCIBackupCatAll
					 initial:0
					envelope:preview
					 handler:^(SCIBackupCat scope) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Reset selected data?")
																	   message:SCILocalized(@"This can't be undone.")
																preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
			[self resetForScope:scope];
			// Restart drops in-memory caches so a wiped store can't resurrect from them.
			SCIBackupCat needsRestart = SCIBackupCatSettings | SCIBackupCatGallery | SCIBackupCatChatBackgrounds | SCIBackupCatDeletedMessages;
			if (scope & needsRestart) [SCIUtils showRestartConfirmation];
			else [self showSuccessHUD:SCILocalized(@"Reset complete")];
		}]];
		[topMostController() presentViewController:alert animated:YES completion:nil];
	}];
}

#pragma mark - Misc

+ (NSString *)timestampString {
	NSDateFormatter *fmt = [NSDateFormatter new];
	fmt.dateFormat = @"yyyyMMdd-HHmmss";
	return [fmt stringFromDate:[NSDate date]];
}

+ (void)showSuccessHUD:(NSString *)message { SCINotifySuccess(SCI_NOTIF_BACKUP, message, nil); }
+ (void)showError:(NSString *)message { SCINotifyError(SCI_NOTIF_BACKUP, SCILocalized(@"Backup failed"), message); }

@end
