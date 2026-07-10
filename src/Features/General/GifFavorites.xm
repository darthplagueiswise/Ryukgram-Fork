// Long-press a picker GIF to favorite (pinned to top), copy its link, or download it.
// Favorites inject into the picker; on tap we hand IG a model so the send builds, then
// step aside so the message renders with IG's real model.

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "GifFavorites.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIDownloadMenu.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../ActionButton/SCIMediaActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static char kSCIGifFavLPKey;
static char kSCIGifFavBadgeKey;

static id sci_kv(id obj, NSString *key) {
    if (!obj) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

#pragma mark - Storage

static NSArray<NSDictionary *> *sci_favList(void) {
    NSArray *list = [SCIUtils getArrayPref:@"gif_favorites_list"];
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

static void sci_favSave(NSArray *list) {
    [SCIUtils setPref:list forKey:@"gif_favorites_list"];
}

static NSUInteger sci_favIndexOfPK(NSArray<NSDictionary *> *list, NSString *pk) {
    for (NSUInteger i = 0; i < list.count; i++)
        if ([list[i][@"pk"] isEqualToString:pk]) return i;
    return NSNotFound;
}

BOOL sciGifFavContains(NSString *giphyId) {
    return giphyId.length && sci_favIndexOfPK(sci_favList(), giphyId) != NSNotFound;
}

BOOL sciGifFavToggleId(NSString *giphyId) {
    if (!giphyId.length) return NO;
    NSMutableArray *list = [sci_favList() mutableCopy];
    NSUInteger existing = sci_favIndexOfPK(list, giphyId);
    BOOL nowFav;
    if (existing != NSNotFound) {
        [list removeObjectAtIndex:existing];
        nowFav = NO;
    } else {
        [list insertObject:@{ @"pk": giphyId, @"w": @(200), @"h": @(200) } atIndex:0];
        nowFav = YES;
    }
    sci_favSave(list);
    return nowFav;
}

#pragma mark - State

// Hand IG our model only while a send is in flight; the render path must fall through
// to IG's own model or the bubble goes blank.
static NSString *gSendingPK;
static __weak id gFetchService;
static __weak id gLauncherSet;

#pragma mark - VM <-> fav dict

static NSString *sci_cfgURL(id imageModel, NSString *cfgKey) {
    @try {
        id cfg = [imageModel valueForKey:cfgKey];
        id u = cfg ? [cfg valueForKey:@"url"] : nil;
        return [u isKindOfClass:[NSString class]] && [u length] ? u : nil;
    } @catch (__unused id e) { return nil; }
}

// Capture rendition URLs off IG's model at favorite time; guessing from the id breaks when a rendition is missing.
static NSDictionary *sci_favFromVM(id vm) {
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
            NSString *gif = sci_cfgURL(im, @"gifConfig");
            NSString *mp4 = sci_cfgURL(im, @"mp4Config");
            NSString *webp = sci_cfgURL(im, @"webpConfig");
            if (gif) fav[@"gif"] = gif;
            if (mp4) fav[@"mp4"] = mp4;
            if (webp) fav[@"webp"] = webp;
        }
        fav[@"w"] = @(w > 0 ? w : 200);
        fav[@"h"] = @(h > 0 ? h : 200);
        return fav;
    } @catch (__unused id e) { return nil; }
}

static NSString *sci_favPKFromObject(id obj) {
    if (!obj || ![obj isKindOfClass:NSClassFromString(@"IGDirectAnimatedMediaViewModel")]) return nil;
    @try {
        NSString *pk = [obj valueForKey:@"pk"];
        return [pk isKindOfClass:[NSString class]] && pk.length ? pk : nil;
    } @catch (__unused id e) { return nil; }
}

static id sci_buildFavModeConfig(Class cfgCls, NSString *urlStr) {
    if (!cfgCls || !urlStr.length) return nil;
    SEL cfgInit = @selector(initWithUrl:dataSizeInByte:);
    if (![cfgCls instancesRespondToSelector:cfgInit]) return nil;
    return ((id(*)(id, SEL, id, double))objc_msgSend)([cfgCls alloc], cfgInit, urlStr, 0.0);
}

