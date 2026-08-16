// See header for the contract.

#import "RYGProfileHelpers.h"
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../Downloader/Download.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGalleryOriginController.h"
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Registry

// Weak on both sides, pruned on each lookup miss since iOS never collects the entries.
static NSMapTable<UIViewController *, id> *rygProfileVCToUser(void) {
    static NSMapTable *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                  valueOptions:NSPointerFunctionsWeakMemory];
    });
    return m;
}

static NSPointerArray *rygActiveProfileVCs(void) {
    static NSPointerArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = [NSPointerArray weakObjectsPointerArray]; });
    return a;
}

static void rygCompactActiveStack(void) {
    NSPointerArray *a = rygActiveProfileVCs();
    [a compact];
}

// MARK: - KVC helpers

static id rygSafe(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

static NSString *rygStr(id v) {
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) ? v : nil;
}

static NSNumber *rygNum(id v) {
    if ([v isKindOfClass:[NSNumber class]]) return v;
    if ([v respondsToSelector:@selector(integerValue)]) return @([v integerValue]);
    return nil;
}

static NSURL *rygURL(id v) {
    if (!v || [v isKindOfClass:[NSNull class]]) return nil;
    if ([v isKindOfClass:[NSURL class]]) return v;
    NSString *s = rygStr(v);
    return s.length ? [NSURL URLWithString:s] : nil;
}

#define rygFieldCacheDict(o) [RYGUtils fieldCacheForObject:(o)]

// MARK: - RYGProfileHelpers

@implementation RYGProfileHelpers

// MARK: - Registry API

+ (void)registerProfileVC:(UIViewController *)vc user:(id)user {
    if (!vc) return;
    if (user) {
        [rygProfileVCToUser() setObject:user forKey:vc];
    }
    NSPointerArray *stack = rygActiveProfileVCs();
    rygCompactActiveStack();
    NSUInteger count = stack.count;
    for (NSUInteger i = 0; i < count; i++) {
        if ((__bridge UIViewController *)[stack pointerAtIndex:i] == vc) {
            [stack removePointerAtIndex:i];
            break;
        }
    }
    [stack addPointer:(__bridge void *)vc];
}

+ (void)unregisterProfileVC:(UIViewController *)vc {
    if (!vc) return;
    NSPointerArray *stack = rygActiveProfileVCs();
    rygCompactActiveStack();
    NSUInteger count = stack.count;
    for (NSUInteger i = 0; i < count; i++) {
        if ((__bridge UIViewController *)[stack pointerAtIndex:i] == vc) {
            [stack removePointerAtIndex:i];
            break;
        }
    }
}

// MARK: - Lookup API

+ (UIViewController *)activeProfileViewController {
    NSPointerArray *stack = rygActiveProfileVCs();
    rygCompactActiveStack();
    NSUInteger n = stack.count;
    return n > 0 ? (__bridge UIViewController *)[stack pointerAtIndex:n - 1] : nil;
}

+ (id)userForViewController:(UIViewController *)vc {
    if (!vc) return nil;

    id user = [rygProfileVCToUser() objectForKey:vc];
    if (user) return user;

    // registerProfileVC runs in viewWillAppear, so first paint can land before it.
    for (NSString *key in @[@"user", @"userGQL", @"profileUser"]) {
        id v = rygSafe(vc, key);
        if (v) return v;
    }
    return nil;
}

+ (id)userForView:(UIView *)view {
    if (!view) return nil;
    Class profileCls = NSClassFromString(@"IGProfileViewController");
    UIResponder *r = view;
    while (r) {
        if (profileCls && [r isKindOfClass:profileCls]) {
            return [self userForViewController:(UIViewController *)r];
        }
        r = [r nextResponder];
    }
    return [self userForViewController:[self activeProfileViewController]];
}

// MARK: - User accessors

+ (NSString *)usernameForUser:(id)user {
    NSString *s = rygStr(rygSafe(user, @"username"));
    if (!s) {
        NSDictionary *fc = rygFieldCacheDict(user);
        s = rygStr(fc[@"username"]);
    }
    return s;
}

+ (NSString *)pkForUser:(id)user {
    NSString *s = rygStr(rygSafe(user, @"pk"));
    if (!s) s = rygStr(rygSafe(user, @"id"));
    if (!s) {
        NSDictionary *fc = rygFieldCacheDict(user);
        s = rygStr(fc[@"pk"]) ?: rygStr(fc[@"strong_id__"]) ?: rygStr(fc[@"id"]);
    }
    return s;
}

