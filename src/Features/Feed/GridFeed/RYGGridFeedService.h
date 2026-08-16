#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RYGGridFeedMediaType) {
	RYGGridFeedMediaTypePhoto = 1,
	RYGGridFeedMediaTypeVideo = 2,
	RYGGridFeedMediaTypeCarousel = 8,
};

@interface RYGGridFeedPost : NSObject
@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy) NSString *mediaID;
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *thumbURLString;
@property (nonatomic) RYGGridFeedMediaType mediaType;
@property (nonatomic) NSInteger likeCount;
@property (nonatomic) NSInteger commentCount;
@property (nonatomic) NSInteger viewCount;
@property (nonatomic) NSInteger shareCount;
@property (nonatomic) NSInteger carouselCount;
@property (nonatomic) NSTimeInterval takenAt;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *userPK;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic) BOOL countsHidden;
@property (nonatomic) BOOL hasLiked;
@property (nonatomic) BOOL isFollowing;
+ (nullable instancetype)postFromMediaDict:(NSDictionary *)media;
// Converts an IG feed model object (IGMedia) into a post using IG's own accessors.
+ (nullable instancetype)postFromIGMedia:(id)media;
- (NSDictionary *)toDictionary;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
@end

typedef void(^RYGGridFeedLoadCompletion)(NSArray<RYGGridFeedPost *> *newPosts, NSError *error);

@interface RYGGridFeedService : NSObject
@property (nonatomic, readonly) NSArray<RYGGridFeedPost *> *posts;
@property (nonatomic) BOOL following;
// Set before loadCache so the disk cache is scoped to the signed-in account.
@property (nonatomic, copy, nullable) NSString *accountPK;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) BOOL moreAvailable;

// Fetches a fresh top page. Keeps the current posts on screen until the page lands,
// then swaps them out (no blank flash mid-refresh).
- (void)refreshWithCompletion:(RYGGridFeedLoadCompletion)completion;
- (void)loadMoreWithCompletion:(RYGGridFeedLoadCompletion)completion;
- (void)clear;

// A pagination page from IG's transport: appends unique posts at the end. Returns count added.
- (NSInteger)ingestNextPage:(NSArray<RYGGridFeedPost *> *)posts nextMaxID:(nullable NSString *)nextMaxID;
// Indices of already-shown posts whose stats changed since last call (then cleared).
- (NSIndexSet *)takePendingUpdated;

// Per-account disk cache. loadCache after setting `accountPK` and `following`.
- (void)loadCache;
- (void)saveCache;
@end
