#import "SCIDeletedMessagesStorage.h"

NSNotificationName const SCIDeletedMessagesDidChangeNotification = @"SCIDeletedMessagesDidChangeNotification";

static NSString *const kSCIDMStorageDir = @"RyukGram/DeletedMessages";
static NSString *const kSCIDMMediaDir   = @"media";

@implementation SCIDeletedMessagesStorage

#pragma mark - Plumbing

static dispatch_queue_t sciDMQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.ryukgram.deletedmessages.io", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *sciSafePK(NSString *pk) {
    return pk.length ? pk : @"anon";
}

static NSString *sciStorageDir(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dir = [roots.firstObject stringByAppendingPathComponent:kSCIDMStorageDir];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciMediaDirForOwner(NSString *pk) {
    NSString *dir = [[sciStorageDir() stringByAppendingPathComponent:kSCIDMMediaDir]
                     stringByAppendingPathComponent:sciSafePK(pk)];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *sciJSONPathForOwner(NSString *pk) {
    return [sciStorageDir() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.json", sciSafePK(pk)]];
}

static NSArray *sciReadArray(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:[NSArray class]] ? obj : @[];
}

static BOOL sciWriteArray(NSString *path, NSArray *arr) {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:(arr ?: @[]) options:0 error:&err];
    if (!data) return NO;
    return [data writeToFile:path atomically:YES];
}

static void sciPostChanged(NSString *ownerPK) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIDeletedMessagesDidChangeNotification
                                                            object:nil
                                                          userInfo:ownerPK.length ? @{@"owner_pk": ownerPK} : @{}];
    });
}

// Newest-first order. capturedAt is required; deletedAt is the truer key when present.
static NSDate *sciSortKey(SCIDeletedMessage *m) {
    return m.deletedAt ?: (m.capturedAt ?: m.sentAt);
}

static NSArray<SCIDeletedMessage *> *sciDecode(NSArray *raw) {
    NSMutableArray<SCIDeletedMessage *> *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id d in raw) {
        SCIDeletedMessage *m = [SCIDeletedMessage messageFromJSONDict:d];
        if (m) [out addObject:m];
    }
    return out;
}

static NSArray<NSDictionary *> *sciEncode(NSArray<SCIDeletedMessage *> *msgs) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
    for (SCIDeletedMessage *m in msgs) [out addObject:[m toJSONDict]];
    return out;
}

#pragma mark - Read

+ (NSArray<SCIDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK {
    __block NSArray<SCIDeletedMessage *> *result = nil;
    dispatch_sync(sciDMQueue(), ^{
        result = sciDecode(sciReadArray(sciJSONPathForOwner(ownerPK)));
    });
    return result ?: @[];
}

+ (NSArray<SCIDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (SCIDeletedMessage *m in [self allMessagesForOwnerPK:ownerPK]) {
        if ([m.senderPk isEqualToString:senderPK]) [out addObject:m];
    }
    return out;
}

+ (NSArray<SCIDeletedMessageGroup *> *)groupedBySenderForOwnerPK:(NSString *)ownerPK {
    NSArray<SCIDeletedMessage *> *all = [self allMessagesForOwnerPK:ownerPK];
    NSMutableDictionary<NSString *, NSMutableArray<SCIDeletedMessage *> *> *byPk = [NSMutableDictionary dictionary];
    for (SCIDeletedMessage *m in all) {
        if (!m.senderPk.length) continue;
        NSMutableArray *list = byPk[m.senderPk];
        if (!list) { list = [NSMutableArray array]; byPk[m.senderPk] = list; }
        [list addObject:m];
    }

    NSMutableArray<SCIDeletedMessageGroup *> *groups = [NSMutableArray array];
    for (NSString *pk in byPk) {
        NSArray *msgs = byPk[pk];
        SCIDeletedMessage *latest = msgs.firstObject;   // already newest-first
        SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
        g.senderPk            = pk;
        g.senderUsername      = latest.senderUsername;
        g.senderFullName      = latest.senderFullName;
        g.senderProfilePicURL = latest.senderProfilePicURL;
        g.messages            = msgs;
        [groups addObject:g];
    }
    [groups sortUsingComparator:^NSComparisonResult(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
        NSDate *da = a.lastDeletedAt ?: [NSDate distantPast];
        NSDate *db = b.lastDeletedAt ?: [NSDate distantPast];
        return [db compare:da];
    }];
    return groups;
}

#pragma mark - Write

+ (BOOL)saveMessage:(SCIDeletedMessage *)message forOwnerPK:(NSString *)ownerPK {
    if (!message.messageId.length) return NO;
    return [self saveMessages:@[message] forOwnerPK:ownerPK];
}

+ (BOOL)saveMessages:(NSArray<SCIDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK {
    if (!messages.count) return NO;
    __block BOOL ok = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        NSMutableSet<NSString *> *incomingIds = [NSMutableSet setWithCapacity:messages.count];
        for (SCIDeletedMessage *m in messages) {
            if (m.messageId.length) [incomingIds addObject:m.messageId];
        }
        // Drop any existing record for the incoming ids (replace semantics).
        NSMutableArray<SCIDeletedMessage *> *kept = [NSMutableArray arrayWithCapacity:cur.count];
        for (SCIDeletedMessage *m in cur) {
            if (![incomingIds containsObject:m.messageId]) [kept addObject:m];
        }
        [kept addObjectsFromArray:messages];
        [kept sortUsingComparator:^NSComparisonResult(SCIDeletedMessage *a, SCIDeletedMessage *b) {
            NSDate *da = sciSortKey(a) ?: [NSDate distantPast];
            NSDate *db = sciSortKey(b) ?: [NSDate distantPast];
            return [db compare:da];
        }];
        ok = sciWriteArray(path, sciEncode(kept));
    });
    if (ok) sciPostChanged(ownerPK);
    return ok;
}

