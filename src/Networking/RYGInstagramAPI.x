// Reusable IG private API helper. See RYGInstagramAPI.h.

#import "RYGInstagramAPI.h"
#import "../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/sysctl.h>

#define RYG_API_BASE @"https://i.instagram.com/api/v1/"
#define RYG_APP_ID   @"124024574287414" // public IG iOS app id constant

@interface RYGInstagramAPI (Private)
+ (void)accumulateViewersForMediaID:(NSString *)mediaID cursor:(NSString *)cursor into:(NSMutableArray *)acc page:(NSInteger)page progress:(void (^)(NSInteger))progress completion:(void (^)(NSArray<NSDictionary *> *, NSInteger, NSError *))completion;
@end

// User-Agent in IG's exact format, generated from the device + IG bundle.
static NSString *rygUserAgent(void) {
    static NSString *ua = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // IG 404s API calls when the UA version isn't a real number (a placeholder plist gives "Default").
        NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
        if (![version isKindOfClass:NSString.class] || !version.length ||
            ![NSCharacterSet.decimalDigitCharacterSet characterIsMember:[version characterAtIndex:0]])
            version = @"423.1.0";
        char machine[64] = {0};
        size_t size = sizeof(machine);
        sysctlbyname("hw.machine", machine, &size, NULL, 0);
        NSString *device = machine[0] ? [NSString stringWithUTF8String:machine] : @"iPhone15,2";
        NSString *iosVersion = [[UIDevice currentDevice].systemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        NSString *locale = [NSLocale currentLocale].localeIdentifier ?: @"en_US";
        NSString *lang = [[NSLocale preferredLanguages] firstObject] ?: @"en";
        UIScreen *screen = [UIScreen mainScreen];
        ua = [NSString stringWithFormat:@"Instagram %@ (%@; iOS %@; %@; %@; scale=%.2f; %.0fx%.0f; 0)",
              version, device, iosVersion, locale, lang,
              screen.scale, screen.nativeBounds.size.width, screen.nativeBounds.size.height];
    });
    return ua;
}

// ============ IG runtime accessors ============

static id rygCurrentUserSession(void) { return [RYGUtils activeUserSession]; }
static NSString *rygCurrentUserPK(void) { return [RYGUtils currentUserPK]; }

// Bearer token for the active account, read fresh from
// -[IGUserSession authHeaderManager] -> -[IGUserAuthHeaderManager authHeader].
static NSString *rygAuthHeader(void) {
    @try {
        id session = rygCurrentUserSession();
        if (!session || ![session respondsToSelector:@selector(authHeaderManager)]) return nil;
        id manager = ((id(*)(id, SEL))objc_msgSend)(session, @selector(authHeaderManager));
        if (!manager || ![manager respondsToSelector:@selector(authHeader)]) return nil;
        id header = ((id(*)(id, SEL))objc_msgSend)(manager, @selector(authHeader));
        if ([header isKindOfClass:[NSString class]] && [(NSString *)header length]) return header;
    } @catch (__unused id e) {}
    return nil;
}

// ============ Request building ============

static NSString *rygFormEncode(NSDictionary *params) {
    if (!params.count) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    for (NSString *key in params) {
        NSString *val = [NSString stringWithFormat:@"%@", params[key]];
        NSString *ek = [key stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        NSString *ev = [val stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", ek, ev]];
    }
    return [parts componentsJoinedByString:@"&"];
}

static NSMutableURLRequest *rygBuildRequest(NSString *method, NSURL *url, NSDictionary *body) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method ?: @"GET";

    [req setValue:rygUserAgent() forHTTPHeaderField:@"User-Agent"];
    [req setValue:RYG_APP_ID      forHTTPHeaderField:@"X-IG-App-ID"];
    [req setValue:@"WIFI"         forHTTPHeaderField:@"X-IG-Connection-Type"];
    [req setValue:@"en-US"        forHTTPHeaderField:@"Accept-Language"];
    NSString *auth = rygAuthHeader();
    if (auth) [req setValue:auth forHTTPHeaderField:@"Authorization"];

    for (NSHTTPCookie *c in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url]) {
        if ([c.name isEqualToString:@"csrftoken"]) {
            [req setValue:c.value forHTTPHeaderField:@"X-CSRFToken"];
            break;
        }
    }

    if (body) {
        req.HTTPBody = [rygFormEncode(body) dataUsingEncoding:NSUTF8StringEncoding];
        [req setValue:@"application/x-www-form-urlencoded; charset=UTF-8"
            forHTTPHeaderField:@"Content-Type"];
    }
    return req;
}

