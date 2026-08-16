#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@class RYGArchivedStory;

@interface RYGArchivedStoryViewer : NSManagedObject

@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
@property (nonatomic, assign) BOOL isVerified;
@property (nonatomic, assign) BOOL liked;
@property (nonatomic, assign) BOOL following;
@property (nonatomic, assign) BOOL followedBy;
@property (nonatomic, assign) int32_t sortIndex;
@property (nonatomic, assign) BOOL addedInLatestFetch;
@property (nonatomic, copy, nullable) NSString *reactionEmoji;
@property (nonatomic, copy, nullable) NSDate *addedAt;
@property (nonatomic, strong, nullable) RYGArchivedStory *story;

@end

NS_ASSUME_NONNULL_END
