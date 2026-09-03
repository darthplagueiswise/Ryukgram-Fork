// View-once / raven DM capture inside Instagram's Notification Service Extension.
// Reads its config from the shared container and stages captured media per account.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import "../../src/RYGOSLog.h"
#import "../../src/RYGFileLog.h"

#define NSELOG(fmt, ...) do { \
    NSString *_m = [NSString stringWithFormat:(fmt), ##__VA_ARGS__]; \
    RYGOSLogWrite("nse", _m); \
    RYGFileLogWrite(@"nse", _m); \
} while (0)

@interface LSBundleProxy : NSObject
@property (nonatomic, readonly) NSDictionary *entitlements;
+ (instancetype)bundleProxyForCurrentProcess;
@end

static NSString *gBearer = nil;
static NSString *gOwnerPk = nil;
static void (*gOrigDidReceive)(id, SEL, id, void (^)(id)) = NULL;

static NSString *rygGroupId(void) {
    Class cls = objc_getClass("LSBundleProxy");
    if (cls) {
        id proxy = [cls bundleProxyForCurrentProcess];
        NSDictionary *ents = [proxy valueForKey:@"entitlements"];
        NSArray *groups = [ents isKindOfClass:NSDictionary.class] ? ents[@"com.apple.security.application-groups"] : nil;
        if ([groups isKindOfClass:NSArray.class] && groups.count) return groups.firstObject;
    }
    return @"group.com.burbn.instagram";
}

static NSString *rygSharedDir(void) {
    NSURL *g = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:rygGroupId()];
    if (!g) return nil;
    NSURL *d = [g URLByAppendingPathComponent:@"RyukGram" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d.path;
}

static NSString *rygStagingDir(void) {
    NSString *base = rygSharedDir();
    if (!base) return nil;
    NSString *d = [base stringByAppendingPathComponent:@"nse_staging"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

static NSString *rygStagingDirForOwner(NSString *pk) {
    NSString *base = rygStagingDir();
    if (!base) return nil;
    NSString *d = [base stringByAppendingPathComponent:(pk.length ? pk : @"unknown")];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

// Flag a staged capture unsent so the main app promotes it; the owner isn't
// known here, so search the per-account dirs for the item.
static void rygMarkDeleted(NSString *itemId) {
    NSString *base = rygStagingDir();
    if (!base || !itemId.length) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *ownerDir in [fm contentsOfDirectoryAtPath:base error:nil]) {
        NSString *od = [base stringByAppendingPathComponent:ownerDir];
        NSString *sidecar = [[od stringByAppendingPathComponent:itemId] stringByAppendingPathExtension:@"json"];
        if (![fm fileExistsAtPath:sidecar]) continue;
        [[NSData data] writeToFile:[[od stringByAppendingPathComponent:itemId] stringByAppendingPathExtension:@"deleted"] atomically:YES];
        return;
    }
}

static NSDictionary *rygConfig(void) {
    NSString *dir = rygSharedDir();
    NSData *d = dir ? [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"nse_config.json"]] : nil;
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : @{};
}

static id RYGkv(id obj, NSString *key) { @try { return [obj valueForKey:key]; } @catch (__unused id ex) { return nil; } }

static NSString *rygExtractToken(NSString *blob) {
    if (![blob containsString:@"IGT:2:"]) return nil;
    NSRange r = [blob rangeOfString:@"IGT:2:"];
    NSString *tail = [blob substringFromIndex:r.location];
    NSRange end = [tail rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"' \n\t\\<>}]"]];
    return end.location != NSNotFound ? [tail substringToIndex:end.location] : tail;
}