static void rygPerformRequest(NSMutableURLRequest *req, RYGAPICompletion completion) {
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            NSDictionary *resp = nil;
            if (data.length) {
                @try {
                    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([parsed isKindOfClass:[NSDictionary class]]) resp = parsed;
                } @catch (__unused id e) {}
            }
            NSError *outErr = error;
            if (!outErr) {
                id status = resp[@"status"];
                BOOL apiFail = [status isKindOfClass:[NSString class]] && [status isEqualToString:@"fail"];
                BOOL loginReq = resp[@"login_required"] || resp[@"require_login"] ||
                    ([resp[@"message"] isKindOfClass:[NSString class]] && [resp[@"message"] rangeOfString:@"login_required"].location != NSNotFound);
                // A missing/failed body must not read as an empty success — callers gate on `error`.
                if (code >= 400 || apiFail || loginReq || !resp) {
                    NSString *msg = [resp[@"message"] isKindOfClass:[NSString class]] ? resp[@"message"] : @"request failed";
                    outErr = [NSError errorWithDomain:@"RYGInstagramAPI" code:(code ?: -1)
                                             userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(resp, outErr); });
            }
        }];
    [task resume];
}

@implementation RYGInstagramAPI

// ============ Generic ============

+ (void)sendRequestWithMethod:(NSString *)method
                         path:(NSString *)path
                         body:(NSDictionary *)body
                   completion:(RYGAPICompletion)completion {
    NSString *clean = [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path;
    NSURL *url = [NSURL URLWithString:[RYG_API_BASE stringByAppendingString:clean]];
    rygPerformRequest(rygBuildRequest(method, url, body), completion);
}

+ (void)downloadAuthorizedURL:(NSURL *)url
                   completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    if (!url) { if (completion) completion(nil, nil, nil); return; }
    NSMutableURLRequest *req = rygBuildRequest(@"GET", url, nil);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (completion) completion(data, response, error);
        }];
    [task resume];
}

// ============ Friendships ============

+ (void)followUserPK:(NSString *)pk completion:(RYGAPICompletion)completion {
    if (!pk.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"POST"
                           path:[NSString stringWithFormat:@"friendships/create/%@/", pk]
                           body:@{@"user_id": pk, @"radio_type": @"wifi-none"}
                     completion:completion];
}

+ (void)unfollowUserPK:(NSString *)pk completion:(RYGAPICompletion)completion {
    if (!pk.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"POST"
                           path:[NSString stringWithFormat:@"friendships/destroy/%@/", pk]
                           body:@{@"user_id": pk, @"radio_type": @"wifi-none"}
                     completion:completion];
}

+ (void)removeFollowerPK:(NSString *)pk completion:(RYGAPICompletion)completion {
    if (!pk.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"POST"
                           path:[NSString stringWithFormat:@"friendships/remove_follower/%@/", pk]
                           body:@{@"user_id": pk}
                     completion:completion];
}

+ (void)likeMediaID:(NSString *)mediaID completion:(RYGAPICompletion)completion {
    if (!mediaID.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"POST"
                           path:[NSString stringWithFormat:@"media/%@/like/", mediaID]
                           body:@{@"media_id": mediaID, @"container_module": @"feed_timeline", @"radio_type": @"wifi-none"}
                     completion:completion];
}

+ (void)unlikeMediaID:(NSString *)mediaID completion:(RYGAPICompletion)completion {
    if (!mediaID.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"POST"
                           path:[NSString stringWithFormat:@"media/%@/unlike/", mediaID]
                           body:@{@"media_id": mediaID, @"container_module": @"feed_timeline", @"radio_type": @"wifi-none"}
                     completion:completion];
}

