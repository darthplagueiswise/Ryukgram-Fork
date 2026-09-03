#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// A stored per-story viewer, or an audience member folded across many stories.
@protocol RYGStoryViewerDisplay <NSObject>
@property (nonatomic, copy, readonly) NSString *pk;
@property (nonatomic, copy, readonly, nullable) NSString *username;
@property (nonatomic, copy, readonly, nullable) NSString *fullName;
@property (nonatomic, copy, readonly, nullable) NSString *profilePicURL;
@property (nonatomic, assign, readonly) BOOL isVerified;
@property (nonatomic, assign, readonly) BOOL liked;
@property (nonatomic, assign, readonly) BOOL following;
@property (nonatomic, assign, readonly) BOOL followedBy;
@property (nonatomic, copy, readonly, nullable) NSString *reactionEmoji;
@end

@interface RYGStoryViewerCell : UITableViewCell
- (void)configureWithViewer:(id<RYGStoryViewerDisplay>)viewer pinned:(BOOL)pinned;
- (void)configureWithViewer:(id<RYGStoryViewerDisplay>)viewer pinned:(BOOL)pinned detail:(nullable NSString *)detail;
@end

NS_ASSUME_NONNULL_END
