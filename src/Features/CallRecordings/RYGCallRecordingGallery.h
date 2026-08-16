#import <Foundation/Foundation.h>
#import "RYGCallRecordingModels.h"

NS_ASSUME_NONNULL_BEGIN

// Mirrors a saved call recording into the in-app RyukGram gallery (source = Calls),
// tagged with the peer/group as its attribution so gallery filters and per-user
// grouping work. Called on commit when `call_recordings_sync_gallery` is on.
@interface RYGCallRecordingGallery : NSObject
+ (void)syncRecording:(RYGCallRecording *)recording absolutePath:(NSString *)path ownerPK:(NSString *)ownerPK;
// Backfill: mirror every not-yet-synced recording (existing ones too). Runs off the main thread.
+ (void)syncAllForOwnerPK:(NSString *)ownerPK;
@end

NS_ASSUME_NONNULL_END
