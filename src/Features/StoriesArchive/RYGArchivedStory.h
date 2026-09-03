#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@class RYGArchivedStoryViewer;

@interface RYGArchivedStory : NSManagedObject

@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy) NSString *mediaID;
@property (nonatomic, assign) int16_t mediaType;
@property (nonatomic, copy, nullable) NSDate *takenAt;
@property (nonatomic, copy, nullable) NSDate *expiresAt;
@property (nonatomic, copy, nullable) NSString *sectionID;
@property (nonatomic, copy, nullable) NSString *mediaRelPath;
@property (nonatomic, copy, nullable) NSString *thumbRelPath;
@property (nonatomic, assign) int64_t viewersCount;
@property (nonatomic, assign) int64_t likesCount;
@property (nonatomic, assign) int64_t reactionsCount;
@property (nonatomic, assign) int64_t totalViewersCount;
@property (nonatomic, copy, nullable) NSDate *lastViewersFetch;
// Set when IG reports the media gone; stops the retry loop inside the 48h window.
@property (nonatomic, assign) BOOL viewersFinal;
@property (nonatomic, strong) NSOrderedSet<RYGArchivedStoryViewer *> *viewers;

@end

NS_ASSUME_NONNULL_END
