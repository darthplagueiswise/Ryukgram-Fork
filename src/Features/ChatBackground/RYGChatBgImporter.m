#import "RYGChatBgImporter.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgEditor.h"
#import "../../Utils.h"
#import "../../RYGTempFiles.h"
#import "../../Gallery/RYGGalleryViewController.h"
#import "../../Gallery/RYGGalleryFile.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

@interface _RYGChatBgPickerDelegate : NSObject <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, copy) void (^completion)(NSString *_Nullable);
- (instancetype)initWithHost:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion;
@end

@implementation _RYGChatBgPickerDelegate

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

- (void)editImage:(UIImage *)image afterDismiss:(UIViewController *)picker {
	UIViewController *host = self.host;
	[picker dismissViewControllerAnimated:YES completion:^{
		[RYGChatBgEditor editImage:image from:host completion:^(NSString *rel) { [self finish:rel]; }];
	}];
}

// The provider's temp file is deleted when the block returns, so copy it out first.
- (void)loadFile:(NSItemProvider *)provider type:(NSString *)typeID afterDismiss:(UIViewController *)picker {
	[provider loadFileRepresentationForTypeIdentifier:typeID completionHandler:^(NSURL *url, __unused NSError *error) {
		NSURL *copy = nil;
		if (url) {
			NSString *ext = url.pathExtension.length ? url.pathExtension : @"mov";
			copy = [RYGTempFiles claimWithExt:ext ttl:300 tag:@"bgpick"];
			if (![NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:NULL]) { [RYGTempFiles releaseURL:copy]; copy = nil; }
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *host = self.host;
			[picker dismissViewControllerAnimated:YES completion:^{
				if (!copy) { [self finish:nil]; return; }
				[RYGChatBgEditor editFileURL:copy from:host completion:^(NSString *rel) {
					[RYGTempFiles releaseURL:copy];
					[self finish:rel];
				}];
			}];
		});
	}];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	PHPickerResult *result = results.firstObject;
	if (!result) { [self editImage:nil afterDismiss:picker]; return; }

	NSItemProvider *ip = result.itemProvider;
	if ([ip hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) {
		[self loadFile:ip type:UTTypeMovie.identifier afterDismiss:picker];
		return;
	}
	if ([ip hasItemConformingToTypeIdentifier:UTTypeGIF.identifier]) {
		[self loadFile:ip type:UTTypeGIF.identifier afterDismiss:picker];
		return;
	}

	[ip loadObjectOfClass:UIImage.class completionHandler:^(__kindof id<NSItemProviderReading> obj, __unused NSError *error) {
		UIImage *image = [obj isKindOfClass:UIImage.class] ? (UIImage *)obj : nil;
		dispatch_async(dispatch_get_main_queue(), ^{ [self editImage:image afterDismiss:picker]; });
	}];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	UIViewController *host = self.host;
	[picker dismissViewControllerAnimated:YES completion:^{
		[RYGChatBgEditor editFileURL:url from:host completion:^(NSString *rel) { [self finish:rel]; }];
	}];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
	[self finish:nil];
}

@end

@implementation RYGChatBgImporter

+ (_RYGChatBgPickerDelegate *)delegateForPicker:(UIViewController *)picker host:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	_RYGChatBgPickerDelegate *delegate = [[_RYGChatBgPickerDelegate alloc] initWithHost:host completion:completion];
	objc_setAssociatedObject(picker, @selector(delegateForPicker:host:completion:), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return delegate;
}

+ (void)presentPhotoLibraryFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	PHPickerConfiguration *config = [PHPickerConfiguration new];
	config.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
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
	picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image", @"public.movie", @"com.compuserve.gif"] inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop

	picker.allowsMultipleSelection = NO;
	picker.delegate = [self delegateForPicker:picker host:host completion:completion];

	[host presentViewController:picker animated:YES completion:nil];
}

+ (void)presentGalleryFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	[RYGGalleryViewController presentPickerWithMediaTypes:@[@(RYGGalleryMediaTypeImage), @(RYGGalleryMediaTypeVideo), @(RYGGalleryMediaTypeGIF)]
													title:RYGLocalized(@"Choose Media")
												   fromVC:host
											   completion:^(NSURL *pickedURL, __unused RYGGalleryFile *pickedFile) {
		[RYGChatBgEditor editFileURL:pickedURL from:host completion:completion];
	}];
}

+ (void)presentFrom:(UIViewController *)host completion:(void (^)(NSString *_Nullable))completion {
	if (!host) {
		if (completion) completion(nil);
		return;
	}

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Add Background")
																   message:nil
															preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Photo Library") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		[self presentPhotoLibraryFrom:host completion:completion];
	}]];

	if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) {
		[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"RyukGram Gallery") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[self presentGalleryFrom:host completion:completion];
		}]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Files") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		[self presentFilesFrom:host completion:completion];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
		if (completion) completion(nil);
	}]];

	sheet.popoverPresentationController.sourceView = host.view;
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1.0, 1.0);
	sheet.popoverPresentationController.permittedArrowDirections = 0;

	[host presentViewController:sheet animated:YES completion:nil];
}

@end