+ (void)fetchFriendshipStatusesForPKs:(NSArray<NSString *> *)pks
                           completion:(RYGAPIStatusesCompletion)completion {
    if (!pks.count) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"POST"
                           path:@"friendships/show_many/"
                           body:@{@"user_ids": [pks componentsJoinedByString:@","]}
                     completion:^(NSDictionary *response, NSError *error) {
        NSDictionary *statuses = nil;
        id s = response[@"friendship_statuses"];
        if ([s isKindOfClass:[NSDictionary class]]) statuses = s;
        if (completion) completion(statuses, error);
    }];
}

+ (void)fetchFriendshipForPK:(NSString *)pk
                  completion:(RYGAPIStatusesCompletion)completion {
    if (!pk.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"GET"
                           path:[NSString stringWithFormat:@"friendships/show/%@/", pk]
                           body:nil
                     completion:^(NSDictionary *response, NSError *error) {
        // show/ returns the status fields at the top level (unlike show_many's nesting).
        // Require a real friendship dict (has `following`) — an error body must not classify.
        NSDictionary *status = (!error && [response isKindOfClass:[NSDictionary class]] && response[@"following"] != nil) ? response : nil;
        if (completion) completion(status, error);
    }];
}

+ (void)searchUsersWithQuery:(NSString *)query
                  completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!q.length) { if (completion) completion(@[], nil); return; }
    NSString *enc = [q stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: q;
    NSString *path = [NSString stringWithFormat:@"users/search/?q=%@&count=20", enc];
    [self sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (error || ![response isKindOfClass:[NSDictionary class]]) { if (completion) completion(@[], error); return; }
        NSMutableArray *out = [NSMutableArray array];
        id users = response[@"users"];
        if ([users isKindOfClass:[NSArray class]]) for (id u in users) {
            if (![u isKindOfClass:[NSDictionary class]]) continue;
            id pk = u[@"pk"] ?: u[@"pk_id"] ?: u[@"id"];
            NSString *pkStr = [pk isKindOfClass:[NSString class]] ? pk : [pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : nil;
            if (!pkStr.length) continue;
            [out addObject:@{
                @"pk": pkStr,
                @"username": u[@"username"] ?: @"",
                @"full_name": u[@"full_name"] ?: @"",
                @"profile_pic_url": u[@"profile_pic_url"] ?: @"",
            }];
        }
        if (completion) completion(out, nil);
    }];
}

+ (void)fetchUserInfoForPK:(NSString *)pk completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!pk.length) { if (completion) completion(nil, nil); return; }
    NSString *path = [NSString stringWithFormat:@"users/%@/info/", pk];
    [self sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        id user = [response isKindOfClass:[NSDictionary class]] ? response[@"user"] : nil;
        if (error || ![user isKindOfClass:[NSDictionary class]]) { if (completion) completion(nil, error); return; }
        if (completion) completion(@{
            @"pk": pk,
            @"username": user[@"username"] ?: @"",
            @"full_name": user[@"full_name"] ?: @"",
            @"profile_pic_url": user[@"profile_pic_url"] ?: @"",
        }, nil);
    }];
}

+ (void)fetchRankedRecipientsWithCompletion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSString *me = [RYGUtils currentUserPK];
    [self sendRequestWithMethod:@"GET" path:@"direct_v2/inbox/?limit=20&thread_message_limit=1" body:nil completion:^(NSDictionary *response, NSError *error) {
        id inbox = [response isKindOfClass:[NSDictionary class]] ? response[@"inbox"] : nil;
        id threads = [inbox isKindOfClass:[NSDictionary class]] ? inbox[@"threads"] : nil;
        if (error || ![threads isKindOfClass:[NSArray class]]) { if (completion) completion(@[], error); return; }
        NSMutableArray *out = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        void (^add)(id) = ^(id u) {
            if (![u isKindOfClass:[NSDictionary class]]) return;
            id pk = u[@"pk"] ?: u[@"pk_id"] ?: u[@"id"];
            NSString *pkStr = [pk isKindOfClass:[NSString class]] ? pk : [pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : nil;
            if (!pkStr.length || (me.length && [pkStr isEqualToString:me]) || [seen containsObject:pkStr]) return;
            [seen addObject:pkStr];
            [out addObject:@{
                @"pk": pkStr,
                @"username": u[@"username"] ?: @"",
                @"full_name": u[@"full_name"] ?: @"",
                @"profile_pic_url": u[@"profile_pic_url"] ?: @"",
            }];
        };
        for (id thread in threads) {
            id users = [thread isKindOfClass:[NSDictionary class]] ? thread[@"users"] : nil;
            if ([users isKindOfClass:[NSArray class]]) for (id u in users) add(u);
        }
        if (completion) completion(out, nil);
    }];
}

