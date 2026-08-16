#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RYGStoriesArchiveDidChangeNotification;

@interface RYGStoriesArchiveManager : NSObject

+ (instancetype)shared;

// Gated by ryg_stories_archive.
- (void)handleTraySectionController:(id)sectionController;

// Fetches a final viewer snapshot for stories 24–48h old. Gated by
// ryg_stories_archive_auto_viewers.
- (void)checkAndFetchViewers;

// completion runs on main.
- (void)refreshViewersForMediaID:(NSString *)mediaID completion:(nullable void (^)(NSInteger count))completion;

- (void)recheck;

@end

NS_ASSUME_NONNULL_END
