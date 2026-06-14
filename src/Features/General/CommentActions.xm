// Comment long-press menu extras: copy text + GIF / image media submenu.
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../UI/SCIIcon.h"
#import "../../UI/SCIDownloadMenu.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../StoriesAndMessages/SCIDirectUserResolver.h"
#import "GifFavorites.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static DownloadAction sciGifDownloadAction(void) {
    NSString *method = [SCIUtils getStringPref:@"dw_save_action"];
    return [method isEqualToString:@"photos"] ? saveToPhotos : share;
}

static id sciCommentUser(id comment) {
    for (NSString *key in @[@"user", @"author", @"commenter"]) {
        @try {
            id u = [comment valueForKey:key];
            if (u) return u;
        } @catch (__unused id e) {}
    }
    return nil;
}

static SCIGallerySaveMetadata *sciMetadataForComment(id comment, NSString *mediaPK,
                                                    NSString *urlStr, NSString *contextLabel) {
    id user = sciCommentUser(comment);
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.source = (int16_t)SCIGallerySourceComments;
    if (mediaPK.length) md.sourceMediaPK = mediaPK;
    if (urlStr.length) md.sourceMediaURLString = urlStr;
    md.sourceUsername = sciDirectUserResolverUsernameFromUser(user);
    md.sourceUserPK = sciDirectUserResolverPKFromUser(user);
    md.sourceProfileURLString = sciDirectUserResolverProfilePicURLStringFromUser(user);
    [SCIMediaActions setCurrentFilenameStem:
        [SCIMediaActions filenameStemForUsername:md.sourceUsername contextLabel:contextLabel]];
    return md;
}

static void sciDownloadCommentMedia(NSURL *url, NSString *ext, NSString *hudLabel,
                                    SCIGallerySaveMetadata *md) {
    if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
        [SCIDownloadMenu presentForURL:url
                                  mode:SCIDownloadMenuModeRemoteURL
                         fileExtension:ext
                              hudLabel:hudLabel
                              metadata:md
                               isAudio:NO
                                fromVC:nil];
    } else {
        [SCIDownloadMenu downloadURL:url
                       fileExtension:ext
                            hudLabel:nil
                            metadata:md
                         forceTarget:(sciGifDownloadAction() == saveToPhotos ? 0 : 2)];
    }
}

