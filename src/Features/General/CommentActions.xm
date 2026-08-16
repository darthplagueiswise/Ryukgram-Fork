// Comment long-press menu extras: copy text + GIF / image media submenu.
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../UI/RYGIcon.h"
#import "../../UI/RYGDownloadMenu.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "../../ActionButton/RYGMediaActions.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../StoriesAndMessages/RYGDirectUserResolver.h"
#import "GifFavorites.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static DownloadAction rygGifDownloadAction(void) {
    NSString *method = [RYGUtils getStringPref:@"dw_save_action"];
    return [method isEqualToString:@"photos"] ? saveToPhotos : share;
}

static id rygCommentUser(id comment) {
    for (NSString *key in @[@"user", @"author", @"commenter"]) {
        @try {
            id u = [comment valueForKey:key];
            if (u) return u;
        } @catch (__unused id e) {}
    }
    return nil;
}

static RYGGallerySaveMetadata *rygMetadataForComment(id comment, NSString *mediaPK,
                                                    NSString *urlStr, NSString *contextLabel) {
    id user = rygCommentUser(comment);
    RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
    md.source = (int16_t)RYGGallerySourceComments;
    if (mediaPK.length) md.sourceMediaPK = mediaPK;
    if (urlStr.length) md.sourceMediaURLString = urlStr;
    md.sourceUsername = rygDirectUserResolverUsernameFromUser(user);
    md.sourceUserPK = rygDirectUserResolverPKFromUser(user);
    md.sourceProfileURLString = rygDirectUserResolverProfilePicURLStringFromUser(user);
    [RYGMediaActions setCurrentFilenameStem:
        [RYGMediaActions filenameStemForUsername:md.sourceUsername contextLabel:contextLabel]];
    return md;
}

static void rygDownloadCommentMedia(NSURL *url, NSString *ext, NSString *hudLabel,
                                    RYGGallerySaveMetadata *md) {
    if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
        [RYGDownloadMenu presentForURL:url
                                  mode:RYGDownloadMenuModeRemoteURL
                         fileExtension:ext
                              hudLabel:hudLabel
                              metadata:md
                               isAudio:NO
                                fromVC:nil];
    } else {
        [RYGDownloadMenu downloadURL:url
                       fileExtension:ext
                            hudLabel:nil
                            metadata:md
                         forceTarget:(rygGifDownloadAction() == saveToPhotos ? 0 : 2)];
    }
}

static NSString *rygGifURLFromComment(id comment, NSString **outGifId) {
    if (outGifId) *outGifId = nil;
    NSString *gifId = nil;
    @try {
        SEL sel = NSSelectorFromString(@"gifMediaId");
        if ([comment respondsToSelector:sel])
            gifId = ((id(*)(id,SEL))objc_msgSend)(comment, sel);
    } @catch (__unused id e) {}
    if (!gifId.length) return nil;
    if (outGifId) *outGifId = gifId;

    Ivar attIvar = class_getInstanceVariable([comment class], "_commentAttachment");
    id att = attIvar ? object_getIvar(comment, attIvar) : nil;
    if (!att) return nil;
    Ivar urlIvar = class_getInstanceVariable([att class], "_image_imageURL");
    if (!urlIvar) return nil;
    id url = object_getIvar(att, urlIvar);
    if ([url isKindOfClass:[NSString class]]) return url;
    if ([url isKindOfClass:[NSURL class]]) return [(NSURL *)url absoluteString];
    return nil;
}