+ (NSString *)fullNameForUser:(id)user {
    NSString *s = rygStr(rygSafe(user, @"fullName"));
    if (!s) s = rygStr(rygSafe(user, @"full_name"));
    if (!s) s = rygStr(rygSafe(user, @"name"));
    if (!s) {
        NSDictionary *fc = rygFieldCacheDict(user);
        s = rygStr(fc[@"full_name"]);
    }
    return s;
}

+ (NSString *)biographyForUser:(id)user {
    NSString *s = rygStr(rygSafe(user, @"biography"));
    if (!s) s = rygStr(rygSafe(user, @"bio"));
    if (!s) {
        NSDictionary *fc = rygFieldCacheDict(user);
        s = rygStr(fc[@"biography"]);
    }
    return s;
}

+ (NSURL *)profileLinkForUser:(id)user {
    NSString *u = [self usernameForUser:user];
    if (!u.length) return nil;
    NSString *enc = [u stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    return enc.length ? [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", enc]] : nil;
}

+ (NSNumber *)privacyStatusForUser:(id)user {
    NSNumber *n = rygNum(rygSafe(user, @"privacyStatus"));
    if (n) return n;
    NSDictionary *fc = rygFieldCacheDict(user);
    n = rygNum(fc[@"privacy_status"]);
    if (n) return n;
    id b = rygSafe(user, @"isPrivate");
    if (!b) b = rygSafe(user, @"privateAccount");
    if (!b) b = fc[@"is_private"];
    if ([b respondsToSelector:@selector(boolValue)]) {
        return @([b boolValue] ? 2 : 1);
    }
    return nil;
}

+ (NSNumber *)followerCountForUser:(id)user {
    NSNumber *n = rygNum(rygSafe(user, @"followerCount"));
    if (n) return n;
    NSDictionary *fc = rygFieldCacheDict(user);
    return rygNum(fc[@"follower_count"]);
}

+ (NSNumber *)followingCountForUser:(id)user {
    NSNumber *n = rygNum(rygSafe(user, @"followingCount"));
    if (n) return n;
    NSDictionary *fc = rygFieldCacheDict(user);
    return rygNum(fc[@"following_count"]);
}

// MARK: - Picture URL

+ (NSURL *)cachedPictureURLForUser:(id)user {
    if (!user) return nil;
    NSDictionary *fc = rygFieldCacheDict(user);

    // 1. fieldCache hd_profile_pic_url_info → { url, ... }
    id hd = fc[@"hd_profile_pic_url_info"];
    if ([hd isKindOfClass:[NSDictionary class]]) {
        NSURL *u = rygURL(((NSDictionary *)hd)[@"url"]);
        if (u) return u;
    }
    // 2. hd_profile_pic_versions array → take the largest.
    NSArray *versions = fc[@"hd_profile_pic_versions"];
    if ([versions isKindOfClass:[NSArray class]] && versions.count) {
        id last = versions.lastObject;
        if ([last isKindOfClass:[NSDictionary class]]) {
            NSURL *u = rygURL(((NSDictionary *)last)[@"url"]);
            if (u) return u;
        }
    }
    // 3. Plain profile_pic_url.
    NSURL *u = rygURL(fc[@"profile_pic_url"]);
    if (u) return u;

    // 4. KVC accessor variants (older IGUser shapes).
    for (NSString *sel in @[@"profilePicURLHd", @"profilePicURLHD",
                             @"profilePicURLString", @"profilePicURL",
                             @"profilePictureURL", @"hdProfilePicURL"]) {
        id v = rygSafe(user, sel);
        u = rygURL(v);
        if (u) return u;
    }
    return nil;
}

+ (void)resolveHDPictureURLForUser:(id)user
                          completion:(void(^)(NSURL * _Nullable url))completion {
    if (!completion) return;
    [self resolveHDPictureURLForPK:[self pkForUser:user]
                            cached:[self cachedPictureURLForUser:user]
                        completion:completion];
}

+ (void)resolveHDPictureURLForPK:(NSString *)pk
                          cached:(NSURL *)cached
                      completion:(void(^)(NSURL * _Nullable url))completion {
    if (!completion) return;
    if (!pk.length) {
        completion(cached);
        return;
    }

    NSString *path = [NSString stringWithFormat:@"users/%@/info/", pk];
    [RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil
                                completion:^(NSDictionary *response, NSError *error) {
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            completion(cached);
            return;
        }
        NSDictionary *u = response[@"user"];
        if (![u isKindOfClass:[NSDictionary class]]) { completion(cached); return; }

        NSDictionary *hd = u[@"hd_profile_pic_url_info"];
        if ([hd isKindOfClass:[NSDictionary class]]) {
            NSURL *url = rygURL(hd[@"url"]);
            if (url) { completion(url); return; }
        }
        NSArray *versions = u[@"hd_profile_pic_versions"];
        if ([versions isKindOfClass:[NSArray class]] && versions.count) {
            id last = versions.lastObject;
            if ([last isKindOfClass:[NSDictionary class]]) {
                NSURL *url = rygURL(((NSDictionary *)last)[@"url"]);
                if (url) { completion(url); return; }
            }
        }
        NSURL *url = rygURL(u[@"profile_pic_url"]);
        completion(url ?: cached);
    }];
}

// MARK: - Caption

+ (NSString *)captionForUser:(id)user {
    NSString *name = [self fullNameForUser:user];
    NSString *username = [self usernameForUser:user];
    NSString *bio = [self biographyForUser:user];
    NSMutableString *out = [NSMutableString string];
    if (name.length) [out appendString:name];
    if (username.length) {
        if (out.length) [out appendString:@"\n"];
        [out appendFormat:@"@%@", username];
    }
    if (bio.length) {
        if (out.length) [out appendString:@"\n\n"];
        [out appendString:bio];
    }
    return out.length ? out : nil;
}

// MARK: - Actions

static RYGGallerySaveMetadata *rygProfileGalleryMetadata(id user);

+ (void)viewPictureForUser:(id)user {
    if (!user) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")];
        return;
    }
    NSString *caption = [self captionForUser:user];
    NSURL *cached = [self cachedPictureURLForUser:user];

    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        NSURL *target = url ?: cached;
        if (!target) {
            [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")];
            return;
        }
        RYGMediaViewerItem *item = [RYGMediaViewerItem itemWithVideoURL:nil
                                                                photoURL:target
                                                                 caption:caption];
        item.metadata = rygProfileGalleryMetadata(user);
        [RYGMediaViewer showItem:item];
    }];
}

