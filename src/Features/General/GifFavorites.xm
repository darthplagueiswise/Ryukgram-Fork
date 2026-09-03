// Long-press a picker GIF to favorite (pinned to top), copy its link, or download it.
// Favorites inject into the picker; on tap we hand IG a model so the send builds, then
// step aside so the message renders with IG's real model.

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "GifFavorites.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGDownloadMenu.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../ActionButton/RYGMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static char kRYGGifFavLPKey;
static char kRYGGifFavBadgeKey;

static id ryg_kv(id obj, NSString *key) {
    if (!obj) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

#pragma mark - Storage

static NSArray<NSDictionary *> *ryg_favList(void) {
    NSArray *list = [RYGUtils getArrayPref:@"gif_favorites_list"];
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

static void ryg_favSave(NSArray *list) {
    [RYGUtils setPref:list forKey:@"gif_favorites_list"];
}

static NSUInteger ryg_favIndexOfPK(NSArray<NSDictionary *> *list, NSString *pk) {
    for (NSUInteger i = 0; i < list.count; i++)
        if ([list[i][@"pk"] isEqualToString:pk]) return i;
    return NSNotFound;
}

BOOL rygGifFavContains(NSString *giphyId) {
    return giphyId.length && ryg_favIndexOfPK(ryg_favList(), giphyId) != NSNotFound;
}

BOOL rygGifFavToggleId(NSString *giphyId) {
    if (!giphyId.length) return NO;
    NSMutableArray *list = [ryg_favList() mutableCopy];
    NSUInteger existing = ryg_favIndexOfPK(list, giphyId);
    BOOL nowFav;
    if (existing != NSNotFound) {
        [list removeObjectAtIndex:existing];
        nowFav = NO;
    } else {
        [list insertObject:@{ @"pk": giphyId, @"w": @(200), @"h": @(200) } atIndex:0];
        nowFav = YES;
    }
    ryg_favSave(list);
    return nowFav;
}

#pragma mark - State

// Hand IG our model only while a send is in flight; the render path must fall through
// to IG's own model or the bubble goes blank.
static NSString *gSendingPK;
static __weak id gFetchService;
static __weak id gLauncherSet;

#pragma mark - VM <-> fav dict

static NSString *ryg_cfgURL(id imageModel, NSString *cfgKey) {
    @try {
        id cfg = [imageModel valueForKey:cfgKey];
        id u = cfg ? [cfg valueForKey:@"url"] : nil;
        return [u isKindOfClass:[NSString class]] && [u length] ? u : nil;
    } @catch (__unused id e) { return nil; }
}

// Capture rendition URLs off IG's model at favorite time; guessing from the id breaks when a rendition is missing.
static NSDictionary *ryg_favFromVM(id vm) {
    @try {
        NSString *pk = [vm valueForKey:@"pk"];
        if (![pk isKindOfClass:[NSString class]] || !pk.length) return nil;
        double w = [[vm valueForKey:@"width"] doubleValue];
        double h = [[vm valueForKey:@"height"] doubleValue];
        NSMutableDictionary *fav = [@{ @"pk": pk } mutableCopy];
        id im = nil;
        @try { im = [vm valueForKey:@"imageModel"]; } @catch (__unused id e) {}
        if (im) {
            double iw = [[im valueForKey:@"width"] doubleValue];
            double ih = [[im valueForKey:@"height"] doubleValue];
            if (iw > 0) w = iw;
            if (ih > 0) h = ih;
            NSString *gif = ryg_cfgURL(im, @"gifConfig");
            NSString *mp4 = ryg_cfgURL(im, @"mp4Config");
            NSString *webp = ryg_cfgURL(im, @"webpConfig");
            if (gif) fav[@"gif"] = gif;
            if (mp4) fav[@"mp4"] = mp4;
            if (webp) fav[@"webp"] = webp;
        }
        fav[@"w"] = @(w > 0 ? w : 200);
        fav[@"h"] = @(h > 0 ? h : 200);
        return fav;
    } @catch (__unused id e) { return nil; }
}

static NSString *ryg_favPKFromObject(id obj) {
    if (!obj || ![obj isKindOfClass:NSClassFromString(@"IGDirectAnimatedMediaViewModel")]) return nil;
    @try {
        NSString *pk = [obj valueForKey:@"pk"];
        return [pk isKindOfClass:[NSString class]] && pk.length ? pk : nil;
    } @catch (__unused id e) { return nil; }
}

static id ryg_buildFavModeConfig(Class cfgCls, NSString *urlStr) {
    if (!cfgCls || !urlStr.length) return nil;
    SEL cfgInit = @selector(initWithUrl:dataSizeInByte:);
    if (![cfgCls instancesRespondToSelector:cfgInit]) return nil;
    return ((id(*)(id, SEL, id, double))objc_msgSend)([cfgCls alloc], cfgInit, urlStr, 0.0);
}

// Prefer captured URLs; fall back to the legacy original for favs saved with the id only (e.g. from a comment).
static void ryg_favURLs(NSDictionary *fav, NSString **gif, NSString **mp4, NSString **webp, double *w, double *h) {
    NSString *pk = fav[@"pk"];
    *gif  = [fav[@"gif"]  isKindOfClass:[NSString class]] ? fav[@"gif"]
        : [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.gif",  pk];
    *mp4  = [fav[@"mp4"]  isKindOfClass:[NSString class]] ? fav[@"mp4"]
        : [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.mp4",  pk];
    *webp = [fav[@"webp"] isKindOfClass:[NSString class]] ? fav[@"webp"]
        : [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.webp", pk];
    *w = [fav[@"w"] doubleValue] ?: 200;
    *h = [fav[@"h"] doubleValue] ?: 200;
}

static id ryg_buildImageModel(NSDictionary *fav) {
    Class cfgCls = NSClassFromString(@"IGGiphyGIFModelModeConfig");
    Class imgCls = NSClassFromString(@"IGGiphyImageModel");
    if (!cfgCls || !imgCls) return nil;
    NSString *gif, *mp4, *webp; double w, h;
    ryg_favURLs(fav, &gif, &mp4, &webp, &w, &h);
    id gifCfg  = ryg_buildFavModeConfig(cfgCls, gif);
    id mp4Cfg  = ryg_buildFavModeConfig(cfgCls, mp4);
    id webpCfg = ryg_buildFavModeConfig(cfgCls, webp);
    if (!gifCfg && !mp4Cfg) return nil;
    SEL imgInit = @selector(initWithGifConfig:mp4Config:webpConfig:width:height:);
    if (![imgCls instancesRespondToSelector:imgInit]) return nil;
    return ((id(*)(id, SEL, id, id, id, double, double))objc_msgSend)(
        [imgCls alloc], imgInit, gifCfg, mp4Cfg, webpCfg, w, h);
}

// Sendable model: one image model keyed by NSNumber 1 (IG's shape); no videoModel/altText, they blocked the send.
static id ryg_buildGiphyModel(NSDictionary *fav) {
    Class gifModelCls = NSClassFromString(@"IGGiphyGIFModel");
    NSString *pk = fav[@"pk"];
    if (!gifModelCls || ![pk isKindOfClass:[NSString class]] || !pk.length) return nil;
    id imgModel = ryg_buildImageModel(fav);
    if (!imgModel) return nil;
    NSDictionary *imageModels = @{ @1: imgModel };
    SEL mInit = @selector(initWithIdentifier:imageModels:videoModel:verifiedUsername:isSticker:isAvatarSticker:isAIGenerated:title:expressionId:gifCategory:creationTs:altText:);
    if (![gifModelCls instancesRespondToSelector:mInit]) return nil;
    return ((id(*)(id, SEL, id, id, id, id, BOOL, BOOL, BOOL, id, id, id, id, id))objc_msgSend)(
        [gifModelCls alloc], mInit,
        pk, imageModels, nil, nil, NO, NO, NO, nil, nil, nil, nil, nil);
}

static id ryg_vmFromFav(NSDictionary *fav) {
    Class vmCls = NSClassFromString(@"IGDirectAnimatedMediaViewModel");
    if (!vmCls) return nil;
    NSString *pk = fav[@"pk"];
    if (![pk isKindOfClass:[NSString class]] || !pk.length) return nil;
    NSString *gif, *mp4, *webp; double w, h;
    ryg_favURLs(fav, &gif, &mp4, &webp, &w, &h);
    id imgModel = ryg_buildImageModel(fav);
    if (!imgModel) return nil;
    SEL vmInit = NSSelectorFromString(@"initWithPk:url:cacheIdentifier:width:height:format:backgroundColor:isSticker:imageModel:animatedImageResolver:previewImageSpecifier:creatorUsername:altText:");
    if (![vmCls instancesRespondToSelector:vmInit]) return nil;
    return ((id(*)(id, SEL, id, id, id, double, double, long long, id, BOOL, id, id, id, id, id))objc_msgSend)(
        [vmCls alloc], vmInit,
        pk, [NSURL URLWithString:mp4], mp4,
        w, h, 2 /*format*/, nil, NO,
        imgModel, nil, nil, nil, @"");
}

#pragma mark - Media priming

// Prime the giphy media like IG's search does so the sent bubble has it; the message plays the MP4, so prime video too.
static void ryg_primeMedia(NSDictionary *fav) {
    id model = ryg_buildGiphyModel(fav);
    if (!model) return;
    id svc = gFetchService;
    if (!svc) {
        Class fc = NSClassFromString(@"IGDirectInstamadilloMediaAssetFetchService")
                 ?: NSClassFromString(@"_TtC42IGDirectInstamadilloMediaAssetFetchService42IGDirectInstamadilloMediaAssetFetchService");
        if (fc && gLauncherSet && [fc instancesRespondToSelector:@selector(initWithLauncherSet:)])
            svc = ((id(*)(id, SEL, id))objc_msgSend)([fc alloc], @selector(initWithLauncherSet:), gLauncherSet);
    }
    id session = [RYGUtils activeUserSession];
    SEL sel = @selector(fetchAnimatedMediaWithGiphyModel:userSession:completionHandler:);
    if (!svc || !session || ![svc respondsToSelector:sel]) return;
    void(^noop)(NSURL *, NSData *, CGSize, NSError *) = ^(NSURL *u, NSData *d, CGSize s, NSError *e) {};
    ((void(*)(id, SEL, id, id, id))objc_msgSend)(svc, sel, model, session, noop);

    NSString *gif, *mp4, *webp; double w, h;
    ryg_favURLs(fav, &gif, &mp4, &webp, &w, &h);
    NSURL *vu = mp4.length ? [NSURL URLWithString:mp4] : nil;
    SEL vsel = @selector(fetchVideoWithVideoURL:orVideoResolver:userSession:completionHandler:);
    if (vu && [svc respondsToSelector:vsel]) {
        void(^vnoop)(id, id) = ^(id asset, id err) {};
        ((void(*)(id, SEL, id, id, id, id))objc_msgSend)(svc, vsel, vu, nil, session, vnoop);
    }
}

#pragma mark - Deleted-gif warning

static NSString *ryg_favMP4URLForPK(NSString *pk) {
    NSArray<NSDictionary *> *list = ryg_favList();
    NSUInteger idx = ryg_favIndexOfPK(list, pk);
    if (idx != NSNotFound) {
        NSDictionary *fav = list[idx];
        if ([fav[@"mp4"] isKindOfClass:[NSString class]]) return fav[@"mp4"];
        if ([fav[@"gif"] isKindOfClass:[NSString class]]) return fav[@"gif"];
    }
    return [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.mp4", pk];
}

// A deleted giphy id sends nothing; HEAD-probe so we can surface an error toast.
static void ryg_warnIfFavGone(NSString *pk) {
    if (!pk.length) return;
    NSURL *u = [NSURL URLWithString:ryg_favMP4URLForPK(pk)];
    if (!u) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = @"HEAD";
    req.timeoutInterval = 12;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
        if (!err && code < 400) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            RYGNotifyError(RYG_NOTIF_GIF_FAVORITE,
                           RYGLocalized(@"Favorite GIF unavailable"),
                           RYGLocalized(@"This GIF may have been removed. Long-press it to unfavorite."));
        });
    }] resume];
}

#pragma mark - Favorite badge

static void ryg_setFavBadge(UICollectionViewCell *cell, BOOL show) {
    RYGChromeButton *badge = objc_getAssociatedObject(cell, &kRYGGifFavBadgeKey);
    if (!show) {
        if (badge) [badge removeFromSuperview];
        objc_setAssociatedObject(cell, &kRYGGifFavBadgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!badge) {
        badge = [[RYGChromeButton alloc] initWithSymbol:@"ig_icon_save_outline_24" pointSize:9 diameter:18];
        badge.iconTint = [UIColor systemYellowColor];
        badge.bubbleColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        badge.userInteractionEnabled = NO;
        objc_setAssociatedObject(cell, &kRYGGifFavBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    badge.frame = CGRectMake(5, 5, 18, 18);
    [cell.contentView addSubview:badge];
}

#pragma mark - Long-press

@interface RYGGifFavTarget : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr;
@end

@implementation RYGGifFavTarget

+ (instancetype)shared {
    static RYGGifFavTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [RYGGifFavTarget new]; });
    return t;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UICollectionView *cv = (UICollectionView *)gr.view;
    if (![cv isKindOfClass:[UICollectionView class]]) return;

    NSIndexPath *path = [cv indexPathForItemAtPoint:[gr locationInView:cv]];
    if (!path) return;

    UIViewController *host = nil;
    UIResponder *r = cv;
    Class vcCls = NSClassFromString(@"IGDirectGIFViewController");
    while (r) {
        if ([r isKindOfClass:vcCls]) { host = (UIViewController *)r; break; }
        r = [r nextResponder];
    }
    if (!host) return;

    id adapter = nil;
    @try { adapter = [host valueForKey:@"listAdapter"]; } @catch (__unused id e) {}
    SEL objAtSec = NSSelectorFromString(@"objectAtSection:");
    if (!adapter || ![adapter respondsToSelector:objAtSec]) return;
    id obj = ((id(*)(id, SEL, NSInteger))objc_msgSend)(adapter, objAtSec, path.section);

    NSDictionary *fav = ryg_favFromVM(obj);
    if (!fav) return;

    BOOL favsOn = [RYGUtils getBoolPref:@"gif_favorites_enabled"];
    BOOL downloadOn = [RYGUtils getBoolPref:@"download_gif_comment"];
    if (!favsOn && !downloadOn) return;

    UIViewController *presenter = host;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:nil message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    if (favsOn) {
        NSMutableArray *list = [ryg_favList() mutableCopy];
        NSUInteger existing = ryg_favIndexOfPK(list, fav[@"pk"]);
        BOOL isFav = (existing != NSNotFound);
        NSString *toggleTitle = isFav ? RYGLocalized(@"Unfavorite") : RYGLocalized(@"Favorite");
        [sheet addAction:[UIAlertAction actionWithTitle:toggleTitle
                                                  style:(isFav ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault)
                                                handler:^(UIAlertAction *_) {
            BOOL added = !isFav;
            if (isFav) {
                [list removeObjectAtIndex:existing];
                RYGNotifySuccess(RYG_NOTIF_GIF_FAVORITE, RYGLocalized(@"Removed from favorites"), nil);
            } else {
                [list insertObject:fav atIndex:0];
                RYGNotifySuccess(RYG_NOTIF_GIF_FAVORITE, RYGLocalized(@"Added to favorites"), nil);
            }
            ryg_favSave(list);
            // performUpdates diffs by giphy id and collides with the replaced picker
            // cell (hangs on a spinner); hard reload rebuilds so the image fetches.
            SEL reload = NSSelectorFromString(@"reloadDataWithCompletion:");
            void (^done)(BOOL) = ^(BOOL finished) {
                if (added && cv.numberOfSections > 0)
                    [cv scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]
                               atScrollPosition:UICollectionViewScrollPositionTop animated:YES];
            };
            if ([adapter respondsToSelector:reload])
                ((void(*)(id, SEL, id))objc_msgSend)(adapter, reload, done);
        }]];

        NSString *pk = fav[@"pk"];
        [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Copy GIF link")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_) {
            if (!pk.length) return;
            [UIPasteboard generalPasteboard].string =
                [NSString stringWithFormat:@"https://giphy.com/gifs/%@", pk];
            RYGNotifySuccess(RYG_NOTIF_COPY_GIF, RYGLocalized(@"GIF link copied"), nil);
        }]];
    }

    if (downloadOn) {
        NSString *pk = fav[@"pk"];
        NSURL *gifURL = [NSURL URLWithString:
            [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.gif", pk]];
        [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Download GIF")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_) {
            if (!gifURL) return;
            RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
            md.source = (int16_t)RYGGallerySourceDMs;
            md.sourceMediaPK = pk;
            md.sourceMediaURLString = gifURL.absoluteString;
            md.contextLabel = @"gif";
            if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
                [RYGDownloadMenu presentForURL:gifURL
                                          mode:RYGDownloadMenuModeRemoteURL
                                 fileExtension:@"gif"
                                      hudLabel:RYGLocalized(@"Download GIF")
                                      metadata:md
                                       isAudio:NO
                                        fromVC:nil];
            } else {
                BOOL toPhotos = [[RYGUtils getStringPref:@"dw_save_action"] isEqualToString:@"photos"];
                [RYGDownloadMenu downloadURL:gifURL
                               fileExtension:@"gif"
                                    hudLabel:nil
                                    metadata:md
                                 forceTarget:(toPhotos ? 0 : 2)];
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    sheet.popoverPresentationController.sourceView = cv;
    sheet.popoverPresentationController.sourceRect = [cv cellForItemAtIndexPath:path].frame;
    [presenter presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Hooks

// Sticker-tray GIF tab: prime the media, mark the send in flight, warn if the gif is gone.
%hook IGDirectStoryStickerViewControllerAdapter

- (void)gifViewController:(id)gifVC didSelectAnimatedMediaModel:(id)vm gifCategory:(id)cat stickerContentSize:(CGSize)size {
    NSString *pk = nil;
    @try { pk = [vm valueForKey:@"pk"]; } @catch (__unused id e) {}
    BOOL isFav = [pk isKindOfClass:[NSString class]] && rygGifFavContains(pk);
    @try { if (!gLauncherSet) gLauncherSet = [gifVC valueForKey:@"launcherSet"]; } @catch (__unused id e) {}
    if (isFav) {
        NSArray<NSDictionary *> *list = ryg_favList();
        NSUInteger idx = ryg_favIndexOfPK(list, pk);
        if (idx != NSNotFound) ryg_primeMedia(list[idx]);
    }
    NSString *prevSend = gSendingPK;
    if (isFav) gSendingPK = pk;
    %orig;
    gSendingPK = prevSend;
    if (isFav) ryg_warnIfFavGone(pk);
}

%end

%hook IGDirectGIFViewController

- (NSArray *)objectsForListAdapter:(id)adapter {
    NSArray *orig = %orig;
    if (![RYGUtils getBoolPref:@"gif_favorites_enabled"]) return orig;

    NSString *query = nil;
    @try { query = [self valueForKey:@"searchQuery"]; } @catch (__unused id e) {}
    if ([query isKindOfClass:[NSString class]] && query.length) return orig;

    NSArray<NSDictionary *> *favs = ryg_favList();
    if (!favs.count) return orig;

    @try { if (!gLauncherSet) gLauncherSet = [self valueForKey:@"launcherSet"]; } @catch (__unused id e) {}

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:orig.count + favs.count];
    NSMutableSet *favPKs = [NSMutableSet set];
    for (NSDictionary *f in favs) {
        id vm = ryg_vmFromFav(f);
        if (!vm) continue;
        [out addObject:vm];
        [favPKs addObject:f[@"pk"]];
    }
    for (id obj in orig) {
        NSString *pk = nil;
        @try { pk = [obj valueForKey:@"pk"]; } @catch (__unused id e) {}
        if ([pk isKindOfClass:[NSString class]] && [favPKs containsObject:pk]) continue;
        [out addObject:obj];
    }
    return out;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (![RYGUtils getBoolPref:@"gif_favorites_enabled"] &&
        ![RYGUtils getBoolPref:@"download_gif_comment"]) return;
    UICollectionView *cv = nil;
    @try { cv = [self valueForKey:@"collectionView"]; } @catch (__unused id e) {}
    if (![cv isKindOfClass:[UICollectionView class]]) return;
    if (objc_getAssociatedObject(cv, &kRYGGifFavLPKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[RYGGifFavTarget shared]
                action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.45;
    [cv addGestureRecognizer:lp];
    objc_setAssociatedObject(cv, &kRYGGifFavLPKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

// Star badge on favorited cells; exits unless the CV carries our picker marker.
%hook IGListAdapter

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = %orig;
    if (!objc_getAssociatedObject(collectionView, &kRYGGifFavLPKey)) return cell;
    if (![RYGUtils getBoolPref:@"gif_favorites_enabled"]) { ryg_setFavBadge(cell, NO); return cell; }
    NSString *pk = ryg_favPKFromObject([self objectAtSection:indexPath.section]);
    ryg_setFavBadge(cell, pk && ryg_favIndexOfPK(ryg_favList(), pk) != NSNotFound);
    return cell;
}

%end

// Pinned-only favs have an empty store: while a send is in flight hand IG a built model, else fall through to IG.
%hook IGGiphyDataStore

- (id)giphyModelForGiphyId:(id)giphyId {
    id model = %orig;
    if (model) return model;
    NSString *pk = [giphyId isKindOfClass:[NSString class]] ? giphyId : nil;
    if (pk && [pk isEqualToString:gSendingPK]) {
        NSArray<NSDictionary *> *list = ryg_favList();
        NSUInteger idx = ryg_favIndexOfPK(list, pk);
        if (idx != NSNotFound) return ryg_buildGiphyModel(list[idx]);
    }
    return model;
}

%end

// The send is forwarded here — bracket it so the getter above supplies a model.
%hook IGDirectThreadViewStickersController

- (void)storyStickerViewControllerAdapter:(id)adapter didSelectAnimatedMedia:(id)media {
    NSString *ident = ryg_kv(media, @"identifier");
    BOOL isFav = [ident isKindOfClass:[NSString class]] && rygGifFavContains(ident);
    NSString *prev = gSendingPK;
    if (isFav) gSendingPK = ident;
    %orig;
    gSendingPK = prev;
}

%end

// Capture IG's media fetch service so we can prime favorites through it.
static void (*ryg_orig_fetchAnimatedMedia)(id, SEL, id, id, id);
static void ryg_fetchAnimatedMedia(id self, SEL _cmd, id giphyModel, id session, id completion) {
    gFetchService = self;
    ryg_orig_fetchAnimatedMedia(self, _cmd, giphyModel, session, completion);
}

%ctor {
    Class fetchCls = NSClassFromString(@"IGDirectInstamadilloMediaAssetFetchService")
                   ?: NSClassFromString(@"_TtC42IGDirectInstamadilloMediaAssetFetchService42IGDirectInstamadilloMediaAssetFetchService");
    SEL sel = @selector(fetchAnimatedMediaWithGiphyModel:userSession:completionHandler:);
    if (fetchCls && [fetchCls instancesRespondToSelector:sel])
        MSHookMessageEx(fetchCls, sel, (IMP)ryg_fetchAnimatedMedia, (IMP *)&ryg_orig_fetchAnimatedMedia);
}
