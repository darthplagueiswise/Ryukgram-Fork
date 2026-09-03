#import "RYGCallVideoCapture.h"
#import <AVFoundation/AVFoundation.h>

@implementation RYGCallVideoCapture

+ (void)muxVideo:(NSURL *)videoURL audio:(NSURL *)audioURL videoOffset:(double)videoOffset audioOffset:(double)audioOffset toURL:(NSURL *)outURL completion:(void (^)(BOOL))completion {
	AVURLAsset *v = [AVURLAsset URLAssetWithURL:videoURL options:nil];
	AVURLAsset *a = [AVURLAsset URLAssetWithURL:audioURL options:nil];
	AVAssetTrack *vt = [v tracksWithMediaType:AVMediaTypeVideo].firstObject;
	AVAssetTrack *at = [a tracksWithMediaType:AVMediaTypeAudio].firstObject;
	if (!vt) { completion(NO); return; }

	AVMutableComposition *comp = [AVMutableComposition composition];
	@try {
		AVMutableCompositionTrack *cv = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
		CMTime vOff = videoOffset > 0.05 ? CMTimeMakeWithSeconds(videoOffset, 600) : kCMTimeZero;
		[cv insertTimeRange:CMTimeRangeMake(kCMTimeZero, v.duration) ofTrack:vt atTime:vOff error:nil];
		cv.preferredTransform = vt.preferredTransform;
		if (at) {
			// Full audio even if video is shorter — video ends, audio keeps going.
			AVMutableCompositionTrack *ca = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
			CMTime aOff = audioOffset > 0.05 ? CMTimeMakeWithSeconds(audioOffset, 600) : kCMTimeZero;
			[ca insertTimeRange:CMTimeRangeMake(kCMTimeZero, a.duration) ofTrack:at atTime:aOff error:nil];
		}
	} @catch (NSException *e) { NSLog(@"[RyukGram][CallVid] mux compose failed: %@", e); completion(NO); return; }

	[NSFileManager.defaultManager removeItemAtURL:outURL error:nil];
	AVAssetExportSession *ex = [[AVAssetExportSession alloc] initWithAsset:comp presetName:AVAssetExportPresetHighestQuality];
	if (!ex) { completion(NO); return; }
	ex.outputURL = outURL;
	ex.outputFileType = AVFileTypeMPEG4;
	ex.shouldOptimizeForNetworkUse = YES;
	[ex exportAsynchronouslyWithCompletionHandler:^{
		if (ex.status != AVAssetExportSessionStatusCompleted) NSLog(@"[RyukGram][CallVid] mux export failed (%ld): %@", (long)ex.status, ex.error);
		completion(ex.status == AVAssetExportSessionStatusCompleted);
	}];
}

@end
