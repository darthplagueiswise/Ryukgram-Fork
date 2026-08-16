#import "PhotoAlbum.h"
#import "Utils.h"

@interface RYGPhotoAlbumWatcher : NSObject <PHPhotoLibraryChangeObserver>
@property (nonatomic, strong) PHFetchResult<PHAsset *> *baseline;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@end

static RYGPhotoAlbumWatcher *rygActiveWatcher = nil;

@implementation RYGPhotoAlbum

+ (NSString *)albumName {
	NSString *name = [[RYGUtils getStringPref:@"gallery_album_name"]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return name.length ? name : @"RyukGram";
}

+ (void)fetchOrCreateAlbumWithCompletion:(void (^)(PHAssetCollection *, NSError *))completion {
	PHFetchOptions *opts = [[PHFetchOptions alloc] init];
	opts.predicate = [NSPredicate predicateWithFormat:@"title = %@", [self albumName]];
	PHFetchResult<PHAssetCollection *> *result = [PHAssetCollection
		fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
							  subtype:PHAssetCollectionSubtypeAlbumRegular
							  options:opts];
	if (result.count > 0) {
		if (completion) completion(result.firstObject, nil);
		return;
	}

	__block NSString *placeholderId = nil;
	[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
		PHAssetCollectionChangeRequest *req = [PHAssetCollectionChangeRequest
			creationRequestForAssetCollectionWithTitle:[self albumName]];
		placeholderId = req.placeholderForCreatedAssetCollection.localIdentifier;
	} completionHandler:^(BOOL success, NSError *error) {
		if (!success || !placeholderId) {
			if (completion) completion(nil, error);
			return;
		}
		PHFetchResult<PHAssetCollection *> *fetched = [PHAssetCollection
			fetchAssetCollectionsWithLocalIdentifiers:@[placeholderId] options:nil];
		if (completion) completion(fetched.firstObject, nil);
	}];
}

+ (void)saveFileToAlbum:(NSURL *)fileURL completion:(void (^)(BOOL, NSError *))completion {
	[self saveFileToAlbum:fileURL originalFilename:nil completion:completion];
}

+ (void)saveFileToAlbum:(NSURL *)fileURL originalFilename:(NSString *)originalFilename completion:(void (^)(BOOL, NSError *))completion {
	[self fetchOrCreateAlbumWithCompletion:^(PHAssetCollection *album, NSError *err) {
		if (!album) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(NO, err);
			});
			return;
		}

		__block NSString *assetId = nil;
		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			NSString *ext = [[fileURL pathExtension] lowercaseString];
			BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];

			PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
			PHAssetResourceCreationOptions *opts = [[PHAssetResourceCreationOptions alloc] init];
			opts.shouldMoveFile = YES;
			if (originalFilename.length) opts.originalFilename = originalFilename;
			[req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
							 fileURL:fileURL options:opts];
			req.creationDate = [NSDate date];
			assetId = req.placeholderForCreatedAsset.localIdentifier;

			PHAssetCollectionChangeRequest *albumReq =
				[PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
			[albumReq addAssets:@[req.placeholderForCreatedAsset]];
		} completionHandler:^(BOOL success, NSError *changeErr) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(success, changeErr);
			});
		}];
	}];
}

+ (void)armWatcherIfEnabled {
	if (![RYGUtils getBoolPref:@"save_to_ryukgram_album"]) return;
	[self watchForNextSavedAsset];
}

+ (void)addAssetWithLocalIdentifier:(NSString *)localId
						 completion:(void (^)(BOOL, NSError *))completion {
	if (!localId.length) {
		if (completion) completion(NO, nil);
		return;
	}
	[self fetchOrCreateAlbumWithCompletion:^(PHAssetCollection *album, NSError *err) {
		if (!album) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(NO, err);
			});
			return;
		}
		PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localId] options:nil];
		if (result.count == 0) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(NO, nil);
			});
			return;
		}
		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			PHAssetCollectionChangeRequest *req = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
			[req addAssets:result];
		} completionHandler:^(BOOL success, NSError *changeErr) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(success, changeErr);
			});
		}];
	}];
}

+ (void)watchForNextSavedAsset {
	if (rygActiveWatcher) {
		[[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:rygActiveWatcher];
		[rygActiveWatcher.timeoutTimer invalidate];
		rygActiveWatcher = nil;
	}

	if ([PHPhotoLibrary authorizationStatus] != PHAuthorizationStatusAuthorized &&
		[PHPhotoLibrary authorizationStatus] != PHAuthorizationStatusLimited) {
		return;
	}

	RYGPhotoAlbumWatcher *watcher = [[RYGPhotoAlbumWatcher alloc] init];
	PHFetchOptions *opts = [[PHFetchOptions alloc] init];
	opts.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
	watcher.baseline = [PHAsset fetchAssetsWithOptions:opts];
	[[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:watcher];

	watcher.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
														   repeats:NO
															 block:^(NSTimer *t) {
		if (rygActiveWatcher == watcher) {
			[[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:watcher];
			rygActiveWatcher = nil;
		}
	}];
	rygActiveWatcher = watcher;
}

@end

@implementation RYGPhotoAlbumWatcher

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
	PHFetchResultChangeDetails *details = [changeInstance changeDetailsForFetchResult:self.baseline];
	if (!details || details.insertedObjects.count == 0) return;

	NSArray<PHAsset *> *inserted = details.insertedObjects;
	[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
		[RYGPhotoAlbum fetchOrCreateAlbumWithCompletion:^(PHAssetCollection *album, NSError *err) {}];
	} completionHandler:^(BOOL success, NSError *error) {
		// Two-transaction add so the album exists by the time we reference it.
		[RYGPhotoAlbum fetchOrCreateAlbumWithCompletion:^(PHAssetCollection *album, NSError *err) {
			if (!album) return;
			[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
				PHAssetCollectionChangeRequest *req =
					[PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
				[req addAssets:inserted];
			} completionHandler:nil];
		}];
	}];

	[[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
	[self.timeoutTimer invalidate];
	self.timeoutTimer = nil;
	if (rygActiveWatcher == self) rygActiveWatcher = nil;
}

@end
