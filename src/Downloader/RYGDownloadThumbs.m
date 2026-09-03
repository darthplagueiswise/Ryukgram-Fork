#import "RYGDownloadThumbs.h"
#import "RYGDownloadCenter.h"
#import "RYGDownloadHistory.h"
#import <AVFoundation/AVFoundation.h>

NSString *const RYGDownloadThumbDidLoadNotification = @"RYGDownloadThumbDidLoadNotification";

static CGFloat const kThumbSide = 120;

@implementation RYGDownloadThumbs

+ (NSString *)storageDirectory {
	NSString *dir = [[RYGDownloadHistory storageDirectory] stringByAppendingPathComponent:@"thumbs"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

+ (NSString *)pathForJobID:(NSString *)jobID {
	return [[self storageDirectory] stringByAppendingPathComponent:[jobID stringByAppendingPathExtension:@"jpg"]];
}

+ (NSCache<NSString *, UIImage *> *)cache {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 150; });
	return cache;
}

+ (dispatch_queue_t)queue {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.downloadthumbs", DISPATCH_QUEUE_SERIAL); });
	return q;
}

#pragma mark - Read

+ (UIImage *)thumbForJobID:(NSString *)jobID {
	if (!jobID.length) return nil;
	UIImage *hit = [[self cache] objectForKey:jobID];
	if (hit) return hit;
	UIImage *onDisk = [UIImage imageWithContentsOfFile:[self pathForJobID:jobID]];
	if (onDisk) [[self cache] setObject:onDisk forKey:jobID];
	return onDisk;
}

#pragma mark - Capture

+ (void)captureForJob:(RYGDownloadJob *)job {
	RYGDownloadMediaKind kind = job.mediaKind;
	if (kind != RYGDownloadMediaKindVideo && kind != RYGDownloadMediaKindPhoto) return;

	NSURL *src = job.resultFileURL;
	if (!src.isFileURL || ![NSFileManager.defaultManager fileExistsAtPath:src.path]) return;

	NSString *jobID = job.jobID;
	if ([NSFileManager.defaultManager fileExistsAtPath:[self pathForJobID:jobID]]) return;

	// Hardlink first: Photos moves the original away before the render runs.
	NSString *staged = [[self storageDirectory] stringByAppendingPathComponent:
	                    [NSString stringWithFormat:@"%@.src.%@", jobID, src.pathExtension ?: @"bin"]];
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm removeItemAtPath:staged error:nil];
	if (![fm linkItemAtPath:src.path toPath:staged error:nil]
	    && ![fm copyItemAtPath:src.path toPath:staged error:nil]) return;

	dispatch_async([self queue], ^{
		UIImage *thumb = (kind == RYGDownloadMediaKindVideo)
			? [self videoThumbAtPath:staged] : [self photoThumbAtPath:staged];
		[NSFileManager.defaultManager removeItemAtPath:staged error:nil];
		if (!thumb) return;

		NSData *jpeg = UIImageJPEGRepresentation(thumb, 0.8);
		if (jpeg) [jpeg writeToFile:[self pathForJobID:jobID] atomically:YES];
		dispatch_async(dispatch_get_main_queue(), ^{
			[[self cache] setObject:thumb forKey:jobID];
			[[NSNotificationCenter defaultCenter] postNotificationName:RYGDownloadThumbDidLoadNotification object:jobID];
		});
	});
}

+ (UIImage *)photoThumbAtPath:(NSString *)path {
	UIImage *full = [UIImage imageWithContentsOfFile:path];
	return full ? [self square:full] : nil;
}

+ (UIImage *)videoThumbAtPath:(NSString *)path {
	AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:path]];
	AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
	gen.appliesPreferredTrackTransform = YES;
	gen.maximumSize = CGSizeMake(kThumbSide * 2, kThumbSide * 2);
	// Short clips and some mux output have no frame at 0.2s.
	CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.2, 600) actualTime:NULL error:nil];
	if (!cg) cg = [gen copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
	if (!cg) return nil;
	UIImage *img = [UIImage imageWithCGImage:cg];
	CGImageRelease(cg);
	return [self square:img];
}

+ (UIImage *)square:(UIImage *)image {
	CGSize size = image.size;
	if (size.width < 1 || size.height < 1) return nil;
	CGFloat scale = MAX(kThumbSide / size.width, kThumbSide / size.height);
	CGSize scaled = CGSizeMake(round(size.width * scale), round(size.height * scale));

	UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
	fmt.opaque = YES;
	fmt.scale = 1;
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kThumbSide, kThumbSide) format:fmt];
	return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		[[UIColor blackColor] setFill];
		[ctx fillRect:CGRectMake(0, 0, kThumbSide, kThumbSide)];
		[image drawInRect:CGRectMake((kThumbSide - scaled.width) / 2.0, (kThumbSide - scaled.height) / 2.0,
		                             scaled.width, scaled.height)];
	}];
}

#pragma mark - Lifetime

+ (void)pruneKeepingJobIDs:(NSSet<NSString *> *)jobIDs {
	dispatch_async([self queue], ^{
		NSString *dir = [self storageDirectory];
		NSFileManager *fm = NSFileManager.defaultManager;
		for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
			NSString *jobID = [name componentsSeparatedByString:@"."].firstObject;
			if (jobID.length && [jobIDs containsObject:jobID]) continue;
			[fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
			if (jobID) {
				dispatch_async(dispatch_get_main_queue(), ^{ [[self cache] removeObjectForKey:jobID]; });
			}
		}
	});
}

+ (void)removeAll {
	dispatch_async([self queue], ^{
		[NSFileManager.defaultManager removeItemAtPath:[self storageDirectory] error:nil];
		dispatch_async(dispatch_get_main_queue(), ^{ [[self cache] removeAllObjects]; });
	});
}

@end
