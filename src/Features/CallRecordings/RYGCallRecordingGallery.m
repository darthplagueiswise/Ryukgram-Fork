#import "RYGCallRecordingGallery.h"
#import "RYGCallRecordingStorage.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "../../Gallery/RYGGalleryCoreDataStack.h"
#import "../../Utils.h"
#import <CoreData/CoreData.h>

@implementation RYGCallRecordingGallery

+ (void)load {
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(recordingsChanged:)
											   name:RYGCallRecordingsDidChangeNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(galleryFileRemoved:)
											   name:RYGGalleryFileDidRemoveNotification object:nil];
}

+ (void)recordingsChanged:(NSNotification *)n {
	NSString *owner = n.userInfo[@"owner_pk"];
	if (owner.length) [self syncAllForOwnerPK:owner];
}

// Gallery deleted a shared call recording → delete the source record too (the file is
// already gone). This cascades back into a reconcile that drops the (now absent) entry.
+ (void)galleryFileRemoved:(NSNotification *)n {
	if ([n.userInfo[@"source"] integerValue] != RYGGallerySourceCalls) return;
	NSString *rid = n.userInfo[@"sourceMediaPK"], *owner = n.userInfo[@"sourceMediaCode"];
	if (rid.length && owner.length) [RYGCallRecordingStorage deleteRecordingId:rid forOwnerPK:owner];
}

+ (void)syncRecording:(RYGCallRecording *)recording absolutePath:(NSString *)path ownerPK:(NSString *)ownerPK {
	if (!recording.recordingId.length || !path.length) return;
	if (![NSFileManager.defaultManager fileExistsAtPath:path]) return;

	RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
	md.source = RYGGallerySourceCalls;
	md.sourceUsername = recording.displayName;
	md.sourceUserPK = recording.peerPk;
	md.sourceProfileURLString = recording.peerProfilePicURL;
	md.sourceMediaPK = recording.recordingId;
	md.sourceMediaCode = ownerPK;   // owner, so a gallery delete can cascade back
	md.durationSeconds = recording.durationSeconds;

	[RYGGalleryFile referenceFileAtPath:path
								 source:RYGGallerySourceCalls
							  mediaType:(recording.isVideo ? RYGGalleryMediaTypeVideo : RYGGalleryMediaTypeAudio)
							   metadata:md
								  error:nil];
}

// Mirror the store's recordings as gallery references (no copies): add missing when sync
// is on, drop entries whose recording is gone, drop everything when sync is off.
+ (void)syncAllForOwnerPK:(NSString *)ownerPK {
	if (!ownerPK.length) return;
	BOOL syncOn = [RYGUtils getBoolPref:@"call_recordings_sync_gallery"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSArray<RYGCallRecording *> *recs = [RYGCallRecordingStorage allRecordingsForOwnerPK:ownerPK];
		NSMutableDictionary<NSString *, RYGCallRecording *> *byId = [NSMutableDictionary dictionary];
		for (RYGCallRecording *r in recs) if (r.recordingId.length) byId[r.recordingId] = r;

		NSManagedObjectContext *ctx = [RYGGalleryCoreDataStack shared].viewContext;
		NSFileManager *fm = NSFileManager.defaultManager;
		NSMutableSet<NSString *> *present = [NSMutableSet set];
		[ctx performBlockAndWait:^{
			NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"RYGGalleryFile"];
			req.predicate = [NSPredicate predicateWithFormat:@"source == %d", (int)RYGGallerySourceCalls];
			BOOL changed = NO;
			for (RYGGalleryFile *f in [ctx executeFetchRequest:req error:nil] ?: @[]) {
				BOOL isRef = [f.relativePath hasPrefix:@"/"];
				BOOL mine = [f.sourceMediaCode isEqualToString:ownerPK];
				if (isRef && !mine) continue;   // another account's reference — its own reconcile handles it
				if (isRef && syncOn && f.sourceMediaPK.length && byId[f.sourceMediaPK]) { [present addObject:f.sourceMediaPK]; continue; }
				NSString *thumb = [f thumbnailPath];
				if (thumb.length) [fm removeItemAtPath:thumb error:nil];
				if (!isRef) [fm removeItemAtPath:[f filePath] error:nil];   // old copy → reclaim the duplicated file
				[ctx deleteObject:f];   // deleteObject (no cascade) — the shared source file belongs to the store
				changed = YES;
			}
			if (changed) [ctx save:nil];
		}];

		if (!syncOn) return;
		for (RYGCallRecording *r in recs) {
			if ([present containsObject:r.recordingId]) continue;
			NSString *path = [RYGCallRecordingStorage absolutePathForRelativePath:r.mediaPath ownerPK:ownerPK];
			if (path.length) [self syncRecording:r absolutePath:path ownerPK:ownerPK];
		}
	});
}

@end
