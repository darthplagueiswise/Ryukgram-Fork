#import "SCIChatBgEditor.h"
#import "SCIChatBackgroundManager.h"
#import "../../UI/SCIImageEditor.h"
#import "../../UI/SCIVideoEditor.h"
#import "../../SCIFFmpeg.h"
#import "../../SCITempFiles.h"
#import "../../Utils.h"

static const NSTimeInterval kSCIChatBgMaxVideoSecs = 15.0;

@implementation SCIChatBgEditor

// Chat backgrounds fill the phone screen — frame video to the device's portrait ratio.
+ (CGSize)portraitAspect {
	CGSize s = UIScreen.mainScreen.bounds.size;
	return CGSizeMake(MIN(s.width, s.height), MAX(s.width, s.height));
}

+ (void)editImage:(UIImage *)image from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	if (!image || !host) { if (completion) completion(nil); return; }

	CGSize ar = [self portraitAspect];
	CGFloat fixed = ar.height > 0 ? ar.width / ar.height : 0;
	[SCIImageEditor presentForImage:image from:host fixedAspect:fixed onDone:^(UIImage *edited) {
		NSString *rel = edited ? [[SCIChatBackgroundManager shared] importImage:edited] : nil;
		if (edited && !rel) [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Couldn't import image")];
		if (completion) completion(rel);
	}];
}

+ (void)editVideoURL:(NSURL *)url from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	if (!url || !host) { if (completion) completion(nil); return; }

	CGSize ar = [self portraitAspect];
	[SCIVideoEditor presentForVideoURL:url from:host maxDuration:kSCIChatBgMaxVideoSecs aspectW:ar.width aspectH:ar.height onDone:^(NSURL *editedURL) {
		NSString *rel = editedURL ? [[SCIChatBackgroundManager shared] importFileURL:editedURL] : nil;
		if (editedURL) [SCITempFiles releaseURL:editedURL];
		if (editedURL && !rel) [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Couldn't import video")];
		if (completion) completion(rel);
	}];
}

+ (void)convertGIF:(NSURL *)gifURL completion:(void (^)(NSURL *))completion {
	if (![SCIFFmpeg isAvailable]) { completion(nil); return; }

	NSURL *out = [SCITempFiles claimWithExt:@"mp4" ttl:300 tag:@"gif2mp4"];
	NSString *cmd = [NSString stringWithFormat:
		@"-y -i \"%@\" -movflags +faststart -pix_fmt yuv420p -vf \"scale=trunc(iw/2)*2:trunc(ih/2)*2\" -c:v libx264 -preset veryfast -crf 22 \"%@\"",
		gifURL.path, out.path];

	[SCIFFmpeg executeCommand:cmd completion:^(BOOL success, __unused NSString *output) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!success) [SCITempFiles releaseURL:out];
			completion(success ? out : nil);
		});
	}];
}

+ (void)editFileURL:(NSURL *)url from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	if (!url || !host) { if (completion) completion(nil); return; }

	NSString *ext = url.pathExtension.lowercaseString;

	if ([ext isEqualToString:@"gif"]) {
		SCINotificationHandle *h = SCINotifyProgress(SCI_NOTIF_GENERIC, SCILocalized(@"Converting GIF"), nil);
		[self convertGIF:url completion:^(NSURL *mp4) {
			[h dismiss];
			if (!mp4) {
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Couldn't import video")];
				if (completion) completion(nil);
				return;
			}
			[self editVideoURL:mp4 from:host completion:^(NSString *rel) {
				[SCITempFiles releaseURL:mp4];
				if (completion) completion(rel);
			}];
		}];
		return;
	}

	if ([SCIChatBackgroundManager isVideoExtension:ext]) {
		[self editVideoURL:url from:host completion:completion];
		return;
	}

	BOOL scoped = [url startAccessingSecurityScopedResource];
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (scoped) [url stopAccessingSecurityScopedResource];
	UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
	[self editImage:image from:host completion:completion];
}

+ (void)reEditAsset:(NSString *)relPath from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	NSURL *url = [[SCIChatBackgroundManager shared] urlForRelativeAsset:relPath];
	if (!url) { if (completion) completion(nil); return; }

	if ([SCIChatBackgroundManager isVideoAsset:relPath]) {
		[self editVideoURL:url from:host completion:completion];
	} else {
		UIImage *image = [UIImage imageWithContentsOfFile:url.path];
		[self editImage:image from:host completion:completion];
	}
}

@end