// Prefer captured URLs; fall back to the legacy original for favs saved with the id only (e.g. from a comment).
static void sci_favURLs(NSDictionary *fav, NSString **gif, NSString **mp4, NSString **webp, double *w, double *h) {
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

static id sci_buildImageModel(NSDictionary *fav) {
    Class cfgCls = NSClassFromString(@"IGGiphyGIFModelModeConfig");
    Class imgCls = NSClassFromString(@"IGGiphyImageModel");
    if (!cfgCls || !imgCls) return nil;
    NSString *gif, *mp4, *webp; double w, h;
    sci_favURLs(fav, &gif, &mp4, &webp, &w, &h);
    id gifCfg  = sci_buildFavModeConfig(cfgCls, gif);
    id mp4Cfg  = sci_buildFavModeConfig(cfgCls, mp4);
    id webpCfg = sci_buildFavModeConfig(cfgCls, webp);
    if (!gifCfg && !mp4Cfg) return nil;
    SEL imgInit = @selector(initWithGifConfig:mp4Config:webpConfig:width:height:);
    if (![imgCls instancesRespondToSelector:imgInit]) return nil;
    return ((id(*)(id, SEL, id, id, id, double, double))objc_msgSend)(
        [imgCls alloc], imgInit, gifCfg, mp4Cfg, webpCfg, w, h);
}

// Sendable model: one image model keyed by NSNumber 1 (IG's shape); no videoModel/altText, they blocked the send.
static id sci_buildGiphyModel(NSDictionary *fav) {
    Class gifModelCls = NSClassFromString(@"IGGiphyGIFModel");
    NSString *pk = fav[@"pk"];
    if (!gifModelCls || ![pk isKindOfClass:[NSString class]] || !pk.length) return nil;
    id imgModel = sci_buildImageModel(fav);
    if (!imgModel) return nil;
    NSDictionary *imageModels = @{ @1: imgModel };
    SEL mInit = @selector(initWithIdentifier:imageModels:videoModel:verifiedUsername:isSticker:isAvatarSticker:isAIGenerated:title:expressionId:gifCategory:creationTs:altText:);
    if (![gifModelCls instancesRespondToSelector:mInit]) return nil;
    return ((id(*)(id, SEL, id, id, id, id, BOOL, BOOL, BOOL, id, id, id, id, id))objc_msgSend)(
        [gifModelCls alloc], mInit,
        pk, imageModels, nil, nil, NO, NO, NO, nil, nil, nil, nil, nil);
}

static id sci_vmFromFav(NSDictionary *fav) {
    Class vmCls = NSClassFromString(@"IGDirectAnimatedMediaViewModel");
    if (!vmCls) return nil;
    NSString *pk = fav[@"pk"];
    if (![pk isKindOfClass:[NSString class]] || !pk.length) return nil;
    NSString *gif, *mp4, *webp; double w, h;
    sci_favURLs(fav, &gif, &mp4, &webp, &w, &h);
    id imgModel = sci_buildImageModel(fav);
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
static void sci_primeMedia(NSDictionary *fav) {
    id model = sci_buildGiphyModel(fav);
    if (!model) return;
    id svc = gFetchService;
    if (!svc) {
        Class fc = NSClassFromString(@"IGDirectInstamadilloMediaAssetFetchService")
                 ?: NSClassFromString(@"_TtC42IGDirectInstamadilloMediaAssetFetchService42IGDirectInstamadilloMediaAssetFetchService");
        if (fc && gLauncherSet && [fc instancesRespondToSelector:@selector(initWithLauncherSet:)])
            svc = ((id(*)(id, SEL, id))objc_msgSend)([fc alloc], @selector(initWithLauncherSet:), gLauncherSet);
    }
    id session = [SCIUtils activeUserSession];
    SEL sel = @selector(fetchAnimatedMediaWithGiphyModel:userSession:completionHandler:);
    if (!svc || !session || ![svc respondsToSelector:sel]) return;
    void(^noop)(NSURL *, NSData *, CGSize, NSError *) = ^(NSURL *u, NSData *d, CGSize s, NSError *e) {};
    ((void(*)(id, SEL, id, id, id))objc_msgSend)(svc, sel, model, session, noop);

    NSString *gif, *mp4, *webp; double w, h;
    sci_favURLs(fav, &gif, &mp4, &webp, &w, &h);
    NSURL *vu = mp4.length ? [NSURL URLWithString:mp4] : nil;
    SEL vsel = @selector(fetchVideoWithVideoURL:orVideoResolver:userSession:completionHandler:);
    if (vu && [svc respondsToSelector:vsel]) {
        void(^vnoop)(id, id) = ^(id asset, id err) {};
        ((void(*)(id, SEL, id, id, id, id))objc_msgSend)(svc, vsel, vu, nil, session, vnoop);
    }
}

#pragma mark - Deleted-gif warning

static NSString *sci_favMP4URLForPK(NSString *pk) {
    NSArray<NSDictionary *> *list = sci_favList();
    NSUInteger idx = sci_favIndexOfPK(list, pk);
    if (idx != NSNotFound) {
        NSDictionary *fav = list[idx];
        if ([fav[@"mp4"] isKindOfClass:[NSString class]]) return fav[@"mp4"];
        if ([fav[@"gif"] isKindOfClass:[NSString class]]) return fav[@"gif"];
    }
    return [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.mp4", pk];
}

// A deleted giphy id sends nothing; HEAD-probe so we can surface an error toast.
static void sci_warnIfFavGone(NSString *pk) {
    if (!pk.length) return;
    NSURL *u = [NSURL URLWithString:sci_favMP4URLForPK(pk)];
    if (!u) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = @"HEAD";
    req.timeoutInterval = 12;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
        if (!err && code < 400) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            SCINotifyError(SCI_NOTIF_GIF_FAVORITE,
                           SCILocalized(@"Favorite GIF unavailable"),
                           SCILocalized(@"This GIF may have been removed. Long-press it to unfavorite."));
        });
    }] resume];
}

