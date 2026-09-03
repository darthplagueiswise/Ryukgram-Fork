#import "RYGNSEImport.h"
#import "RYGNSEConfig.h"
#import "RYGDeletedMessagesModels.h"
#import "RYGDeletedMessagesStorage.h"
#import "../Feed/RYGHomeShortcutBadges.h"
#import "../../Utils.h"
#import "../../RYGOSLog.h"

static NSString *rygStagingRoot(void) {
    NSString *base = [RYGNSEConfig sharedDir];
    if (!base) return nil;
    NSString *d = [base stringByAppendingPathComponent:@"nse_staging"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

// Absolute path of each per-account staging dir.
static NSArray<NSString *> *rygOwnerDirs(NSFileManager *fm, NSString *root) {
    NSMutableArray *dirs = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]) {
        NSString *p = [root stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) [dirs addObject:p];
    }
    return dirs;
}

static dispatch_queue_t rygQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryuk.ryukgram.nseimport", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static NSDictionary *rygSidecar(NSString *dir, NSString *itemId) {
    NSData *d = [NSData dataWithContentsOfFile:[[dir stringByAppendingPathComponent:itemId] stringByAppendingPathExtension:@"json"]];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : nil;
}

static void rygRemoveStaged(NSFileManager *fm, NSString *dir, NSString *itemId, NSDictionary *rec) {
    for (NSString *ext in @[@"json", @"deleted"]) [fm removeItemAtPath:[[dir stringByAppendingPathComponent:itemId] stringByAppendingPathExtension:ext] error:nil];
    NSString *mf = [rec[@"mediaFile"] description]; if (mf.length) [fm removeItemAtPath:[dir stringByAppendingPathComponent:mf] error:nil];
    NSString *tf = [rec[@"thumbFile"] description]; if (tf.length) [fm removeItemAtPath:[dir stringByAppendingPathComponent:tf] error:nil];
}

// Item ids staged in `dir` that are NOT flagged unsent, oldest first.
static NSArray<NSString *> *rygUndeleted(NSFileManager *fm, NSString *dir) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (NSString *n in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if (![n.pathExtension isEqualToString:@"json"]) continue;
        NSString *itemId = n.stringByDeletingPathExtension;
        if ([fm fileExistsAtPath:[[dir stringByAppendingPathComponent:itemId] stringByAppendingPathExtension:@"deleted"]]) continue;
        [ids addObject:itemId];
    }
    [ids sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double ca = [rygSidecar(dir, a)[@"capturedAt"] doubleValue];
        double cb = [rygSidecar(dir, b)[@"capturedAt"] doubleValue];
        return ca < cb ? NSOrderedAscending : (ca > cb ? NSOrderedDescending : NSOrderedSame);
    }];
    return ids;
}

@implementation RYGNSEImport

+ (void)promoteDeleted {
    if (![RYGUtils getBoolPref:@"deleted_messages_log_enabled"]) return;

    dispatch_async(rygQueue(), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = rygStagingRoot();
        if (!root) return;
        NSString *fallbackOwner = [RYGUtils currentUserPK];
        NSUInteger imported = 0;

        for (NSString *dir in rygOwnerDirs(fm, root)) {
            NSString *dirOwner = dir.lastPathComponent;
            NSArray *markers = [[fm contentsOfDirectoryAtPath:dir error:nil] filteredArrayUsingPredicate:
                [NSPredicate predicateWithBlock:^BOOL(NSString *n, __unused id b) { return [n.pathExtension isEqualToString:@"deleted"]; }]];

            for (NSString *marker in markers) {
                NSString *itemId = marker.stringByDeletingPathExtension;
                NSDictionary *rec = rygSidecar(dir, itemId);
                if (!rec) { rygRemoveStaged(fm, dir, itemId, nil); continue; }

                NSString *owner = [rec[@"ownerPk"] length] ? [rec[@"ownerPk"] description] : ([dirOwner isEqualToString:@"unknown"] ? fallbackOwner : dirOwner);
                if (!owner.length) continue;

                RYGDeletedMessage *m = [RYGDeletedMessage new];
                m.messageId = itemId;
                m.threadId = [rec[@"threadId"] description] ?: @"";
                m.senderPk = [rec[@"senderPk"] description] ?: @"";
                m.kind = [[rec[@"kind"] description] isEqualToString:@"video"] ? RYGDeletedMessageKindVideo : RYGDeletedMessageKindPhoto;
                m.isEphemeral = YES;
                m.mediaURL = [rec[@"mediaURL"] description];
                m.mediaMimeType = [rec[@"mediaMime"] description];
                m.width = [rec[@"width"] doubleValue];
                m.height = [rec[@"height"] doubleValue];

                double us = [rec[@"sentAtUs"] doubleValue];
                double cap = [rec[@"capturedAt"] doubleValue];
                m.sentAt = us > 0 ? [NSDate dateWithTimeIntervalSince1970:us / 1e6] : (cap > 0 ? [NSDate dateWithTimeIntervalSince1970:cap] : [NSDate date]);
                m.capturedAt = cap > 0 ? [NSDate dateWithTimeIntervalSince1970:cap] : [NSDate date];
                m.deletedAt = [NSDate date];

                NSString *mediaFile = [rec[@"mediaFile"] description];
                NSString *src = mediaFile.length ? [dir stringByAppendingPathComponent:mediaFile] : nil;
                if (src && [fm fileExistsAtPath:src]) {
                    NSString *rel = [RYGDeletedMessagesStorage reserveRelativeMediaPathForMessageId:itemId extension:mediaFile.pathExtension ownerPK:owner];
                    NSString *abs = [RYGDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:owner];
                    [fm removeItemAtPath:abs error:nil];
                    if ([fm copyItemAtPath:src toPath:abs error:nil]) { m.mediaPath = rel; m.mediaStatus = RYGDeletedMessageMediaStatusSaved; }
                }

                NSString *thumbFile = [rec[@"thumbFile"] description];
                NSString *tsrc = thumbFile.length ? [dir stringByAppendingPathComponent:thumbFile] : nil;
                if (tsrc && [fm fileExistsAtPath:tsrc]) {
                    NSString *trel = [RYGDeletedMessagesStorage reserveRelativeMediaPathForMessageId:[itemId stringByAppendingString:@"_thumb"] extension:@"jpg" ownerPK:owner];
                    NSString *tabs = [RYGDeletedMessagesStorage absolutePathForRelativePath:trel ownerPK:owner];
                    [fm removeItemAtPath:tabs error:nil];
                    if ([fm copyItemAtPath:tsrc toPath:tabs error:nil]) m.thumbnailPath = trel;
                }

                if (!m.mediaPath) m.mediaStatus = m.mediaURL.length ? RYGDeletedMessageMediaStatusPending : RYGDeletedMessageMediaStatusUnavailable;

                if ([RYGDeletedMessagesStorage saveMessage:m forOwnerPK:owner]) {
                    imported++;
                    [RYGHomeShortcutBadges bumpActionID:@"deleted_messages"];
                }
                rygRemoveStaged(fm, dir, itemId, rec);
            }
        }

        if (imported) {
            RYGOSLog("nse-import", @"promoted %lu unsent capture(s) into the log", (unsigned long)imported);
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RYGDeletedMessagesDidChangeNotification object:nil];
            });
        }
    });
}

