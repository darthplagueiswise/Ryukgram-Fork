#import "RYGFollowRequestModels.h"
#import "../../Localization/RYGLocalization.h"

@implementation RYGFollowRequest

+ (instancetype)requestFromJSONDict:(NSDictionary *)d {
	if (![d isKindOfClass:NSDictionary.class]) return nil;
	if (![d[@"userPK"] isKindOfClass:NSString.class]) return nil;
	RYGFollowRequest *r = [self new];
	r.recordID = [d[@"recordID"] isKindOfClass:NSString.class] ? d[@"recordID"] : [NSUUID UUID].UUIDString;
	r.userPK = d[@"userPK"];
	r.username = [d[@"username"] isKindOfClass:NSString.class] ? d[@"username"] : nil;
	r.fullName = [d[@"fullName"] isKindOfClass:NSString.class] ? d[@"fullName"] : nil;
	r.profilePicURL = [d[@"profilePicURL"] isKindOfClass:NSString.class] ? d[@"profilePicURL"] : nil;
	r.profilePicID = [d[@"profilePicID"] isKindOfClass:NSString.class] ? d[@"profilePicID"] : nil;
	r.isPrivate = [d[@"isPrivate"] boolValue];
	r.type = (RYGFollowRequestType)[d[@"type"] integerValue];
	r.sentAt = [d[@"sentAt"] doubleValue];
	r.resolvedAt = [d[@"resolvedAt"] doubleValue];
	return r;
}

- (NSDictionary *)jsonDict {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"recordID"] = self.recordID ?: [NSUUID UUID].UUIDString;
	d[@"userPK"] = self.userPK ?: @"";
	if (self.username) d[@"username"] = self.username;
	if (self.fullName) d[@"fullName"] = self.fullName;
	if (self.profilePicURL) d[@"profilePicURL"] = self.profilePicURL;
	if (self.profilePicID) d[@"profilePicID"] = self.profilePicID;
	d[@"isPrivate"] = @(self.isPrivate);
	d[@"type"] = @(self.type);
	d[@"sentAt"] = @(self.sentAt);
	d[@"resolvedAt"] = @(self.resolvedAt);
	return d;
}

- (NSString *)displayName {
	if (self.username.length) return self.username;
	if (self.fullName.length) return self.fullName;
	return self.userPK ?: RYGLocalized(@"Unknown user");
}

- (NSTimeInterval)sortDate { return self.resolvedAt > 0 ? self.resolvedAt : self.sentAt; }
- (RYGFollowRequestDirection)direction { return [RYGFollowRequest directionForType:self.type]; }
- (BOOL)isPending { return self.type == RYGFollowRequestTypeSent || self.type == RYGFollowRequestTypeReceived; }

+ (RYGFollowRequestDirection)directionForType:(RYGFollowRequestType)type {
	return type >= RYGFollowRequestTypeReceived ? RYGFollowRequestDirectionIncoming : RYGFollowRequestDirectionOutgoing;
}

+ (NSString *)stringForType:(RYGFollowRequestType)type {
	switch (type) {
		case RYGFollowRequestTypeSent:      return RYGLocalized(@"Sent");
		case RYGFollowRequestTypeAccepted:  return RYGLocalized(@"Accepted");
		case RYGFollowRequestTypeRejected:  return RYGLocalized(@"Rejected");
		case RYGFollowRequestTypeCancelled: return RYGLocalized(@"Cancelled");
		case RYGFollowRequestTypeReceived:  return RYGLocalized(@"Received");
		case RYGFollowRequestTypeApproved:  return RYGLocalized(@"Approved");
		case RYGFollowRequestTypeIgnored:   return RYGLocalized(@"Ignored");
		case RYGFollowRequestTypeWithdrawn: return RYGLocalized(@"Withdrawn");
	}
	return @"";
}

+ (NSString *)symbolForType:(RYGFollowRequestType)type {
	switch (type) {
		case RYGFollowRequestTypeSent:      return @"paperplane.fill";
		case RYGFollowRequestTypeAccepted:  return @"checkmark.circle.fill";
		case RYGFollowRequestTypeRejected:  return @"xmark.circle.fill";
		case RYGFollowRequestTypeCancelled: return @"arrow.uturn.backward.circle.fill";
		case RYGFollowRequestTypeReceived:  return @"tray.and.arrow.down.fill";
		case RYGFollowRequestTypeApproved:  return @"checkmark.circle.fill";
		case RYGFollowRequestTypeIgnored:   return @"hand.raised.fill";
		case RYGFollowRequestTypeWithdrawn: return @"arrow.uturn.backward.circle.fill";
	}
	return @"circle";
}

+ (UIColor *)colorForType:(RYGFollowRequestType)type {
	switch (type) {
		case RYGFollowRequestTypeSent:      return UIColor.systemBlueColor;
		case RYGFollowRequestTypeAccepted:  return UIColor.systemGreenColor;
		case RYGFollowRequestTypeRejected:  return UIColor.systemRedColor;
		case RYGFollowRequestTypeCancelled: return UIColor.systemGrayColor;
		case RYGFollowRequestTypeReceived:  return UIColor.systemIndigoColor;
		case RYGFollowRequestTypeApproved:  return UIColor.systemGreenColor;
		case RYGFollowRequestTypeIgnored:   return UIColor.systemGrayColor;
		case RYGFollowRequestTypeWithdrawn: return UIColor.systemOrangeColor;
	}
	return UIColor.labelColor;
}

@end
