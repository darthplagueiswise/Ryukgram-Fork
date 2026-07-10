// Reusable wrapper for Instagram private API calls. Reads the Bearer token
// for the active account from IG's keychain group and uses it to talk to
// the legacy /api/v1/ endpoints. Account switches are picked up automatically.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^SCIAPICompletion)(NSDictionary * _Nullable response, NSError * _Nullable error);
typedef void(^SCIAPIStatusesCompletion)(NSDictionary * _Nullable statuses, NSError * _Nullable error);

@interface SCIInstagramAPI : NSObject

// ============ Generic ============

// `path` is the part after /api/v1/, e.g. "friendships/create/123/".
// `body` is form-encoded if non-nil. `completion` runs on the main queue.
+ (void)sendRequestWithMethod:(NSString *)method
                         path:(NSString *)path
                         body:(nullable NSDictionary *)body
                   completion:(nullable SCIAPICompletion)completion;

// Raw bytes from a URL with the account's auth headers; for authed endpoints like media_fallback.
+ (void)downloadAuthorizedURL:(NSURL *)url
                   completion:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completion;

// ============ Friendships ============

+ (void)followUserPK:(NSString *)pk completion:(nullable SCIAPICompletion)completion;
+ (void)unfollowUserPK:(NSString *)pk completion:(nullable SCIAPICompletion)completion;

// Remove a user from your followers (they stop following you). IG-native action.
+ (void)removeFollowerPK:(NSString *)pk completion:(nullable SCIAPICompletion)completion;

// Bulk-fetch friendship statuses for a set of user PKs in one round trip.
// Statuses dict maps pk → {following, outgoing_request, is_private, ...}.
// NOTE: show_many omits `followed_by` — use fetchFriendshipForPK: when you need it.
+ (void)fetchFriendshipStatusesForPKs:(NSArray<NSString *> *)pks
                           completion:(nullable SCIAPIStatusesCompletion)completion;

// Single-user friendship status via /friendships/show/<pk>/. Unlike show_many it
// includes `followed_by`. Status dict is nil on failure — don't classify on nil.
+ (void)fetchFriendshipForPK:(NSString *)pk
                  completion:(nullable SCIAPIStatusesCompletion)completion;

// Incoming follow requests — the people who have requested to follow YOU.
// Walks next_max_id pagination and returns the merged `users` array (user dicts
// with pk/username/full_name/profile_pic_url/is_private). Capped at a few pages.
+ (void)fetchPendingFollowRequestsWithCompletion:(void (^)(NSArray<NSDictionary *> * _Nullable users, NSError * _Nullable error))completion;

// ============ Media ============

// Fetch a single media item. Response carries `items[0]` with `user`, `usertags.in[].user`, etc.
+ (void)fetchMediaInfoForMediaId:(NSString *)mediaId completion:(nullable SCIAPICompletion)completion;

// Batch /media/infos/ — same items[] shape as the single endpoint.
// Use when hydrating many cells to avoid soft-blocks.
+ (void)fetchMediaInfosForMediaIds:(NSArray<NSString *> *)mediaIds
                         completion:(nullable SCIAPICompletion)completion;

// Story viewers ("who viewed my story"). Cursor-paginated via next_max_id in
// the response; pass a small `count` to force multi-page responses for testing.
+ (void)fetchStoryViewersForMediaId:(NSString *)mediaId
                              maxId:(nullable NSString *)maxId
                              count:(NSInteger)count
                         completion:(nullable SCIAPICompletion)completion;

@end

NS_ASSUME_NONNULL_END
