#import "RYGStorageUsage.h"
#import "../Localization/RYGLocalization.h"
#import "../RYGAccountRegistry.h"
#import "../UI/RYGFeatureIcons.h"
#import "../Features/ProfileAnalyzer/RYGProfileAnalyzerStorage.h"
#import "../Features/StoriesArchive/RYGStoriesArchiveStore.h"
#import "../Features/DeletedMessages/RYGDeletedMessagesStorage.h"
#import "../Features/ReadReceipts/RYGReadReceiptStorage.h"
#import "../Features/FollowRequests/RYGFollowRequestStorage.h"
#import "../Features/CallRecordings/RYGCallRecordingStorage.h"
#import "../Features/ChatBackground/RYGChatBackgroundManager.h"
#import "../Gallery/RYGGalleryPaths.h"
#import "../Downloader/RYGDownloadHistory.h"
#import <stdatomic.h>

static NSString *const kRYGStorageMediaDir = @"media";
static NSString *const kRYGStorageOtherPK = @"";

static _Atomic(unsigned long long) gCachedTotal = 0;

@interface RYGStorageAccountEntry ()
@property (nonatomic, copy) NSString *pk;
@property (nonatomic) unsigned long long byteSize;
@property (nonatomic) NSUInteger fileCount;
@end

@implementation RYGStorageAccountEntry
- (NSString *)displayName {
	if (!self.pk.length) return RYGLocalized(@"Other");
	return [RYGAccountRegistry displayNameForPK:self.pk];
}
@end

@interface RYGStorageEntry ()
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) RYGSymbol *symbol;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) unsigned long long byteSize;
@property (nonatomic) NSUInteger fileCount;
@property (nonatomic, copy, nullable) NSArray<RYGStorageAccountEntry *> *accounts;
@end

@implementation RYGStorageEntry
@end

static BOOL rygIsPK(NSString *c) {
	if (!c.length) return NO;
	if ([c isEqualToString:@"anon"]) return YES;
	static NSCharacterSet *nonDigits;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ nonDigits = [NSCharacterSet decimalDigitCharacterSet].invertedSet; });
	return [c rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

static NSString *rygPKForRelativePath(NSString *rel) {
	NSArray<NSString *> *comps = rel.pathComponents;
	if (!comps.count) return nil;
	if (comps.count >= 3 && [comps[0] isEqualToString:kRYGStorageMediaDir] && rygIsPK(comps[1])) return comps[1];
	NSString *head = [comps[0] componentsSeparatedByString:@"."].firstObject;
	return rygIsPK(head) ? head : nil;
}

static NSString *rygInstantsDir(void) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	return [root stringByAppendingPathComponent:@"RyukGram/InstantsAutoSave"];
}

static NSString *rygChatBgDir(void) {
	NSString *p = [[RYGChatBackgroundManager shared] assetsDirectoryURL].path;
	if (p.length) return p;
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	return [docs stringByAppendingPathComponent:@"RyukGram/ChatBackgrounds"];
}