static NSString *rygPkForToken(NSString *tok) {
    NSString *b64 = tok.length > 6 ? [tok substringFromIndex:6] : nil;
    NSData *jd = b64 ? [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
    id j = jd ? [NSJSONSerialization JSONObjectWithData:jd options:0 error:NULL] : nil;
    return [j isKindOfClass:NSDictionary.class] ? [((NSDictionary *)j)[@"ds_user_id"] description] : nil;
}

// Pick the token for the push recipient; else the active-account authheader token.
static void rygHarvestBearer(NSString *recipientPk) {
    NSDictionary *q = @{ (id)kSecClass: (id)kSecClassGenericPassword,
                         (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                         (id)kSecReturnData: @YES,
                         (id)kSecReturnAttributes: @YES };
    CFTypeRef res = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &res);
    if (st != errSecSuccess || !res) { if (res) CFRelease(res); return; }
    NSArray *items = (__bridge_transfer NSArray *)res;

    NSMutableDictionary<NSString *, NSString *> *byPk = [NSMutableDictionary dictionary];
    NSString *authHeaderTok = nil;
    for (NSDictionary *it in items) {
        NSData *d = it[(id)kSecValueData];
        if (!d.length) continue;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s) { id pl = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:NULL]; s = pl ? [pl description] : nil; }
        NSString *scan = s;
        while (scan.length) {
            NSString *tok = rygExtractToken(scan);
            if (!tok) break;
            NSString *pk = rygPkForToken(tok) ?: @"?";
            if (!byPk[pk]) byPk[pk] = tok;
            NSString *svce = it[(id)kSecAttrService] ?: @"";
            if ([svce containsString:@"authheader"] && !authHeaderTok) authHeaderTok = tok;
            NSRange r = [scan rangeOfString:tok];
            scan = r.location != NSNotFound ? [scan substringFromIndex:r.location + r.length] : nil;
        }
    }

    NSString *tok = nil;
    if (recipientPk.length && byPk[recipientPk]) tok = byPk[recipientPk];
    else if (authHeaderTok) tok = authHeaderTok;
    else tok = byPk.allValues.firstObject;

    if (tok) {
        gBearer = [@"Bearer " stringByAppendingString:tok];
        gOwnerPk = rygPkForToken(tok);
    } else {
        NSELOG(@"bearer not found in %lu keychain items", (unsigned long)items.count);
    }
}

static NSString *rygWearables(NSString *sel, id userInfo) {
    Class c = objc_getClass("_TtC16IGWearablesUtils16IGWearablesUtils");
    if (!c) return nil;
    SEL s = NSSelectorFromString(sel);
    if (![c respondsToSelector:s]) return nil;
    @try { id r = ((id(*)(id, SEL, id))objc_msgSend)(c, s, userInfo); return [r isKindOfClass:NSString.class] ? r : (r ? [r description] : nil); }
    @catch (__unused id ex) { return nil; }
}

static NSMutableURLRequest *rygAuthedRequest(NSString *urlStr) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.timeoutInterval = 12;
    [req setValue:@"Instagram 443.0.0 (iPhone11,6; iOS 16_1_1; en_US; en; scale=3.00; 1242x2688; 0)" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"124024574287414" forHTTPHeaderField:@"X-IG-App-ID"];
    [req setValue:@"WIFI" forHTTPHeaderField:@"X-IG-Connection-Type"];
    [req setValue:@"en-US" forHTTPHeaderField:@"Accept-Language"];
    if (gBearer) [req setValue:gBearer forHTTPHeaderField:@"Authorization"];
    return req;
}

static NSDictionary *rygBestImageCandidate(NSDictionary *media) {
    NSArray *cands = [media[@"image_versions2"] isKindOfClass:NSDictionary.class] ? media[@"image_versions2"][@"candidates"] : nil;
    NSDictionary *best = nil; long bestW = -1;
    for (NSDictionary *c in (cands ?: @[])) { long w = [c[@"width"] longValue]; if (w > bestW) { bestW = w; best = c; } }
    return best;
}

static void rygWriteSidecar(NSString *dir, NSString *itemId, NSDictionary *rec) {
    NSData *j = [NSJSONSerialization dataWithJSONObject:rec options:NSJSONWritingPrettyPrinted error:nil];
    [j writeToFile:[dir stringByAppendingPathComponent:[itemId stringByAppendingString:@".json"]] atomically:YES];
}