static NSString *sciGifURLFromComment(id comment, NSString **outGifId) {
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
static NSURL *sciImageURLFromComment(id comment, NSString **outMediaId) {
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

static void sciPresentInViewer(NSURL *url, NSString *username, BOOL animated) {
    if (!url) return;
    SCIMediaViewerItem *item = animated
        ? [SCIMediaViewerItem itemWithAnimatedImageURL:url caption:nil]
        : [SCIMediaViewerItem itemWithVideoURL:nil photoURL:url caption:nil];
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.source = (int16_t)SCIGallerySourceComments;
    md.sourceUsername = username;
    md.sourceMediaURLString = [url absoluteString];
    item.metadata = md;
    [SCIMediaViewer showItem:item];
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
    NSString *gifURL = sciGifURLFromComment(comment, &gifId);

    NSString *imageMediaId = nil;
    NSURL *imageURL = sciImageURLFromComment(comment, &imageMediaId);

    NSString *commentUsername = sciDirectUserResolverUsernameFromUser(sciCommentUser(comment));

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

        if (hasText && [SCIUtils getBoolPref:@"copy_comment"]) {
            [extra addObject:[UIAction actionWithTitle:SCILocalized(@"Copy")
                                                 image:[SCIIcon imageNamed:@"doc.on.doc"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
                [UIPasteboard generalPasteboard].string = text;
                SCINotifySuccess(SCI_NOTIF_COPY_COMMENT, SCILocalized(@"Comment copied"), nil);
            }]];
        }

        BOOL gifDownloads = [SCIUtils getBoolPref:@"download_gif_comment"];
        BOOL gifFavorites = [SCIUtils getBoolPref:@"gif_favorites_enabled"] && gifId.length;
        if (hasGif && (gifDownloads || gifFavorites)) {
            NSURL *url = [NSURL URLWithString:gifURL];
            NSString *pageURL = gifId.length ? [NSString stringWithFormat:@"https://giphy.com/gifs/%@", gifId] : nil;
            NSMutableArray *gifChildren = [NSMutableArray array];

            if (gifDownloads) {
                [gifChildren addObject:[UIAction actionWithTitle:SCILocalized(@"Download GIF")
                                                           image:[SCIIcon imageNamed:@"arrow.down.circle"]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    if (!url) return;
                    SCIGallerySaveMetadata *md = sciMetadataForComment(comment, gifId, gifURL, @"comment-gif");
                    sciDownloadCommentMedia(url, @"gif", SCILocalized(@"Download GIF"), md);
                }]];
                [gifChildren addObject:[UIAction actionWithTitle:SCILocalized(@"Copy GIF link")
                                                           image:[SCIIcon imageNamed:@"link"]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    if (!pageURL.length) return;
                    [UIPasteboard generalPasteboard].string = pageURL;
                    SCINotifySuccess(SCI_NOTIF_COPY_GIF, SCILocalized(@"GIF link copied"), nil);
                }]];
                [gifChildren addObject:[UIAction actionWithTitle:SCILocalized(@"Expand")
                                                           image:[SCIIcon imageNamed:@"arrow.up.left.and.arrow.down.right"]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    sciPresentInViewer(url, commentUsername, YES);
                }]];
            }
            if (gifFavorites) {
                BOOL isFav = sciGifFavContains(gifId);
                [gifChildren addObject:[UIAction actionWithTitle:(isFav ? SCILocalized(@"Unfavorite") : SCILocalized(@"Favorite"))
                                                           image:[SCIIcon imageNamed:(isFav ? @"star.slash" : @"star")]
                                                      identifier:nil
                                                         handler:^(__kindof UIAction *_) {
                    BOOL nowFav = sciGifFavToggleId(gifId);
                    SCINotifySuccess(SCI_NOTIF_GIF_FAVORITE,
                                     nowFav ? SCILocalized(@"Added to favorites") : SCILocalized(@"Removed from favorites"), nil);
                }]];
            }
            [extra addObject:[UIMenu menuWithTitle:SCILocalized(@"GIF")
                                             image:[SCIIcon imageNamed:@"photo"]
                                        identifier:nil
                                           options:0
                                          children:gifChildren]];
        }

        if (hasImage && [SCIUtils getBoolPref:@"download_gif_comment"]) {
            NSString *imgURLStr = [imageURL absoluteString];
            UIAction *download = [UIAction actionWithTitle:SCILocalized(@"Download image")
                                                     image:[SCIIcon imageNamed:@"arrow.down.circle"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction *_) {
                SCIGallerySaveMetadata *md = sciMetadataForComment(comment, imageMediaId, imgURLStr, @"comment-image");
                sciDownloadCommentMedia(imageURL, @"jpg", SCILocalized(@"Download image"), md);
            }];
            UIAction *copy = [UIAction actionWithTitle:SCILocalized(@"Copy image link")
                                                 image:[SCIIcon imageNamed:@"link"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
                if (!imgURLStr.length) return;
                [UIPasteboard generalPasteboard].string = imgURLStr;
                SCINotifySuccess(SCI_NOTIF_COPY_GIF, SCILocalized(@"Image link copied"), nil);
            }];
            UIAction *expand = [UIAction actionWithTitle:SCILocalized(@"Expand")
                                                   image:[SCIIcon imageNamed:@"arrow.up.left.and.arrow.down.right"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction *_) {
                sciPresentInViewer(imageURL, commentUsername, NO);
            }];
            [extra addObject:[UIMenu menuWithTitle:SCILocalized(@"Image")
                                             image:[SCIIcon imageNamed:@"photo"]
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
