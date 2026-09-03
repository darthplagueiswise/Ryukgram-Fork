// Relationship text under the follow button in follower / following lists, read
// from the friendship the cell already holds. The button covers whether you
// follow them, so this only reports whether they follow you.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGProfileHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger kListRelTag = 99791;
static BOOL sColored;

static UIView *rygCellIvarView(id cell, const char *name) {
	Ivar iv = class_getInstanceVariable([cell class], name);
	id v = iv ? object_getIvar(cell, iv) : nil;
	return [v isKindOfClass:UIView.class] ? v : nil;
}

%group FollowListIndicator

%hook IGFollowListCollectionCell

- (void)layoutSubviews {
	%orig;

	UIView *host = self.contentView;
	UILabel *label = (UILabel *)[host viewWithTag:kListRelTag];

	id user = [self respondsToSelector:@selector(user)] ? [self user] : nil;
	BOOL following = NO, followedBy = NO;
	UIView *followButton = rygCellIvarView(self, "_followButton");

	if (!user || !followButton || followButton.hidden ||
		![RYGProfileHelpers relationForUser:user following:&following followedBy:&followedBy]) {
		label.hidden = YES;
		return;
	}

	if (!label) {
		label = [UILabel new];
		label.tag = kListRelTag;
		label.textAlignment = NSTextAlignmentCenter;
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.7;
		label.lineBreakMode = NSLineBreakByClipping;
		label.userInteractionEnabled = NO;
		label.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightMedium];
		[host addSubview:label];
	}

	label.hidden = NO;
	label.text = followedBy
		? (following ? RYGLocalized(@"Mutual") : RYGLocalized(@"Follows you"))
		: RYGLocalized(@"Doesn't follow you");
	label.textColor = sColored
		? (followedBy ? [UIColor colorWithRed:0.22 green:0.68 blue:0.36 alpha:1.0]
		              : [UIColor colorWithRed:0.86 green:0.28 blue:0.28 alpha:1.0])
		: UIColor.secondaryLabelColor;

	CGRect b = [followButton convertRect:followButton.bounds toView:host];
	CGFloat h = 12.0;
	CGFloat y = MIN(CGRectGetMaxY(b), CGRectGetMaxY(host.bounds) - h);
	label.frame = CGRectMake(CGRectGetMinX(b), y, CGRectGetWidth(b), h);
	[host bringSubviewToFront:label];
}

- (void)prepareForReuse {
	%orig;
	[self.contentView viewWithTag:kListRelTag].hidden = YES;
}

%end

%end

%ctor {
	NSString *mode = [RYGUtils getStringPref:@"follow_indicator_lists"];
	if (!mode.length || [mode isEqualToString:@"off"]) return;
	sColored = [mode isEqualToString:@"colored"];
	%init(FollowListIndicator);
}