static RYGGallerySaveMetadata *rygProfileGalleryMetadata(id user) {
    RYGGallerySaveMetadata *m = [[RYGGallerySaveMetadata alloc] init];
    m.source = (int16_t)RYGGallerySourceProfile;
    NSString *username = [RYGProfileHelpers usernameForUser:user];
    @try { [RYGGalleryOriginController populateProfileMetadata:m username:username user:user]; }
    @catch (__unused id e) {}
    return m;
}

+ (void)viewPictureForPK:(NSString *)pk fallbackURL:(NSURL *)fallbackURL {
    [self resolveHDPictureURLForPK:pk cached:fallbackURL completion:^(NSURL *url) {
        NSURL *target = url ?: fallbackURL;
        if (!target) {
            [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")];
            return;
        }
        [RYGMediaViewer showWithVideoURL:nil photoURL:target caption:nil];
    }];
}

+ (void)sharePictureForUser:(id)user {
    if (!user) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")];
        return;
    }
    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")]; return; }
        NSString *ext = [[url pathExtension] lowercaseString];
        if (!ext.length) ext = @"jpg";
        RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:share showProgress:YES];
        dl.pendingGallerySaveMetadata = rygProfileGalleryMetadata(user);
        [dl downloadFileWithURL:url fileExtension:ext hudLabel:nil];
    }];
}

+ (void)savePictureForUser:(id)user {
    if (!user) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")];
        return;
    }
    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")]; return; }
        NSString *ext = [[url pathExtension] lowercaseString];
        if (!ext.length) ext = @"jpg";

        RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:YES];
        dl.pendingGallerySaveMetadata = rygProfileGalleryMetadata(user);
        [dl downloadFileWithURL:url fileExtension:ext hudLabel:nil];
    }];
}

+ (void)savePictureToGalleryForUser:(id)user {
    if (!user) {
        [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")];
        return;
    }
    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Picture not found")]; return; }
        NSString *ext = [[url pathExtension] lowercaseString];
        if (!ext.length) ext = @"jpg";
        RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:saveToGallery showProgress:YES];
        dl.pendingGallerySaveMetadata = rygProfileGalleryMetadata(user);
        [dl downloadFileWithURL:url fileExtension:ext hudLabel:nil];
    }];
}

@end


// MARK: - Hooks

%hook IGProfileViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    id user = nil;
    for (NSString *key in @[@"user", @"userGQL", @"profileUser"]) {
        @try { user = [self valueForKey:key]; } @catch (__unused id e) {}
        if (user) break;
    }
    [RYGProfileHelpers registerProfileVC:self user:user];
}

- (void)viewWillDisappear:(BOOL)animated {
    [RYGProfileHelpers unregisterProfileVC:self];
    %orig;
}

%end
