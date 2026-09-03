#import "RYGRepostSheet.h"
#import "../Utils.h"
#import "../RYGURLOpener.h"
#import "../PhotoAlbum.h"
#import "../UI/Notification/RYGNotificationCenter.h"
#import "../UI/Notification/RYGNotificationActions.h"
#import <Photos/Photos.h>

@implementation RYGRepostSheet

+ (void)repostWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL {
    NSURL *url = videoURL ?: photoURL;
    if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No media URL")]; return; }

    BOOL isVideo = (videoURL != nil);

    RYGNotificationHandle *handle = RYGNotifyProgress(RYG_NOTIF_REPOST,
                                                      RYGLocalized(@"Preparing repost…"),
                                                      nil);

    NSString *ext = [[url lastPathComponent] pathExtension];
    if (!ext.length) ext = isVideo ? @"mp4" : @"jpg";
    NSString *cleanName = [[RYGFileName stemForUsername:nil context:@"repost" date:nil index:0] stringByAppendingPathExtension:ext];
    NSURL *fileURL = [RYGTempFiles claimNamedFile:cleanName ttl:900 tag:@"repost"];

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (err || !loc || status >= 400) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [handle error:RYGLocalized(@"Download failed")];
            });
            return;
        }

        NSError *mv = nil;
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:loc toURL:fileURL error:&mv];
        unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] fileSize];
        if (mv || size == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [handle error:RYGLocalized(@"Save failed")];
            });
            return;
        }

        [self saveToPhotosAndOpenCreation:fileURL isVideo:isVideo handle:handle];
    }];
    [task resume];
}

+ (void)saveToPhotosAndOpenCreation:(NSURL *)fileURL isVideo:(BOOL)isVideo handle:(RYGNotificationHandle *)handle {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [handle error:RYGLocalized(@"Photos access denied")];
            });
            return;
        }

        __block NSString *localId = nil;

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *opts = [PHAssetResourceCreationOptions new];
            // Copy so the share-sheet fallback below still has a readable file.
            opts.shouldMoveFile = NO;
            [req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
                             fileURL:fileURL
                             options:opts];
            req.creationDate = [NSDate date];
            localId = req.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success || !localId.length) {
                    NSLog(@"[RyukGram][Repost] performChanges failed success=%d err=%@", success, error);
                    [handle error:RYGLocalized(@"Failed to save")];
                    return;
                }

                if ([RYGUtils getBoolPref:@"save_to_ryukgram_album"]) {
                    [RYGPhotoAlbum addAssetWithLocalIdentifier:localId completion:nil];
                }

                [handle success:RYGLocalized(@"Opening creator…")];

                NSString *urlStr = [NSString stringWithFormat:@"instagram://library?LocalIdentifier=%@",
                                    [localId stringByAddingPercentEncodingWithAllowedCharacters:
                                     [NSCharacterSet URLQueryAllowedCharacterSet]]];
                NSURL *igURL = [NSURL URLWithString:urlStr];
                if (igURL && [[UIApplication sharedApplication] canOpenURL:igURL]) {
                    [RYGURLOpener openURL:igURL];
                } else {
                    [RYGUtils showShareVC:fileURL];
                }
            });
        }];
    }];
}

@end
