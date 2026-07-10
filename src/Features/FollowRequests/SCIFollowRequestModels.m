#import "SCIFollowRequestModels.h"
#import "../../Localization/SCILocalization.h"

@implementation SCIFollowRequest

+ (instancetype)requestFromJSONDict:(NSDictionary *)d {
	if (![d isKindOfClass:NSDictionary.class]) return nil;
	if (![d[@"userPK"] isKindOfClass:NSString.class]) return nil;
	SCIFollowRequest *r = [self new];
	r.recordID = [d[@"recordID"] isKindOfClass:NSString.class] ? d[@"recordID"] : [NSUUID UUID].UUIDString;
	r.userPK = d[@"userPK"];
	r.username = [d[@"username"] isKindOfClass:NSString.class] ? d[@"username"] : nil;
	r.fullName = [d[@"fullName"] isKindOfClass:NSString.class] ? d[@"fullName"] : nil;
	r.profilePicURL = [d[@"profilePicURL"] isKindOfClass:NSString.class] ? d[@"profilePicURL"] : nil;
	r.profilePicID = [d[@"profilePicID"] isKindOfClass:NSString.class] ? d[@"profilePicID"] : nil;
	r.isPrivate = [d[@"isPrivate"] boolValue];
	r.type = (SCIFollowRequestType)[d[@"type"] integerValue];
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
	return self.userPK ?: SCILocalized(@"Unknown user");
}

- (NSTimeInterval)sortDate { return self.resolvedAt > 0 ? self.resolvedAt : self.sentAt; }
- (SCIFollowRequestDirection)direction { return [SCIFollowRequest directionForType:self.type]; }
- (BOOL)isPending { return self.type == SCIFollowRequestTypeSent || self.type == SCIFollowRequestTypeReceived; }

+ (SCIFollowRequestDirection)directionForType:(SCIFollowRequestType)type {
	return type >= SCIFollowRequestTypeReceived ? SCIFollowRequestDirectionIncoming : SCIFollowRequestDirectionOutgoing;
}

+ (NSString *)stringForType:(SCIFollowRequestType)type {
	switch (type) {
		case SCIFollowRequestTypeSent:      return SCILocalized(@"Sent");
		case SCIFollowRequestTypeAccepted:  return SCILocalized(@"Accepted");
		case SCIFollowRequestTypeRejected:  return SCILocalized(@"Rejected");
		case SCIFollowRequestTypeCancelled: return SCILocalized(@"Cancelled");
		case SCIFollowRequestTypeReceived:  return SCILocalized(@"Received");
		case SCIFollowRequestTypeApproved:  return SCILocalized(@"Approved");
		case SCIFollowRequestTypeIgnored:   return SCILocalized(@"Ignored");
		case SCIFollowRequestTypeWithdrawn: return SCILocalized(@"Withdrawn");
	}
	return @"";
}

+ (NSString *)symbolForType:(SCIFollowRequestType)type {
	switch (type) {
		case SCIFollowRequestTypeSent:      return @"paperplane.fill";
		case SCIFollowRequestTypeAccepted:  return @"checkmark.circle.fill";
		case SCIFollowRequestTypeRejected:  return @"xmark.circle.fill";
		case SCIFollowRequestTypeCancelled: return @"arrow.uturn.backward.circle.fill";
		case SCIFollowRequestTypeReceived:  return @"tray.and.arrow.down.fill";
		case SCIFollowRequestTypeApproved:  return @"checkmark.circle.fill";
		case SCIFollowRequestTypeIgnored:   return @"hand.raised.fill";
		case SCIFollowRequestTypeWithdrawn: return @"arrow.uturn.backward.circle.fill";
	}
	return @"circle";
}

+ (UIColor *)colorForType:(SCIFollowRequestType)type {
	switch (type) {
		case SCIFollowRequestTypeSent:      return UIColor.systemBlueColor;
		case SCIFollowRequestTypeAccepted:  return UIColor.systemGreenColor;
		case SCIFollowRequestTypeRejected:  return UIColor.systemRedColor;
		case SCIFollowRequestTypeCancelled: return UIColor.systemGrayColor;
		case SCIFollowRequestTypeReceived:  return UIColor.systemIndigoColor;
		case SCIFollowRequestTypeApproved:  return UIColor.systemGreenColor;
		case SCIFollowRequestTypeIgnored:   return UIColor.systemGrayColor;
		case SCIFollowRequestTypeWithdrawn: return UIColor.systemOrangeColor;
	}
	return UIColor.labelColor;
}

@end