#pragma mark - Favorite badge

static void sci_setFavBadge(UICollectionViewCell *cell, BOOL show) {
    SCIChromeButton *badge = objc_getAssociatedObject(cell, &kSCIGifFavBadgeKey);
    if (!show) {
        if (badge) [badge removeFromSuperview];
        objc_setAssociatedObject(cell, &kSCIGifFavBadgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!badge) {
        badge = [[SCIChromeButton alloc] initWithSymbol:@"star.fill" pointSize:9 diameter:18];
        badge.iconTint = [UIColor systemYellowColor];
        badge.bubbleColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        badge.userInteractionEnabled = NO;
        objc_setAssociatedObject(cell, &kSCIGifFavBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    badge.frame = CGRectMake(5, 5, 18, 18);
    [cell.contentView addSubview:badge];
}

#pragma mark - Long-press

@interface SCIGifFavTarget : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr;
@end

@implementation SCIGifFavTarget

+ (instancetype)shared {
    static SCIGifFavTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [SCIGifFavTarget new]; });
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

    NSDictionary *fav = sci_favFromVM(obj);
    if (!fav) return;

    BOOL favsOn = [SCIUtils getBoolPref:@"gif_favorites_enabled"];
    BOOL downloadOn = [SCIUtils getBoolPref:@"download_gif_comment"];
    if (!favsOn && !downloadOn) return;

    UIViewController *presenter = host;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:nil message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    if (favsOn) {
        NSMutableArray *list = [sci_favList() mutableCopy];
        NSUInteger existing = sci_favIndexOfPK(list, fav[@"pk"]);
        BOOL isFav = (existing != NSNotFound);
        NSString *toggleTitle = isFav ? SCILocalized(@"Unfavorite") : SCILocalized(@"Favorite");
        [sheet addAction:[UIAlertAction actionWithTitle:toggleTitle
                                                  style:(isFav ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault)
                                                handler:^(UIAlertAction *_) {
            BOOL added = !isFav;
            if (isFav) {
                [list removeObjectAtIndex:existing];
                SCINotifySuccess(SCI_NOTIF_GIF_FAVORITE, SCILocalized(@"Removed from favorites"), nil);
            } else {
                [list insertObject:fav atIndex:0];
                SCINotifySuccess(SCI_NOTIF_GIF_FAVORITE, SCILocalized(@"Added to favorites"), nil);
            }
            sci_favSave(list);
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
        [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy GIF link")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_) {
            if (!pk.length) return;
            [UIPasteboard generalPasteboard].string =
                [NSString stringWithFormat:@"https://giphy.com/gifs/%@", pk];
            SCINotifySuccess(SCI_NOTIF_COPY_GIF, SCILocalized(@"GIF link copied"), nil);
        }]];
    }

    if (downloadOn) {
        NSString *pk = fav[@"pk"];
        NSURL *gifURL = [NSURL URLWithString:
            [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.gif", pk]];
        [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Download GIF")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_) {
            if (!gifURL) return;
            SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
            md.source = (int16_t)SCIGallerySourceDMs;
            md.sourceMediaPK = pk;
            md.sourceMediaURLString = gifURL.absoluteString;
            [SCIMediaActions setCurrentFilenameStem:
                [SCIMediaActions filenameStemForUsername:nil contextLabel:@"gif"]];
            if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
                [SCIDownloadMenu presentForURL:gifURL
                                          mode:SCIDownloadMenuModeRemoteURL
                                 fileExtension:@"gif"
                                      hudLabel:SCILocalized(@"Download GIF")
                                      metadata:md
                                       isAudio:NO
                                        fromVC:nil];
            } else {
                BOOL toPhotos = [[SCIUtils getStringPref:@"dw_save_action"] isEqualToString:@"photos"];
                [SCIDownloadMenu downloadURL:gifURL
                               fileExtension:@"gif"
                                    hudLabel:nil
                                    metadata:md
                                 forceTarget:(toPhotos ? 0 : 2)];
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
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
    BOOL isFav = [pk isKindOfClass:[NSString class]] && sciGifFavContains(pk);
    @try { if (!gLauncherSet) gLauncherSet = [gifVC valueForKey:@"launcherSet"]; } @catch (__unused id e) {}
    if (isFav) {
        NSArray<NSDictionary *> *list = sci_favList();
        NSUInteger idx = sci_favIndexOfPK(list, pk);
        if (idx != NSNotFound) sci_primeMedia(list[idx]);
    }
    NSString *prevSend = gSendingPK;
    if (isFav) gSendingPK = pk;
    %orig;
    gSendingPK = prevSend;
    if (isFav) sci_warnIfFavGone(pk);
}

%end

%hook IGDirectGIFViewController

- (NSArray *)objectsForListAdapter:(id)adapter {
    NSArray *orig = %orig;
    if (![SCIUtils getBoolPref:@"gif_favorites_enabled"]) return orig;

    NSString *query = nil;
    @try { query = [self valueForKey:@"searchQuery"]; } @catch (__unused id e) {}
    if ([query isKindOfClass:[NSString class]] && query.length) return orig;

    NSArray<NSDictionary *> *favs = sci_favList();
    if (!favs.count) return orig;

    @try { if (!gLauncherSet) gLauncherSet = [self valueForKey:@"launcherSet"]; } @catch (__unused id e) {}

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:orig.count + favs.count];
    NSMutableSet *favPKs = [NSMutableSet set];
    for (NSDictionary *f in favs) {
        id vm = sci_vmFromFav(f);
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
    if (![SCIUtils getBoolPref:@"gif_favorites_enabled"] &&
        ![SCIUtils getBoolPref:@"download_gif_comment"]) return;
    UICollectionView *cv = nil;
    @try { cv = [self valueForKey:@"collectionView"]; } @catch (__unused id e) {}
    if (![cv isKindOfClass:[UICollectionView class]]) return;
    if (objc_getAssociatedObject(cv, &kSCIGifFavLPKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[SCIGifFavTarget shared]
                action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.45;
    [cv addGestureRecognizer:lp];
    objc_setAssociatedObject(cv, &kSCIGifFavLPKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

// Star badge on favorited cells; exits unless the CV carries our picker marker.
%hook IGListAdapter

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = %orig;
    if (!objc_getAssociatedObject(collectionView, &kSCIGifFavLPKey)) return cell;
    if (![SCIUtils getBoolPref:@"gif_favorites_enabled"]) { sci_setFavBadge(cell, NO); return cell; }
    NSString *pk = sci_favPKFromObject([self objectAtSection:indexPath.section]);
    sci_setFavBadge(cell, pk && sci_favIndexOfPK(sci_favList(), pk) != NSNotFound);
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
        NSArray<NSDictionary *> *list = sci_favList();
        NSUInteger idx = sci_favIndexOfPK(list, pk);
        if (idx != NSNotFound) return sci_buildGiphyModel(list[idx]);
    }
    return model;
}

%end

// The send is forwarded here — bracket it so the getter above supplies a model.
%hook IGDirectThreadViewStickersController

- (void)storyStickerViewControllerAdapter:(id)adapter didSelectAnimatedMedia:(id)media {
    NSString *ident = sci_kv(media, @"identifier");
    BOOL isFav = [ident isKindOfClass:[NSString class]] && sciGifFavContains(ident);
    NSString *prev = gSendingPK;
    if (isFav) gSendingPK = ident;
    %orig;
    gSendingPK = prev;
}

%end

// Capture IG's media fetch service so we can prime favorites through it.
static void (*sci_orig_fetchAnimatedMedia)(id, SEL, id, id, id);
static void sci_fetchAnimatedMedia(id self, SEL _cmd, id giphyModel, id session, id completion) {
    gFetchService = self;
    sci_orig_fetchAnimatedMedia(self, _cmd, giphyModel, session, completion);
}

%ctor {
    Class fetchCls = NSClassFromString(@"IGDirectInstamadilloMediaAssetFetchService")
                   ?: NSClassFromString(@"_TtC42IGDirectInstamadilloMediaAssetFetchService42IGDirectInstamadilloMediaAssetFetchService");
    SEL sel = @selector(fetchAnimatedMediaWithGiphyModel:userSession:completionHandler:);
    if (fetchCls && [fetchCls instancesRespondToSelector:sel])
        MSHookMessageEx(fetchCls, sel, (IMP)sci_fetchAnimatedMedia, (IMP *)&sci_orig_fetchAnimatedMedia);
}
