#import "RYGChatBgEditor.h"
#import "RYGChatBackgroundManager.h"
#import "../../UI/RYGImageEditor.h"
#import "../../UI/RYGVideoEditor.h"
#import "../../RYGFFmpeg.h"
#import "../../RYGTempFiles.h"
#import "../../Utils.h"

static const NSTimeInterval kRYGChatBgMaxVideoSecs = 15.0;

@implementation RYGChatBgEditor

// Chat backgrounds fill the phone screen — frame video to the device's portrait ratio.
+ (CGSize)portraitAspect {
	CGSize s = UIScreen.mainScreen.bounds.size;
	return CGSizeMake(MIN(s.width, s.height), MAX(s.width, s.height));
}

+ (void)editImage:(UIImage *)image from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	if (!image || !host) { if (completion) completion(nil); return; }

	CGSize ar = [self portraitAspect];
	CGFloat fixed = ar.height > 0 ? ar.width / ar.height : 0;
	[RYGImageEditor presentForImage:image from:host fixedAspect:fixed onDone:^(UIImage *edited) {
		NSString *rel = edited ? [[RYGChatBackgroundManager shared] importImage:edited] : nil;
		if (edited && !rel) [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Couldn't import image")];
		if (completion) completion(rel);
	}];
}

+ (void)editVideoURL:(NSURL *)url from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	if (!url || !host) { if (completion) completion(nil); return; }

	CGSize ar = [self portraitAspect];
	[RYGVideoEditor presentForVideoURL:url from:host maxDuration:kRYGChatBgMaxVideoSecs aspectW:ar.width aspectH:ar.height onDone:^(NSURL *editedURL) {
		NSString *rel = editedURL ? [[RYGChatBackgroundManager shared] importFileURL:editedURL] : nil;
		if (editedURL) [RYGTempFiles releaseURL:editedURL];
		if (editedURL && !rel) [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Couldn't import video")];
		if (completion) completion(rel);
	}];
}

+ (void)convertGIF:(NSURL *)gifURL completion:(void (^)(NSURL *))completion {
	if (![RYGFFmpeg isAvailable]) { completion(nil); return; }

	NSURL *out = [RYGTempFiles claimWithExt:@"mp4" ttl:300 tag:@"gif2mp4"];
	NSString *cmd = [NSString stringWithFormat:
		@"-y -i \"%@\" -movflags +faststart -pix_fmt yuv420p -vf \"scale=trunc(iw/2)*2:trunc(ih/2)*2\" -c:v libx264 -preset veryfast -crf 22 \"%@\"",
		gifURL.path, out.path];

	[RYGFFmpeg executeCommand:cmd completion:^(BOOL success, __unused NSString *output) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!success) [RYGTempFiles releaseURL:out];
			completion(success ? out : nil);
		});
	}];
}

+ (void)editFileURL:(NSURL *)url from:(UIViewController *)host completion:(void (^)(NSString *))completion {
	if (!url || !host) { if (completion) completion(nil); return; }

	NSString *ext = url.pathExtension.lowercaseString;

	if ([ext isEqualToString:@"gif"]) {
		RYGNotificationHandle *h = RYGNotifyProgress(RYG_NOTIF_GENERIC, RYGLocalized(@"Converting GIF"), nil);
		[self convertGIF:url completion:^(NSURL *mp4) {
			[h dismiss];
			if (!mp4) {
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Couldn't import video")];
				if (completion) completion(nil);
				return;
			}
			[self editVideoURL:mp4 from:host completion:^(NSString *rel) {
				[RYGTempFiles releaseURL:mp4];
				if (completion) completion(rel);
			}];
		}];
		return;
	}

	if ([RYGChatBackgroundManager isVideoExtension:ext]) {
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
	NSURL *url = [[RYGChatBackgroundManager shared] urlForRelativeAsset:relPath];
	if (!url) { if (completion) completion(nil); return; }

	if ([RYGChatBackgroundManager isVideoAsset:relPath]) {
		[self editVideoURL:url from:host completion:completion];
	} else {
		UIImage *image = [UIImage imageWithContentsOfFile:url.path];
		[self editImage:image from:host completion:completion];
	}
}

@end
