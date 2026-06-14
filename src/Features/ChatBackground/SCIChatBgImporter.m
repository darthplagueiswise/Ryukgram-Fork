#import "SCIChatBgImporter.h"
#import "SCIChatBackgroundManager.h"
#import "SCIChatBgCropController.h"
#import "../../Utils.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../../Gallery/SCIGalleryFile.h"
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static UIImage *SCIImageFromURL(NSURL *url) {
	if (!url) return nil;

	BOOL scoped = [url startAccessingSecurityScopedResource];
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (scoped) [url stopAccessingSecurityScopedResource];

	return data.length ? [UIImage imageWithData:data] : nil;
}

static void SCIImportCropped(UIViewController *host, UIImage *image, void (^completion)(NSString *_Nullable)) {
	if (!host || !image) {
		if (completion) completion(nil);
		return;
	}

	SCIChatBgCropController *crop = [SCIChatBgCropController new];
	crop.sourceImage = image;
	crop.onConfirm = ^(UIImage *cropped) {
		NSString *rel = cropped ? [[SCIChatBackgroundManager shared] importImage:cropped] : nil;
		if (cropped && !rel) [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Couldn't import image")];
		if (completion) completion(rel);
	};

	[host presentViewController:crop animated:YES completion:nil];
}

@interface _SCIChatBgPickerDelegate : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, copy) void (^completion)(NSString *_Nullable);
- (instancetype)initWithHost:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion;
@end

@implementation _SCIChatBgPickerDelegate

- (instancetype)initWithHost:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	if ((self = [super init])) {
		_host = host;
		_completion = completion;
	}
	return self;
}

- (void)finish:(NSString *)asset {
	void (^cb)(NSString *) = self.completion;
	self.completion = nil;
	if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(asset); });
}

- (void)importImage:(UIImage *)image afterDismiss:(UIViewController *)picker {
	UIViewController *host = self.host;

	[picker dismissViewControllerAnimated:YES completion:^{
		if (!image) {
			[self finish:nil];
			return;
		}

		SCIImportCropped(host, image, ^(NSString *rel) {
			[self finish:rel];
		});
	}];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	PHPickerResult *result = results.firstObject;
	if (!result) {
		[self importImage:nil afterDismiss:picker];
		return;
	}

	[result.itemProvider loadObjectOfClass:UIImage.class completionHandler:^(__kindof id<NSItemProviderReading> obj, __unused NSError *error) {
		UIImage *image = [obj isKindOfClass:UIImage.class] ? (UIImage *)obj : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self importImage:image afterDismiss:picker];
		});
	}];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	UIImage *image = SCIImageFromURL(urls.firstObject);
	[self importImage:image afterDismiss:picker];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
	[self finish:nil];
}

@end

@implementation SCIChatBgImporter

+ (_SCIChatBgPickerDelegate *)delegateForPicker:(UIViewController *)picker host:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	_SCIChatBgPickerDelegate *delegate = [[_SCIChatBgPickerDelegate alloc] initWithHost:host completion:completion];
	objc_setAssociatedObject(picker, @selector(delegateForPicker:host:completion:), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return delegate;
}

+ (void)presentPhotoLibraryFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	PHPickerConfiguration *config = [PHPickerConfiguration new];
	config.filter = PHPickerFilter.imagesFilter;
	config.selectionLimit = 1;

	PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
	picker.delegate = [self delegateForPicker:picker host:host completion:completion];

	[host presentViewController:picker animated:YES completion:nil];
}

+ (void)presentFilesFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	UIDocumentPickerViewController *picker = nil;

	// initForOpeningContentTypes: never fires its delegate on sideload — only the deprecated init works.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image"] inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop

	picker.allowsMultipleSelection = NO;
	picker.delegate = [self delegateForPicker:picker host:host completion:completion];

	[host presentViewController:picker animated:YES completion:nil];
}

+ (void)presentGalleryFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	[SCIGalleryViewController presentPickerWithMediaTypes:@[@(SCIGalleryMediaTypeImage)]
													title:SCILocalized(@"Choose Image")
												   fromVC:host
											   completion:^(NSURL *pickedURL, __unused SCIGalleryFile *pickedFile) {
		UIImage *image = SCIImageFromURL(pickedURL);
		SCIImportCropped(host, image, completion);
	}];
}

+ (void)presentFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	if (!host) {
		if (completion) completion(nil);
		return;
	}

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add Background")
																   message:nil
															preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Photo Library") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		[self presentPhotoLibraryFrom:host completion:completion];
	}]];

	if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
		[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"RyukGram Gallery") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[self presentGalleryFrom:host completion:completion];
		}]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Files") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		[self presentFilesFrom:host completion:completion];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
		if (completion) completion(nil);
	}]];

	sheet.popoverPresentationController.sourceView = host.view;
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1.0, 1.0);
	sheet.popoverPresentationController.permittedArrowDirections = 0;

	[host presentViewController:sheet animated:YES completion:nil];
}

@end
