#import "RYGGalleryImporter.h"
#import "RYGGalleryFile.h"
#import "RYGGallerySaveMetadata.h"
#import "../Utils.h"
#import "../RYGTempFiles.h"
#import "../UI/Notification/RYGNotificationCenter.h"
#import "../UI/Notification/RYGNotificationActions.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

@interface _RYGGalleryImportPicker : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, copy, nullable) NSString *folderPath;
@property (nonatomic, copy, nullable) void (^completion)(NSUInteger added);
@end

@implementation _RYGGalleryImportPicker

- (void)finish:(NSUInteger)added {
	void (^cb)(NSUInteger) = self.completion;
	self.completion = nil;
	if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(added); });
}

// Saves a batch of local file URLs into the gallery on the main (view) context.
- (void)saveURLs:(NSArray<NSURL *> *)urls {
	if (urls.count == 0) { [self finish:0]; return; }

	dispatch_async(dispatch_get_main_queue(), ^{
		RYGNotificationHandle *handle = urls.count > 1
			? RYGNotifyProgress(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Importing…"), nil)
			: nil;

		NSUInteger added = 0;
		for (NSUInteger i = 0; i < urls.count; i++) {
			NSURL *url = urls[i];
			RYGGalleryMediaType type = RYGGalleryMediaTypeForExtension(url.pathExtension);

			RYGGallerySaveMetadata *meta = [RYGGallerySaveMetadata new];
			meta.source = RYGGallerySourceImported;
			meta.skipDedup = YES;

			NSError *saveErr = nil;
			if ([RYGGalleryFile saveFileToGallery:url source:RYGGallerySourceImported mediaType:type
									   folderPath:self.folderPath metadata:meta error:&saveErr]) {
				added++;
			} else {
				NSLog(@"[RyukGram][Gallery] import save failed (%@): %@", url.lastPathComponent, saveErr);
			}
			if (handle) [handle setProgress:(float)(i + 1) / (float)urls.count];
		}

		if (handle) {
			if (added) [handle success:[NSString stringWithFormat:RYGLocalized(@"Added %lu"), (unsigned long)added]];
			else [handle error:RYGLocalized(@"Nothing imported")];
		} else if (added) {
			RYGNotifySuccess(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Saved to Gallery"), nil);
		} else {
			RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Import failed"), nil);
		}

		[self finish:added];
	});
}

#pragma mark - Photos

- (NSString *)typeIdentifierForProvider:(NSItemProvider *)ip {
	if ([ip hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) return UTTypeMovie.identifier;
	if ([ip hasItemConformingToTypeIdentifier:UTTypeGIF.identifier]) return UTTypeGIF.identifier;
	if ([ip hasItemConformingToTypeIdentifier:UTTypeImage.identifier]) return UTTypeImage.identifier;
	return nil;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (results.count == 0) { [self finish:0]; return; }

	NSMutableArray<NSURL *> *collected = [NSMutableArray array];
	dispatch_group_t group = dispatch_group_create();

	for (PHPickerResult *result in results) {
		NSItemProvider *ip = result.itemProvider;
		NSString *typeID = [self typeIdentifierForProvider:ip];
		if (!typeID) continue;

		dispatch_group_enter(group);
		// The provider's temp file dies when the block returns — copy it out first.
		[ip loadFileRepresentationForTypeIdentifier:typeID completionHandler:^(NSURL *url, __unused NSError *error) {
			if (url) {
				NSString *ext = url.pathExtension.length ? url.pathExtension : @"dat";
				NSURL *copy = [RYGTempFiles claimWithExt:ext ttl:300 tag:@"import"];
				if ([NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:NULL]) {
					@synchronized (collected) { [collected addObject:copy]; }
				} else {
					[RYGTempFiles releaseURL:copy];
				}
			}
			dispatch_group_leave(group);
		}];
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		// Don't release here — saveURLs saves asynchronously; the ttl:300 claims auto-reap.
		[self saveURLs:collected];
	});
}

#pragma mark - Files

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	[picker dismissViewControllerAnimated:YES completion:nil];
	[self saveURLs:urls]; // import-mode URLs are local copies; saveFileToGallery copies again into the gallery
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
	[self finish:0];
}

@end

@implementation RYGGalleryImporter

+ (_RYGGalleryImportPicker *)pinDelegate:(_RYGGalleryImportPicker *)delegate toPicker:(UIViewController *)picker {
	objc_setAssociatedObject(picker, _cmd, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return delegate;
}

+ (_RYGGalleryImportPicker *)delegateForHost:(UIViewController *)host
								  folderPath:(NSString *)folderPath
								  completion:(void (^)(NSUInteger))completion {
	_RYGGalleryImportPicker *d = [_RYGGalleryImportPicker new];
	d.host = host;
	d.folderPath = folderPath;
	d.completion = completion;
	return d;
}

+ (void)presentPhotosFrom:(UIViewController *)host folderPath:(NSString *)folderPath completion:(void (^)(NSUInteger))completion {
	PHPickerConfiguration *config = [PHPickerConfiguration new];
	config.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
	config.selectionLimit = 0;

	PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
	picker.delegate = [self pinDelegate:[self delegateForHost:host folderPath:folderPath completion:completion] toPicker:picker];
	[host presentViewController:picker animated:YES completion:nil];
}

+ (void)presentFilesFrom:(UIViewController *)host folderPath:(NSString *)folderPath completion:(void (^)(NSUInteger))completion {
	UIDocumentPickerViewController *picker = nil;
	// initForOpeningContentTypes: never fires its delegate on sideload — only the deprecated init works.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image", @"public.movie", @"public.audio", @"com.compuserve.gif"]
																	inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
	picker.allowsMultipleSelection = YES;
	picker.delegate = [self pinDelegate:[self delegateForHost:host folderPath:folderPath completion:completion] toPicker:picker];
	[host presentViewController:picker animated:YES completion:nil];
}

+ (void)presentImportFrom:(UIViewController *)host folderPath:(NSString *)folderPath completion:(void (^)(NSUInteger))completion {
	if (!host) { if (completion) completion(0); return; }

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Import to Gallery")
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Photo Library") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		[self presentPhotosFrom:host folderPath:folderPath completion:completion];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Files") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		[self presentFilesFrom:host folderPath:folderPath completion:completion];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
		if (completion) completion(0);
	}]];

	sheet.popoverPresentationController.sourceView = host.view;
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1.0, 1.0);
	sheet.popoverPresentationController.permittedArrowDirections = 0;

	[host presentViewController:sheet animated:YES completion:nil];
}

@end
