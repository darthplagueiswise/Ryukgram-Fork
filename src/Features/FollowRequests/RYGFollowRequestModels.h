#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGFollowRequestType) {
	// Outgoing — requests YOU sent to private accounts.
	RYGFollowRequestTypeSent = 0,      // pending
	RYGFollowRequestTypeAccepted,      // they accepted — you now follow them
	RYGFollowRequestTypeRejected,      // request vanished without a follow
	RYGFollowRequestTypeCancelled,     // you withdrew it

	// Incoming — requests OTHER people sent to YOU.
	RYGFollowRequestTypeReceived,      // pending — they want to follow you
	RYGFollowRequestTypeApproved,      // you accepted — they now follow you
	RYGFollowRequestTypeIgnored,       // you deleted / ignored it
	RYGFollowRequestTypeWithdrawn,     // they cancelled before you acted
};

typedef NS_ENUM(NSInteger, RYGFollowRequestDirection) {
	RYGFollowRequestDirectionOutgoing = 0,
	RYGFollowRequestDirectionIncoming = 1,
};

// One follow request and its eventual outcome. Created when the request appears
// (you send one, or one arrives) and transitions in place to its outcome type.
@interface RYGFollowRequest : NSObject

@property (nonatomic, copy) NSString *recordID;       // uuid, stable across transitions
@property (nonatomic, copy) NSString *userPK;         // the other user
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
@property (nonatomic, copy, nullable) NSString *profilePicID;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) RYGFollowRequestType type;
@property (nonatomic, assign) NSTimeInterval sentAt;      // unix — when the request appeared
@property (nonatomic, assign) NSTimeInterval resolvedAt;  // unix — when it flipped (0 while pending)

+ (instancetype)requestFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)jsonDict;

- (NSString *)displayName;   // username, falls back to full name / pk
- (NSTimeInterval)sortDate;  // resolvedAt if set, else sentAt
- (RYGFollowRequestDirection)direction;
- (BOOL)isPending;           // Sent or Received

+ (RYGFollowRequestDirection)directionForType:(RYGFollowRequestType)type;
+ (NSString *)stringForType:(RYGFollowRequestType)type;
+ (NSString *)symbolForType:(RYGFollowRequestType)type;
+ (UIColor *)colorForType:(RYGFollowRequestType)type;

@end

NS_ASSUME_NONNULL_END
