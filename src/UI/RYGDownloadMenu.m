#import "RYGDownloadMenu.h"
#import "../Utils.h"
#import "../InstagramHeaders.h"
#import "../Downloader/Download.h"
#import "../Gallery/RYGGalleryFile.h"
#import <Photos/Photos.h>

@implementation RYGDownloadMenu

#pragma mark - Helpers

+ (BOOL)galleryEnabled {
    return [RYGUtils getBoolPref:@"ryg_gallery_enabled"];
}

+ (void)savePhotosLocal:(NSURL *)fileURL hudLabel:(NSString *)hudLabel metadata:(RYGGallerySaveMetadata *)metadata {
    RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:NO];
    dl.pendingGallerySaveMetadata = metadata;
    [dl saveLocalFileURL:fileURL hudLabel:hudLabel];
}

+ (void)saveGalleryLocal:(NSURL *)fileURL hudLabel:(NSString *)hudLabel metadata:(RYGGallerySaveMetadata *)metadata {
    RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:saveToGallery showProgress:NO];
    dl.pendingGallerySaveMetadata = metadata;
    [dl saveLocalFileURL:fileURL hudLabel:hudLabel];
}

#pragma mark - Remote

+ (void)downloadRemote:(NSURL *)url
         fileExtension:(NSString *)ext
              hudLabel:(NSString *)hudLabel
              metadata:(RYGGallerySaveMetadata *)metadata
                action:(DownloadAction)action {
    RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:YES];
    dl.pendingGallerySaveMetadata = metadata;
    [dl downloadFileWithURL:url fileExtension:(ext.length ? ext : @"bin") hudLabel:hudLabel];
}

#pragma mark - Public

+ (void)downloadURL:(NSURL *)url
      fileExtension:(NSString *)fileExtension
           hudLabel:(NSString *)hudLabel
           metadata:(RYGGallerySaveMetadata *)metadata
        forceTarget:(NSInteger)forceTarget {
    DownloadAction action = saveToPhotos;
    if (forceTarget == 1) action = saveToGallery;
    else if (forceTarget == 2) action = share;
    [self downloadRemote:url fileExtension:fileExtension hudLabel:hudLabel metadata:metadata action:action];
}

+ (NSArray<UIAlertAction *> *)alertActionsForURL:(NSURL *)url
                                            mode:(RYGDownloadMenuMode)mode
                                   fileExtension:(NSString *)fileExtension
                                        hudLabel:(NSString *)hudLabel
                                        metadata:(RYGGallerySaveMetadata *)metadata
                                         isAudio:(BOOL)isAudio
                                     titlePrefix:(NSString *)titlePrefix {
    NSMutableArray *actions = [NSMutableArray array];
    NSString *prefix = titlePrefix.length ? titlePrefix : RYGLocalized(@"Download");

    if (!isAudio) {
        [actions addObject:[UIAlertAction actionWithTitle:prefix
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *_) {
            if (mode == RYGDownloadMenuModeLocalFile) {
                [self savePhotosLocal:url hudLabel:hudLabel metadata:metadata];
            } else {
                [self downloadRemote:url fileExtension:fileExtension hudLabel:hudLabel metadata:metadata action:saveToPhotos];
            }
        }]];
    }

    NSString *galleryTitle = [NSString stringWithFormat:@"%@ %@", prefix, RYGLocalized(@"to Gallery")];
    [actions addObject:[UIAlertAction actionWithTitle:galleryTitle
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *_) {
        if (mode == RYGDownloadMenuModeLocalFile) {
            [self saveGalleryLocal:url hudLabel:hudLabel metadata:metadata];
        } else {
            [self downloadRemote:url fileExtension:fileExtension hudLabel:hudLabel metadata:metadata action:saveToGallery];
        }
    }]];

    if (isAudio) {
        [actions addObject:[UIAlertAction actionWithTitle:RYGLocalized(@"Share")
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *_) {
            if (mode == RYGDownloadMenuModeLocalFile) {
                [RYGUtils showShareVC:url];
            } else {
                [self downloadRemote:url fileExtension:fileExtension hudLabel:hudLabel metadata:metadata action:share];
            }
        }]];
    }

    return actions;
}

+ (void)presentForURL:(NSURL *)url
                 mode:(RYGDownloadMenuMode)mode
        fileExtension:(NSString *)fileExtension
             hudLabel:(NSString *)hudLabel
             metadata:(RYGGallerySaveMetadata *)metadata
              isAudio:(BOOL)isAudio
               fromVC:(UIViewController *)fromVC {
    BOOL galleryOn = [self galleryEnabled];

    // Gallery off → no submenu. Photos for non-audio (mirror branch in
    // RYGDownloadDelegate still logs to gallery when `gallery_save_mode` is
    // mirror), share fallback for audio.
    if (!galleryOn) {
        if (isAudio) {
            if (mode == RYGDownloadMenuModeLocalFile) [RYGUtils showShareVC:url];
            else [self downloadRemote:url fileExtension:fileExtension hudLabel:hudLabel metadata:metadata action:share];
        } else {
            if (mode == RYGDownloadMenuModeLocalFile) [self savePhotosLocal:url hudLabel:hudLabel metadata:metadata];
            else [self downloadRemote:url fileExtension:fileExtension hudLabel:hudLabel metadata:metadata action:saveToPhotos];
        }
        return;
    }

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:hudLabel ?: RYGLocalized(@"Download")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (UIAlertAction *a in [self alertActionsForURL:url
                                                  mode:mode
                                         fileExtension:fileExtension
                                              hudLabel:hudLabel
                                              metadata:metadata
                                               isAudio:isAudio
                                           titlePrefix:RYGLocalized(@"Download")]) {
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [RYGUtils presentAlertInOwnWindow:sheet];
}

@end