+ (void)fetchPendingFollowRequestsWithCompletion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    [self fetchPendingPage:nil accumulated:[NSMutableArray array] page:0 completion:completion];
}

+ (void)fetchPendingPage:(NSString *)maxId
             accumulated:(NSMutableArray *)acc
                    page:(NSInteger)page
              completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSString *path = maxId.length ? [NSString stringWithFormat:@"friendships/pending/?max_id=%@", maxId] : @"friendships/pending/";
    [self sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (error) { if (completion) completion(acc.count ? acc : nil, error); return; }
        id users = response[@"users"];
        // No `users` array on the first page = a malformed/gated body, not an empty list.
        if (page == 0 && ![users isKindOfClass:[NSArray class]]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"RYGInstagramAPI" code:-2
                                              userInfo:@{NSLocalizedDescriptionKey: @"pending: no users field"}]);
            return;
        }
        if ([users isKindOfClass:[NSArray class]]) for (id u in users) if ([u isKindOfClass:[NSDictionary class]]) [acc addObject:u];
        id next = response[@"next_max_id"];
        NSString *nextId = [next isKindOfClass:[NSString class]] ? next : ([next respondsToSelector:@selector(stringValue)] ? [next stringValue] : nil);
        // Cap pages — incoming request lists are small; this just bounds a runaway.
        if (nextId.length && page < 5) [self fetchPendingPage:nextId accumulated:acc page:page + 1 completion:completion];
        else if (completion) completion(acc, nil);
    }];
}

// ============ Media ============

+ (void)fetchMediaInfoForMediaId:(NSString *)mediaId completion:(RYGAPICompletion)completion {
    if (!mediaId.length) { if (completion) completion(nil, nil); return; }
    [self sendRequestWithMethod:@"GET"
                           path:[NSString stringWithFormat:@"media/%@/info/", mediaId]
                           body:nil
                     completion:completion];
}