// Raven media lives under visual_media.media; normal media under item.media.
static NSDictionary *rygMediaDict(NSDictionary *item) {
    NSDictionary *vm = [item[@"visual_media"] isKindOfClass:NSDictionary.class] ? item[@"visual_media"] : nil;
    NSDictionary *media = [vm[@"media"] isKindOfClass:NSDictionary.class] ? vm[@"media"] : nil;
    if (!media) media = [item[@"media"] isKindOfClass:NSDictionary.class] ? item[@"media"] : nil;
    return media;
}

static void rygFetchToFile(NSString *urlStr, NSString *dst, void (^done)(BOOL ok, long long bytes)) {
    NSURLSession *sess = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSURLSessionDownloadTask *task = [sess downloadTaskWithRequest:rygAuthedRequest(urlStr) completionHandler:^(NSURL *loc, NSURLResponse *resp, __unused NSError *err) {
        long code = [resp isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)resp statusCode] : -1;
        if (loc && code == 200) {
            [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
            BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:loc.path toPath:dst error:nil];
            done(ok, resp.expectedContentLength);
        } else { done(NO, 0); }
    }];
    [task resume];
}

static void rygDownloadItem(NSDictionary *item, NSString *threadId, NSString *pending, dispatch_group_t group) {
    NSString *itemId = [item[@"item_id"] description] ?: @"";
    NSDictionary *media = rygMediaDict(item);
    if (!itemId.length || !media) return;

    NSString *fileBase = [pending stringByAppendingPathComponent:itemId];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[fileBase stringByAppendingString:@".json"]]) return;

    BOOL isVideo = [media[@"media_type"] integerValue] == 2 || [media[@"video_versions"] isKindOfClass:NSArray.class];
    NSString *url = nil, *ext = nil, *mime = nil; long w = 0, h = 0;
    if (isVideo) {
        NSArray *vv = media[@"video_versions"];
        NSDictionary *v = [vv isKindOfClass:NSArray.class] && vv.count ? vv.firstObject : nil;
        url = v[@"url"]; ext = @"mp4"; mime = @"video/mp4"; w = [v[@"width"] longValue]; h = [v[@"height"] longValue];
    } else {
        NSDictionary *c = rygBestImageCandidate(media);
        url = c[@"url"]; ext = @"jpg"; mime = @"image/jpeg"; w = [c[@"width"] longValue]; h = [c[@"height"] longValue];
    }
    if (!url.length) return;
    NSString *thumbURL = isVideo ? rygBestImageCandidate(media)[@"url"] : nil;

    NSMutableDictionary *rec = [@{
        @"schema": @1, @"itemId": itemId, @"threadId": threadId ?: @"",
        @"senderPk": [item[@"user_id"] description] ?: @"", @"ownerPk": gOwnerPk ?: @"",
        @"kind": isVideo ? @"video" : @"photo", @"isEphemeral": @YES,
        @"mediaURL": url, @"mediaMime": mime, @"width": @(w), @"height": @(h),
        @"sentAtUs": item[@"timestamp"] ?: @0, @"capturedAt": @([[NSDate date] timeIntervalSince1970]),
    } mutableCopy];

    dispatch_group_enter(group);
    NSString *mediaDst = [fileBase stringByAppendingPathExtension:ext];
    rygFetchToFile(url, mediaDst, ^(BOOL ok, long long bytes) {
        if (ok) { rec[@"mediaFile"] = [mediaDst lastPathComponent]; rec[@"bytes"] = @(bytes); }
        else rec[@"error"] = @"download_failed";
        void (^finish)(void) = ^{
            rygWriteSidecar(pending, itemId, rec);
            if (!ok) NSELOG(@"download failed item=%@", itemId);
            dispatch_group_leave(group);
        };
        if (ok && thumbURL.length) {
            NSString *thumbDst = [[fileBase stringByAppendingString:@"_thumb"] stringByAppendingPathExtension:@"jpg"];
            rygFetchToFile(thumbURL, thumbDst, ^(BOOL tok, __unused long long tb) {
                if (tok) rec[@"thumbFile"] = [thumbDst lastPathComponent];
                finish();
            });
        } else { finish(); }
    });
}