// Photo-comment URL chain documented in CLAUDE.md "PandoTree storable map".
static NSURL *rygImageURLFromComment(id comment, NSString **outMediaId) {
    if (outMediaId) *outMediaId = nil;
    @try {
        SEL isPh = @selector(isPhotoComment);
        if (![comment respondsToSelector:isPh]) return nil;
        if (!((BOOL(*)(id,SEL))objc_msgSend)(comment, isPh)) return nil;

        Ivar apiIvar = class_getInstanceVariable([comment class], "_internalApiCommentDict");
        if (!apiIvar) return nil;
        id apiDict = object_getIvar(comment, apiIvar);
        if (!apiDict) return nil;

        Ivar somIvar = NULL;
        Class c = [apiDict class];
        while (c && c != [NSObject class]) {
            somIvar = class_getInstanceVariable(c, "_storableObjectMap");
            if (somIvar) break;
            c = class_getSuperclass(c);
        }
        if (!somIvar) return nil;
        id som = object_getIvar(apiDict, somIvar);
        if (![som isKindOfClass:[NSDictionary class]]) return nil;

        id media = nil;
        for (id k in (NSDictionary *)som) {
            id v = ((NSDictionary *)som)[k];
            if (![v isKindOfClass:[NSDictionary class]]) continue;
            id m = ((NSDictionary *)v)[@"media"];
            if (m) { media = m; break; }
        }
        if (!media) return nil;

        if (outMediaId) {
            SEL mIdSel = @selector(mediaId);
            if ([media respondsToSelector:mIdSel]) {
                id r = ((id(*)(id,SEL))objc_msgSend)(media, mIdSel);
                if ([r isKindOfClass:[NSString class]]) *outMediaId = r;
            }
        }

        SEL iv2Sel = @selector(imageVersions2);
        if (![media respondsToSelector:iv2Sel]) return nil;
        id iv2 = ((id(*)(id,SEL))objc_msgSend)(media, iv2Sel);
        if (!iv2) return nil;

        SEL candSel = @selector(candidates);
        if (![iv2 respondsToSelector:candSel]) return nil;
        NSArray *cands = ((id(*)(id,SEL))objc_msgSend)(iv2, candSel);
        if (![cands isKindOfClass:[NSArray class]] || cands.count == 0) return nil;

        id best = nil;
        NSInteger bestW = -1;
        SEL ws = @selector(width);
        for (id cand in cands) {
            NSInteger w = 0;
            if ([cand respondsToSelector:ws]) {
                id wn = ((id(*)(id,SEL))objc_msgSend)(cand, ws);
                if ([wn isKindOfClass:[NSNumber class]]) w = [wn integerValue];
            }
            if (w > bestW) { bestW = w; best = cand; }
        }
        if (!best) return nil;

        SEL urlSel = NSSelectorFromString(@"urlString");
        if (![best respondsToSelector:urlSel]) return nil;
        id urlStr = ((id(*)(id,SEL))objc_msgSend)(best, urlSel);
        if (![urlStr isKindOfClass:[NSString class]]) return nil;
        return [NSURL URLWithString:urlStr];
    } @catch (__unused id e) {}
    return nil;
}

static void rygPresentInViewer(NSURL *url, NSString *username, BOOL animated) {
    if (!url) return;
    RYGMediaViewerItem *item = animated
        ? [RYGMediaViewerItem itemWithAnimatedImageURL:url caption:nil]
        : [RYGMediaViewerItem itemWithVideoURL:nil photoURL:url caption:nil];
    RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
    md.source = (int16_t)RYGGallerySourceComments;
    md.sourceUsername = username;
    md.sourceMediaURLString = [url absoluteString];
    item.metadata = md;
    [RYGMediaViewer showItem:item];
}

