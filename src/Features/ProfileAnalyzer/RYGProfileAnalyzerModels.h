#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Cached user record (one per follower / following / visit entry).
@interface RYGProfileAnalyzerUser : NSObject <NSCopying>

@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
// Stable IG-internal pic id; only changes when the user uploads a new photo.
@property (nonatomic, copy, nullable) NSString *profilePicID;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) BOOL isVerified;

+ (nullable instancetype)userFromAPIDict:(NSDictionary *)dict;
+ (nullable instancetype)userFromJSONDict:(NSDictionary *)dict;
+ (nullable instancetype)userFromIGUserObject:(id)igUser;
- (NSDictionary *)toJSONDict;

@end

// One visited-profile entry — first/last seen + cumulative count.
@interface RYGProfileAnalyzerVisit : NSObject

@property (nonatomic, strong) RYGProfileAnalyzerUser *user;
@property (nonatomic, strong) NSDate *firstSeen;
@property (nonatomic, strong) NSDate *lastSeen;
@property (nonatomic, assign) NSInteger visitCount;

+ (nullable instancetype)visitFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)toJSONDict;

@end

// Point-in-time capture of an account's graph + self info; persisted as JSON.
@interface RYGProfileAnalyzerSnapshot : NSObject

@property (nonatomic, strong) NSDate *scanDate;
@property (nonatomic, copy) NSString *selfPK;
@property (nonatomic, copy, nullable) NSString *selfUsername;
@property (nonatomic, copy, nullable) NSString *selfFullName;
@property (nonatomic, copy, nullable) NSString *selfProfilePicURL;
@property (nonatomic, assign) NSInteger followerCount;
@property (nonatomic, assign) NSInteger followingCount;
@property (nonatomic, assign) NSInteger mediaCount;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *followers;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *following;

+ (nullable instancetype)snapshotFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)toJSONDict;

@end

// Per-user change between snapshots (username / fullName / pic).
@interface RYGProfileAnalyzerProfileChange : NSObject
@property (nonatomic, strong) RYGProfileAnalyzerUser *previous;
@property (nonatomic, strong) RYGProfileAnalyzerUser *current;
@property (nonatomic, readonly) BOOL usernameChanged;
@property (nonatomic, readonly) BOOL fullNameChanged;
@property (nonatomic, readonly) BOOL profilePicChanged;
@end

// Derived category arrays from (current, previous) snapshots.
@interface RYGProfileAnalyzerReport : NSObject

@property (nonatomic, strong, nullable) RYGProfileAnalyzerSnapshot *current;
@property (nonatomic, strong, nullable) RYGProfileAnalyzerSnapshot *previous;

@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *mutualFollowers;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *notFollowingYouBack;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *youDontFollowBack;
// "recent" / "lost" — `new*` is reserved by ARC's Cocoa new-family rule.
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *recentFollowers;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *lostFollowers;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *youStartedFollowing;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerUser *> *youUnfollowed;
@property (nonatomic, copy) NSArray<RYGProfileAnalyzerProfileChange *> *profileUpdates;

+ (RYGProfileAnalyzerReport *)reportFromCurrent:(nullable RYGProfileAnalyzerSnapshot *)current
                                        previous:(nullable RYGProfileAnalyzerSnapshot *)previous;

@end

NS_ASSUME_NONNULL_END