static void rygCaptureThread(NSString *threadId, NSString *pushedItemId, BOOL isRaven, void (^done)(void)) {
    NSString *pending = rygStagingDirForOwner(gOwnerPk);
    if (!threadId.length || !pending || !gBearer) { done(); return; }

    NSString *urlStr = [NSString stringWithFormat:@"https://i.instagram.com/api/v1/direct_v2/threads/%@/?limit=20&visual_message_return_type=unseen", threadId];
    NSURLSession *sess = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSURLSessionDataTask *task = [sess dataTaskWithRequest:rygAuthedRequest(urlStr) completionHandler:^(NSData *data, __unused NSURLResponse *resp, __unused NSError *err) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSArray *items = [json isKindOfClass:NSDictionary.class] ? [json[@"thread"] isKindOfClass:NSDictionary.class] ? json[@"thread"][@"items"] : nil : nil;

        dispatch_group_t g = dispatch_group_create();
        for (NSDictionary *it in (items ?: @[])) {
            if (![it isKindOfClass:NSDictionary.class]) continue;
            NSString *iid = [it[@"item_id"] description];
            BOOL isRavenItem = [[it[@"item_type"] description] isEqualToString:@"raven_media"] || [it[@"visual_media"] isKindOfClass:NSDictionary.class];
            // pushed item (any type) + other unseen ravens on a raven push
            BOOL match = (pushedItemId.length && [iid isEqualToString:pushedItemId]) || (isRaven && isRavenItem);
            if (!match) continue;
            rygDownloadItem(it, threadId, pending, g);
        }
        dispatch_group_notify(g, dispatch_get_main_queue(), ^{ done(); });
    }];
    [task resume];
}

static void rygDidReceive(id self, SEL _cmd, id request, void (^contentHandler)(id)) {
    id content = RYGkv(request, @"content");
    id userInfo = RYGkv(content, @"userInfo");
    NSString *cat = RYGkv(content, @"categoryIdentifier") ?: @"";

    // Read config fresh per push: the NSE process is reused, so a constructor
    // snapshot would miss later toggles.
    NSDictionary *cfg = rygConfig();
    BOOL enabled = [cfg[@"enabled"] boolValue] && [cfg[@"log_enabled"] boolValue];
    BOOL captureNormal = [cfg[@"capture_normal_media"] boolValue];
    if (!enabled) { gOrigDidReceive(self, _cmd, request, contentHandler); return; }

    if ([cat isEqualToString:@"direct_v2_delete_item"]) {
        rygMarkDeleted([RYGkv(userInfo, @"n") description]);
        gOrigDidReceive(self, _cmd, request, contentHandler);
        return;
    }

    BOOL isRaven = [cat containsString:@"raven"];
    BOOL isMedia = [cat containsString:@"direct_v2_media"];
    if (!isRaven && !(isMedia && captureNormal)) { gOrigDidReceive(self, _cmd, request, contentHandler); return; }

    __block BOOL forwarded = NO;
    void (^forwardOnce)(void) = ^{
        @synchronized (request) { if (forwarded) return; forwarded = YES; }
        gOrigDidReceive(self, _cmd, request, contentHandler);
    };

    rygHarvestBearer([RYGkv(userInfo, @"pi") description]);
    NSString *threadId = rygWearables(@"uriThreadIdWithUserInfo:", userInfo);
    if (!threadId.length) threadId = [RYGkv(userInfo, @"t_id") description] ?: [RYGkv(userInfo, @"thread-id") description];
    NSString *pushedItemId = [RYGkv(userInfo, @"n") description];

    rygCaptureThread(threadId, pushedItemId, isRaven, ^{ forwardOnce(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(22 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        if (!forwarded) forwardOnce();
    });
}

// Hook is installed unconditionally; it forwards immediately when the config is off.
__attribute__((constructor))
static void RYGViewOnceInit(void) {
    if (NSBundle.mainBundle.infoDictionary[@"NSExtension"] == nil) return;
    Class svc = objc_getClass("FBNotificationService");
    if (!svc) return;
    Method m = class_getInstanceMethod(svc, @selector(didReceiveNotificationRequest:withContentHandler:));
    if (!m) return;
    gOrigDidReceive = (void (*)(id, SEL, id, void (^)(id)))method_getImplementation(m);
    method_setImplementation(m, (IMP)rygDidReceive);
}