static RYGStorageEntry *rygScanDir(NSString *dir, NSString *identifier, NSString *title, RYGSymbol *symbol, UIColor *color, BOOL perAccount) {
	RYGStorageEntry *entry = [RYGStorageEntry new];
	entry.identifier = identifier;
	entry.title = title;
	entry.symbol = symbol;
	entry.color = color;

	NSUInteger count = 0;
	unsigned long long bytes = 0;
	NSMutableDictionary<NSString *, RYGStorageAccountEntry *> *byPK = perAccount ? [NSMutableDictionary dictionary] : nil;

	NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
	for (NSString *rel in en) {
		if (![en.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) continue;
		unsigned long long size = en.fileAttributes.fileSize;
		count++;
		bytes += size;
		if (!perAccount) continue;

		NSString *pk = rygPKForRelativePath(rel) ?: kRYGStorageOtherPK;
		RYGStorageAccountEntry *acc = byPK[pk];
		if (!acc) {
			acc = [RYGStorageAccountEntry new];
			acc.pk = pk;
			byPK[pk] = acc;
		}
		acc.byteSize += size;
		acc.fileCount++;
	}

	entry.fileCount = count;
	entry.byteSize = bytes;
	if (perAccount) {
		entry.accounts = [byPK.allValues sortedArrayUsingComparator:^NSComparisonResult(RYGStorageAccountEntry *a, RYGStorageAccountEntry *b) {
			if (a.byteSize != b.byteSize) return a.byteSize > b.byteSize ? NSOrderedAscending : NSOrderedDescending;
			return [a.pk compare:b.pk];
		}];
	}
	return entry;
}

@implementation RYGStorageUsage

+ (NSString *)accountPKForRelativePath:(NSString *)relativePath { return rygPKForRelativePath(relativePath); }

+ (void)scanWithCompletion:(nullable void (^)(NSArray<RYGStorageEntry *> *, unsigned long long))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSArray<NSDictionary *> *descriptors = @[
			@{ @"dir": [RYGGalleryPaths galleryDirectory] ?: @"",
			   @"id": @"gallery",
			   @"title": RYGLocalized(@"Gallery"),
			   @"symbol": [RYGFeatureIcons gallery],
			   @"color": UIColor.systemPinkColor,
			   @"accounts": @NO },
			@{ @"dir": rygChatBgDir(),
			   @"id": @"chat_backgrounds",
			   @"title": RYGLocalized(@"Chat backgrounds"),
			   @"symbol": [RYGFeatureIcons chatBackgroundsFilled],
			   @"color": UIColor.systemTealColor,
			   @"accounts": @NO },
			@{ @"dir": [RYGDeletedMessagesStorage storageDirectory] ?: @"",
			   @"id": @"deleted_messages",
			   @"title": RYGLocalized(@"Deleted messages"),
			   @"symbol": [RYGFeatureIcons deletedMessagesFilled],
			   @"color": UIColor.systemBrownColor,
			   @"accounts": @YES },
			@{ @"dir": [RYGProfileAnalyzerStorage storageDirectory] ?: @"",
			   @"id": @"analyzer",
			   @"title": RYGLocalized(@"Profile Analyzer data"),
			   @"symbol": [RYGFeatureIcons profileAnalyzer],
			   @"color": UIColor.systemPurpleColor,
			   @"accounts": @YES },
			@{ @"dir": [RYGStoriesArchiveStore storageDirectory] ?: @"",
			   @"id": @"stories_archive",
			   @"title": RYGLocalized(@"Stories archive"),
			   @"symbol": [RYGFeatureIcons storiesArchive],
			   @"color": UIColor.systemCyanColor,
			   @"accounts": @YES },
			@{ @"dir": [RYGCallRecordingStorage storageDirectory] ?: @"",
			   @"id": @"call_recordings",
			   @"title": RYGLocalized(@"Call recordings"),
			   @"symbol": [RYGFeatureIcons callRecordingsFilled],
			   @"color": UIColor.systemRedColor,
			   @"accounts": @YES },
			@{ @"dir": [RYGReadReceiptStorage storageDirectory] ?: @"",
			   @"id": @"read_receipts",
			   @"title": RYGLocalized(@"Read receipts log"),
			   @"symbol": [RYGFeatureIcons readReceiptsFilled],
			   @"color": UIColor.systemGreenColor,
			   @"accounts": @YES },
			@{ @"dir": [RYGFollowRequestStorage storageDirectory] ?: @"",
			   @"id": @"follow_requests",
			   @"title": RYGLocalized(@"Follow requests log"),
			   @"symbol": [RYGFeatureIcons followRequests],
			   @"color": UIColor.systemBlueColor,
			   @"accounts": @YES },
			@{ @"dir": rygInstantsDir(),
			   @"id": @"instants_auto_save",
			   @"title": RYGLocalized(@"Auto-saved instants log"),
			   @"symbol": [RYGFeatureIcons instantsFilled],
			   @"color": UIColor.systemYellowColor,
			   @"accounts": @NO },
			@{ @"dir": [RYGDownloadHistory storageDirectory] ?: @"",
			   @"id": @"download_history",
			   @"title": RYGLocalized(@"Download history"),
			   @"symbol": [RYGFeatureIcons downloadsFilled],
			   @"color": UIColor.systemIndigoColor,
			   @"accounts": @NO },
		];

		NSMutableArray<RYGStorageEntry *> *entries = [NSMutableArray array];
		unsigned long long total = 0;
		for (NSDictionary *d in descriptors) {
			RYGStorageEntry *e = rygScanDir(d[@"dir"], d[@"id"], d[@"title"], d[@"symbol"], d[@"color"], [d[@"accounts"] boolValue]);
			[entries addObject:e];
			total += e.byteSize;
		}
		[entries sortUsingComparator:^NSComparisonResult(RYGStorageEntry *a, RYGStorageEntry *b) {
			if (a.byteSize != b.byteSize) return a.byteSize > b.byteSize ? NSOrderedAscending : NSOrderedDescending;
			return [a.title localizedCaseInsensitiveCompare:b.title];
		}];

		atomic_store(&gCachedTotal, total);
		NSMutableArray<NSString *> *pks = [NSMutableArray array];
		for (RYGStorageEntry *e in entries)
			for (RYGStorageAccountEntry *a in e.accounts) if (a.pk.length) [pks addObject:a.pk];

		dispatch_async(dispatch_get_main_queue(), ^{
			// Any scan is a chance to name an account we only know by pk.
			[RYGAccountRegistry resolveMissingNamesForPKs:pks];
			if (completion) completion(entries, total);
		});
	});
}

+ (unsigned long long)cachedTotal { return atomic_load(&gCachedTotal); }

+ (void)refreshTotalInBackground { [self scanWithCompletion:nil]; }

+ (NSString *)formattedSize:(unsigned long long)bytes {
	return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@end