static id (*orig_commentCtxMenu)(id, SEL, id, id, CGPoint);
static id new_commentCtxMenu(id self, SEL _cmd, id cv, id indexPath, CGPoint point) {
    UIContextMenuConfiguration *config = orig_commentCtxMenu(self, _cmd, cv, indexPath, point);
    if (!config) return config;

    Ivar commentIvar = class_getInstanceVariable([self class], "_longPressedComment");
    id comment = commentIvar ? object_getIvar(self, commentIvar) : nil;
    if (!comment) return config;

    NSString *text = nil;
    @try { text = ((id(*)(id,SEL))objc_msgSend)(comment, @selector(text)); } @catch (__unused id e) {}

    NSString *gifId = nil;
    NSString *gifURL = rygGifURLFromComment(comment, &gifId);

    NSString *imageMediaId = nil;
    NSURL *imageURL = rygImageURLFromComment(comment, &imageMediaId);

    NSString *commentUsername = rygDirectUserResolverUsernameFromUser(rygCommentUser(comment));

    BOOL hasText = text.length > 0;
    BOOL hasGif = gifURL.length > 0;
    BOOL hasImage = imageURL != nil;
    if (!hasText && !hasGif && !hasImage) return config;

    id origProvider = [config valueForKey:@"actionProvider"];
    id<NSCopying> origIdent = [config valueForKey:@"identifier"];
    UIContextMenuContentPreviewProvider origPreview = [config valueForKey:@"previewProvider"];

    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIMenu *base = origProvider ? ((UIMenu *(^)(NSArray *))origProvider)(suggested)
                                    : [UIMenu menuWithChildren:suggested];
        NSMutableArray *extra = [NSMutableArray array];

        if (hasText && [RYGUtils getBoolPref:@"copy_comment"]) {
            [extra addObject:[UIAction actionWithTitle:RYGLocalized(@"Copy")
                                                 image:[RYGIcon imageNamed:@"doc.on.doc"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
                [UIPasteboard generalPasteboard].string = text;
                RYGNotifySuccess(RYG_NOTIF_COPY_COMMENT, RYGLocalized(@"Comment copied"), nil);
            }]];
        }

        BOOL gifDownloads = [RYGUtils getBoolPref:@"download_gif_comment"];
        BOOL gifFavorites = [RYGUtils getBoolPref:@"gif_favorites_enabled"] && gifId.length;
        if (hasGif && (gifDownloads || gifFavorites)) {
            NSURL *url = [NSURL URLWithString:gifURL];
            NSString *pageURL = gifId.length ? [NSString stringWithFormat:@"https://giphy.com/gifs/%@", gifId] : nil;
            NSMutableArray *gifChildren = [NSMutableArray array];

            if (gifDownloads) {
                [gifChildren addObject:[UIAction actionWithTitle:RYGLocalized(@"Download GIF")
                                                           image:[RYGIcon imageNamed:@"arrow.down.circle"]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    if (!url) return;
                    RYGGallerySaveMetadata *md = rygMetadataForComment(comment, gifId, gifURL, @"comment-gif");
                    rygDownloadCommentMedia(url, @"gif", RYGLocalized(@"Download GIF"), md);
                }]];
                [gifChildren addObject:[UIAction actionWithTitle:RYGLocalized(@"Copy GIF link")
                                                           image:[RYGIcon imageNamed:@"link"]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    if (!pageURL.length) return;
                    [UIPasteboard generalPasteboard].string = pageURL;
                    RYGNotifySuccess(RYG_NOTIF_COPY_GIF, RYGLocalized(@"GIF link copied"), nil);
                }]];
                [gifChildren addObject:[UIAction actionWithTitle:RYGLocalized(@"Expand")
                                                           image:[RYGIcon imageNamed:@"arrow.up.left.and.arrow.down.right"]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    rygPresentInViewer(url, commentUsername, YES);
                }]];
            }
            if (gifFavorites) {
                BOOL isFav = rygGifFavContains(gifId);
                [gifChildren addObject:[UIAction actionWithTitle:(isFav ? RYGLocalized(@"Unfavorite") : RYGLocalized(@"Favorite"))
                                                           image:[RYGIcon imageNamed:(isFav ? @"star.slash" : @"star")]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    BOOL nowFav = rygGifFavToggleId(gifId);
                    RYGNotifySuccess(RYG_NOTIF_GIF_FAVORITE,
                                     nowFav ? RYGLocalized(@"Added to favorites") : RYGLocalized(@"Removed from favorites"), nil);
                }]];
            }
            [extra addObject:[UIMenu menuWithTitle:RYGLocalized(@"GIF")
                                             image:[RYGIcon imageNamed:@"photo"]
                                        identifier:nil
                                           options:0
                                          children:gifChildren]];
        }

        if (hasImage && [RYGUtils getBoolPref:@"download_gif_comment"]) {
            NSString *imgURLStr = [imageURL absoluteString];
            UIAction *download = [UIAction actionWithTitle:RYGLocalized(@"Download image")
                                                     image:[RYGIcon imageNamed:@"arrow.down.circle"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction *_) {
                RYGGallerySaveMetadata *md = rygMetadataForComment(comment, imageMediaId, imgURLStr, @"comment-image");
                rygDownloadCommentMedia(imageURL, @"jpg", RYGLocalized(@"Download image"), md);
            }];
            UIAction *copy = [UIAction actionWithTitle:RYGLocalized(@"Copy image link")
                                                 image:[RYGIcon imageNamed:@"link"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
                if (!imgURLStr.length) return;
                [UIPasteboard generalPasteboard].string = imgURLStr;
                RYGNotifySuccess(RYG_NOTIF_COPY_GIF, RYGLocalized(@"Image link copied"), nil);
            }];
            UIAction *expand = [UIAction actionWithTitle:RYGLocalized(@"Expand")
                                                   image:[RYGIcon imageNamed:@"arrow.up.left.and.arrow.down.right"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction *_) {
                rygPresentInViewer(imageURL, commentUsername, NO);
            }];
            [extra addObject:[UIMenu menuWithTitle:RYGLocalized(@"Image")
                                             image:[RYGIcon imageNamed:@"photo"]
                                        identifier:nil
                                           options:0
                                          children:@[download, copy, expand]]];
        }

        if (!extra.count) return base;
        NSMutableArray *kids = [base.children mutableCopy] ?: [NSMutableArray array];
        NSUInteger insertIdx = kids.count > 0 ? kids.count - 1 : 0;
        UIMenu *ourMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil
                                        options:UIMenuOptionsDisplayInline children:extra];
        [kids insertObject:ourMenu atIndex:insertIdx];
        return [base menuByReplacingChildren:kids];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:origIdent
                                                    previewProvider:origPreview
                                                     actionProvider:wrapped];
}

__attribute__((constructor)) static void _commentActionsInit(void) {
    Class cls = NSClassFromString(@"IGCommentThreadViewController");
    if (!cls) return;
    SEL s = @selector(collectionView:contextMenuConfigurationForItemAtIndexPath:point:);
    if (class_getInstanceMethod(cls, s))
        MSHookMessageEx(cls, s, (IMP)new_commentCtxMenu, (IMP *)&orig_commentCtxMenu);
}
