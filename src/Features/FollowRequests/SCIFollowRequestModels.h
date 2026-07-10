#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIFollowRequestType) {
	// Outgoing — requests YOU sent to private accounts.
	SCIFollowRequestTypeSent = 0,      // pending
	SCIFollowRequestTypeAccepted,      // they accepted — you now follow them
	SCIFollowRequestTypeRejected,      // request vanished without a follow
	SCIFollowRequestTypeCancelled,     // you withdrew it

	// Incoming — requests OTHER people sent to YOU.
	SCIFollowRequestTypeReceived,      // pending — they want to follow you
	SCIFollowRequestTypeApproved,      // you accepted — they now follow you
	SCIFollowRequestTypeIgnored,       // you deleted / ignored it
	SCIFollowRequestTypeWithdrawn,     // they cancelled before you acted
};

typedef NS_ENUM(NSInteger, SCIFollowRequestDirection) {
	SCIFollowRequestDirectionOutgoing = 0,
	SCIFollowRequestDirectionIncoming = 1,
};

// One follow request and its eventual outcome. Created when the request appears
// (you send one, or one arrives) and transitions in place to its outcome type.
@interface SCIFollowRequest : NSObject

@property (nonatomic, copy) NSString *recordID;       // uuid, stable across transitions
@property (nonatomic, copy) NSString *userPK;         // the other user
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
@property (nonatomic, copy, nullable) NSString *profilePicID;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) SCIFollowRequestType type;
@property (nonatomic, assign) NSTimeInterval sentAt;      // unix — when the request appeared
@property (nonatomic, assign) NSTimeInterval resolvedAt;  // unix — when it flipped (0 while pending)

+ (instancetype)requestFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)jsonDict;

- (NSString *)displayName;   // username, falls back to full name / pk
- (NSTimeInterval)sortDate;  // resolvedAt if set, else sentAt
- (SCIFollowRequestDirection)direction;
- (BOOL)isPending;           // Sent or Received

+ (SCIFollowRequestDirection)directionForType:(SCIFollowRequestType)type;
+ (NSString *)stringForType:(SCIFollowRequestType)type;
+ (NSString *)symbolForType:(SCIFollowRequestType)type;
+ (UIColor *)colorForType:(SCIFollowRequestType)type;

@end

NS_ASSUME_NONNULL_END