+ (void)runCleanup {
    if (![[RYGUtils getStringPref:@"nse_cleanup_mode"] isEqualToString:@"limits"]) return;

    dispatch_async(rygQueue(), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = rygStagingRoot();
        if (!root) return;
        double days = [RYGUtils getDoublePref:@"nse_cleanup_age_days"];
        unsigned long long cap = (unsigned long long)([RYGUtils getDoublePref:@"nse_cleanup_size_mb"] * 1024.0 * 1024.0);
        NSUInteger removed = 0;

        // Both caps apply per account.
        for (NSString *dir in rygOwnerDirs(fm, root)) {
            NSMutableArray<NSString *> *ids = [rygUndeleted(fm, dir) mutableCopy];

            if (days > 0) {
                double cutoff = [NSDate date].timeIntervalSince1970 - days * 86400.0;
                NSMutableArray *survivors = [NSMutableArray array];
                for (NSString *itemId in ids) {
                    NSDictionary *rec = rygSidecar(dir, itemId);
                    if ([rec[@"capturedAt"] doubleValue] < cutoff) { rygRemoveStaged(fm, dir, itemId, rec); removed++; }
                    else [survivors addObject:itemId];
                }
                ids = survivors;
            }

            if (cap > 0) {
                unsigned long long total = 0;
                NSMutableArray<NSArray *> *sized = [NSMutableArray array];
                for (NSString *itemId in ids) {
                    NSDictionary *rec = rygSidecar(dir, itemId);
                    NSString *mf = [rec[@"mediaFile"] description];
                    unsigned long long sz = 0;
                    if (mf.length) { NSDictionary *at = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:mf] error:nil]; sz = at ? [at fileSize] : 0; }
                    total += sz;
                    [sized addObject:@[itemId, @(sz), rec ?: @{}]];
                }
                for (NSArray *e in sized) {
                    if (total <= cap) break;
                    rygRemoveStaged(fm, dir, e[0], e[2]);
                    total -= [e[1] unsignedLongLongValue];
                    removed++;
                }
            }
        }

        if (removed) RYGOSLog("nse-cleanup", @"removed %lu staged capture(s)", (unsigned long)removed);
    });
}

+ (void)cleanStagingCache {
    dispatch_async(rygQueue(), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = rygStagingRoot();
        if (!root) return;
        NSUInteger removed = 0;
        for (NSString *dir in rygOwnerDirs(fm, root)) {
            NSArray<NSString *> *ids = rygUndeleted(fm, dir);
            for (NSString *itemId in ids) { rygRemoveStaged(fm, dir, itemId, rygSidecar(dir, itemId)); removed++; }
        }
        if (removed) RYGOSLog("nse-cleanup", @"clean-on-open dropped %lu staged capture(s)", (unsigned long)removed);
    });
}

+ (unsigned long long)stagingCacheSize {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = rygStagingRoot();
    if (!root) return 0;
    unsigned long long total = 0;
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
    while ([en nextObject]) {
        NSDictionary *at = en.fileAttributes;
        if ([at.fileType isEqualToString:NSFileTypeRegular]) total += at.fileSize;
    }
    return total;
}

+ (void)clearAllStaging {
    dispatch_async(rygQueue(), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = rygStagingRoot();
        if (!root) return;
        for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil])
            [fm removeItemAtPath:[root stringByAppendingPathComponent:name] error:nil];
        RYGOSLog("nse-cleanup", @"cleared entire staging cache");
    });
}

@end