+ (void)fetchMediaInfosForMediaIds:(NSArray<NSString *> *)mediaIds
                         completion:(RYGAPICompletion)completion {
    if (!mediaIds.count) { if (completion) completion(nil, nil); return; }
    NSString *ids = [mediaIds componentsJoinedByString:@","];
    NSString *encoded = [ids stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    [self sendRequestWithMethod:@"GET"
                           path:[NSString stringWithFormat:@"media/infos/?media_ids=%@", encoded]
                           body:nil
                     completion:completion];
}

+ (void)fetchStoryViewersForMediaId:(NSString *)mediaId
                              maxId:(NSString *)maxId
                              count:(NSInteger)count
                         completion:(RYGAPICompletion)completion {
    if (!mediaId.length) { if (completion) completion(nil, nil); return; }
    NSMutableString *path = [NSMutableString stringWithFormat:@"media/%@/list_reel_media_viewer/?", mediaId];
    if (count > 0) [path appendFormat:@"count=%ld&", (long)count];
    if (maxId.length) {
        NSString *enc = [maxId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: maxId;
        [path appendFormat:@"max_id=%@", enc];
    }
    [self sendRequestWithMethod:@"GET" path:path body:nil completion:completion];
}

+ (void)fetchStoryViewersPageForMediaID:(NSString *)mediaID
                                 cursor:(NSString *)cursor
                             completion:(void (^)(NSArray<NSDictionary *> *, NSString *, NSInteger, NSError *))completion {
    if (!mediaID.length) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], nil, 0, [NSError errorWithDomain:@"RYGStoryViewers" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Missing story id"}]); });
        return;
    }
    NSMutableString *path = [NSMutableString stringWithFormat:@"media/%@/list_reel_media_viewer/?story_has_interactive_stickers=false&include_reactions=true&supports_reel_reactions=true", mediaID];
    if (cursor.length) {
        NSString *enc = [cursor stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: cursor;
        [path appendFormat:@"&max_id=%@", enc];
    }
    [self sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (![response isKindOfClass:[NSDictionary class]]) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], nil, 0, error ?: [NSError errorWithDomain:@"RYGStoryViewers" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not load viewers"}]); });
            return;
        }
        NSInteger total = 0;
        id totalRaw = response[@"total_viewer_count"] ?: response[@"user_count"];
        if ([totalRaw respondsToSelector:@selector(integerValue)]) total = [totalRaw integerValue];

        NSMutableArray *out = [NSMutableArray array];
        id entries = response[@"viewers"] ?: response[@"users"];
        if ([entries isKindOfClass:[NSArray class]]) for (id entry in entries) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            BOOL liked = [entry[@"has_liked"] boolValue];
            NSDictionary *u = [entry[@"user"] isKindOfClass:[NSDictionary class]] ? entry[@"user"] : entry;
            id pk = u[@"pk"] ?: u[@"pk_id"] ?: u[@"id"];
            NSString *pkStr = [pk isKindOfClass:[NSString class]] ? pk : ([pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : nil);
            if (!pkStr.length) continue;
            id rel = u[@"friendship_status"];
            BOOL relOK = [rel isKindOfClass:[NSDictionary class]];
            NSString *emoji = @"";
            id er = entry[@"emoji_reaction"];
            if ([er isKindOfClass:[NSDictionary class]] && [er[@"unicode"] isKindOfClass:[NSString class]]) emoji = er[@"unicode"];
            if (!emoji.length) {
                id ers = entry[@"emoji_reactions"];
                if ([ers isKindOfClass:[NSArray class]] && [(NSArray *)ers count]) {
                    id first = ((NSArray *)ers).firstObject;
                    if ([first isKindOfClass:[NSDictionary class]] && [first[@"unicode"] isKindOfClass:[NSString class]]) emoji = first[@"unicode"];
                }
            }
            [out addObject:@{
                @"pk": pkStr,
                @"username": u[@"username"] ?: @"",
                @"full_name": u[@"full_name"] ?: @"",
                @"profile_pic_url": u[@"profile_pic_url"] ?: @"",
                @"is_verified": @([u[@"is_verified"] boolValue]),
                @"liked": @(liked),
                @"following": @(relOK ? [rel[@"following"] boolValue] : NO),
                @"followed_by": @(relOK ? [rel[@"followed_by"] boolValue] : NO),
                @"reaction_emoji": emoji,
            }];
        }
        id nextRaw = response[@"next_max_id"];
        NSString *next = [nextRaw isKindOfClass:[NSString class]] ? nextRaw : ([nextRaw respondsToSelector:@selector(stringValue)] ? [nextRaw stringValue] : nil);
        BOOL more = response[@"more_available"] ? [response[@"more_available"] boolValue] : (next.length > 0);
        NSString *nextCursor = (more && next.length) ? next : nil;
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(out, nextCursor, total, nil); });
    }];
}

+ (void)fetchAllStoryViewersForMediaID:(NSString *)mediaID
                              progress:(void (^)(NSInteger))progress
                            completion:(void (^)(NSArray<NSDictionary *> *, NSInteger, NSError *))completion {
    [self accumulateViewersForMediaID:mediaID cursor:nil into:[NSMutableArray array] page:0 progress:progress completion:completion];
}

+ (void)accumulateViewersForMediaID:(NSString *)mediaID
                             cursor:(NSString *)cursor
                               into:(NSMutableArray *)acc
                               page:(NSInteger)page
                           progress:(void (^)(NSInteger))progress
                         completion:(void (^)(NSArray<NSDictionary *> *, NSInteger, NSError *))completion {
    [self fetchStoryViewersPageForMediaID:mediaID cursor:cursor completion:^(NSArray<NSDictionary *> *viewers, NSString *nextCursor, NSInteger total, NSError *error) {
        if (error && acc.count == 0) { if (completion) completion(acc, 0, error); return; }
        [acc addObjectsFromArray:viewers];
        if (progress) progress(acc.count);
        if (nextCursor.length && page < 200) {
            [self accumulateViewersForMediaID:mediaID cursor:nextCursor into:acc page:page + 1 progress:progress completion:completion];
        } else if (completion) {
            completion(acc, MAX(total, (NSInteger)acc.count), nil);
        }
    }];
}

@end