+ (BOOL)applySenderInfo:(NSDictionary *)info
            forSenderPK:(NSString *)senderPK
                ownerPK:(NSString *)ownerPK {
    if (!senderPK.length || ![info isKindOfClass:[NSDictionary class]]) return NO;
    NSString *u  = [info[@"username"]        isKindOfClass:[NSString class]] ? info[@"username"]        : nil;
    NSString *fn = [info[@"full_name"]       isKindOfClass:[NSString class]] ? info[@"full_name"]       : nil;
    NSString *p  = [info[@"profile_pic_url"] isKindOfClass:[NSString class]] ? info[@"profile_pic_url"] : nil;
    if (!u.length && !fn.length && !p.length) return NO;

    __block BOOL touched = NO;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        for (SCIDeletedMessage *m in cur) {
            if (![m.senderPk isEqualToString:senderPK]) continue;
            if (u.length  && !m.senderUsername.length)        { m.senderUsername = u;        touched = YES; }
            if (fn.length && !m.senderFullName.length)        { m.senderFullName = fn;       touched = YES; }
            if (p.length  && !m.senderProfilePicURL.length)   { m.senderProfilePicURL = p;   touched = YES; }
        }
        if (touched) sciWriteArray(path, sciEncode(cur));
    });
    if (touched) sciPostChanged(ownerPK);
    return touched;
}

+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK {
    if (!messageId.length) return;
    dispatch_sync(sciDMQueue(), ^{
        NSString *path = sciJSONPathForOwner(ownerPK);
        NSMutableArray<SCIDeletedMessage *> *cur = [sciDecode(sciReadArray(path)) mutableCopy];
        NSMutableArray<SCIDeletedMessage *> *kept = [NSMutableArray arrayWithCapacity:cur.count];
        for (SCIDeletedMessage *m in cur) {
            if ([m.messageId isEqualToString:messageId]) {
                if (m.mediaPath.length) {
                    [[NSFileManager defaultManager] removeItemAtPath:
                        [sciMediaDirForOwner(ownerPK) stringByAppendingPathComponent:m.mediaPath.lastPathComponent]
                        error:nil];
                }
                if (m.thumbnailPath.length) {
                    [[NSFileManager defaultManager] removeItemAtPath:
                        [sciMediaDirForOwner(ownerPK) stringByAppendingPathComponent:m.thumbnailPath.lastPathComponent]
                        error:nil];
                }
                continue;
            }
            [kept addObject:m];
        }
        sciWriteArray(path, sciEncode(kept));
    });
    sciPostChanged(ownerPK);
}

+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK {
    if (!senderPK.length) return;
    NSArray *toDrop = [self messagesForSenderPK:senderPK ownerPK:ownerPK];
    for (SCIDeletedMessage *m in toDrop) {
        [self deleteMessageId:m.messageId forOwnerPK:ownerPK];
    }
}

+ (void)resetForOwnerPK:(NSString *)ownerPK {
    dispatch_sync(sciDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:sciJSONPathForOwner(ownerPK) error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:sciMediaDirForOwner(ownerPK) error:nil];
    });
    sciPostChanged(ownerPK);
}

+ (void)resetAll {
    dispatch_sync(sciDMQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:sciStorageDir() error:nil];
    });
    sciPostChanged(nil);
}

#pragma mark - Media

+ (NSString *)absolutePathForRelativePath:(NSString *)relativePath ownerPK:(NSString *)ownerPK {
    if (!relativePath.length) return nil;
    return [sciMediaDirForOwner(ownerPK) stringByAppendingPathComponent:relativePath.lastPathComponent];
}

+ (NSString *)reserveRelativeMediaPathForMessageId:(NSString *)messageId
                                         extension:(NSString *)ext
                                           ownerPK:(NSString *)ownerPK {
    NSString *safeId = [messageId stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *cleanExt = ext.length ? ([ext hasPrefix:@"."] ? [ext substringFromIndex:1] : ext) : @"bin";
    NSString *fname = [NSString stringWithFormat:@"%@.%@", safeId, cleanExt];
    // Touch the dir so callers can write straight away.
    (void)sciMediaDirForOwner(ownerPK);
    return fname;
}

+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK {
    NSString *dir = sciMediaDirForOwner(ownerPK);
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    unsigned long long total = 0;
    for (NSString *rel in en) {
        NSDictionary *attrs = [en fileAttributes];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
        (void)rel;
    }
    return total;
}

@end
