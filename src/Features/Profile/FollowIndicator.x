// Follow indicator — shows whether the profile user follows you.
// Fetches once per profile PK, renders directly inside the stats container.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../Networking/SCIInstagramAPI.h"
#import <objc/runtime.h>

static const NSInteger kFollowBadgeTag = 99788;
static const NSInteger kFollowBgTag = 99789;
static const NSInteger kFollowLabelTag = 99790;

static const char kFollowProfilePKKey;
static const char kFollowFetchPKKey;
static const char kFollowContainerKey;

static NSCache *sciFollowCache(void) {
	static NSCache *c;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		c = [NSCache new];
		c.countLimit = 100;
	});
	return c;
}

static inline NSString *sciFollowMode(void) {
	NSString *mode = [SCIUtils getStringPref:@"follow_indicator"];
	return mode.length ? mode : @"off";
}

static inline BOOL sciFollowEnabled(void) {
	return ![sciFollowMode() isEqualToString:@"off"];
}

static inline BOOL sciFollowColored(void) {
	return [sciFollowMode() isEqualToString:@"colored"];
}

static inline NSString *sciFollowProfilePK(id vc) {
	return objc_getAssociatedObject(vc, &kFollowProfilePKKey);
}

static inline void sciSetFollowProfilePK(id vc, NSString *pk) {
	objc_setAssociatedObject(vc, &kFollowProfilePKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static inline NSString *sciFollowFetchPK(id vc) {
	return objc_getAssociatedObject(vc, &kFollowFetchPKKey);
}

static inline void sciSetFollowFetchPK(id vc, NSString *pk) {
	objc_setAssociatedObject(vc, &kFollowFetchPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static inline UIView *sciFollowContainer(id vc) {
	return objc_getAssociatedObject(vc, &kFollowContainerKey);
}

static inline void sciSetFollowContainer(id vc, UIView *view) {
	objc_setAssociatedObject(vc, &kFollowContainerKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *sciProfilePK(UIViewController *vc) {
	@try {
		return [SCIUtils pkFromIGUser:[vc valueForKey:@"user"]];
	} @catch (__unused id e) {
		return nil;
	}
}

static void sciRemoveFollowBadge(UIView *root) {
	[[root viewWithTag:kFollowBadgeTag] removeFromSuperview];
}

static void sciRenderFollowBadge(UIViewController *vc, UIView *container) {
	if (!vc || !container) return;

	NSString *pk = sciFollowProfilePK(vc);
	NSNumber *status = pk.length ? [sciFollowCache() objectForKey:pk] : nil;

	if (!sciFollowEnabled() || !status) {
		sciRemoveFollowBadge(container);
		return;
	}

	BOOL followedBy = status.boolValue;
	BOOL colored = sciFollowColored();

	NSString *text = followedBy
		? SCILocalized(@"Follows you")
		: SCILocalized(@"Doesn't follow you");

	SCIChromeCanvas *badge = (SCIChromeCanvas *)[container viewWithTag:kFollowBadgeTag];

	if (![badge isKindOfClass:SCIChromeCanvas.class]) {
		[badge removeFromSuperview];

		badge = [SCIChromeCanvas new];
		badge.tag = kFollowBadgeTag;
		badge.translatesAutoresizingMaskIntoConstraints = NO;
		badge.userInteractionEnabled = NO;

		UIView *host = badge.contentContainer;

		UIView *bg = [UIView new];
		bg.tag = kFollowBgTag;
		bg.translatesAutoresizingMaskIntoConstraints = NO;
		bg.userInteractionEnabled = NO;
		bg.clipsToBounds = YES;
		bg.layer.cornerRadius = 10.0;

		UILabel *label = [UILabel new];
		label.tag = kFollowLabelTag;
		label.translatesAutoresizingMaskIntoConstraints = NO;
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.78;
		label.lineBreakMode = NSLineBreakByClipping;

		[host addSubview:bg];
		[host addSubview:label];

		[container addSubview:badge];

		[NSLayoutConstraint activateConstraints:@[
			[badge.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
			[badge.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-2.0],
			[badge.heightAnchor constraintEqualToConstant:21.0],
			[badge.widthAnchor constraintGreaterThanOrEqualToConstant:112.0],
			[badge.widthAnchor constraintLessThanOrEqualToConstant:138.0],

			[bg.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
			[bg.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
			[bg.topAnchor constraintEqualToAnchor:host.topAnchor],
			[bg.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],

			[label.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:7.0],
			[label.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-7.0],
			[label.topAnchor constraintEqualToAnchor:host.topAnchor],
			[label.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
		]];
	}

	UIColor *color = followedBy
		? [UIColor colorWithRed:0.22 green:0.68 blue:0.36 alpha:1.0]
		: [UIColor colorWithRed:0.86 green:0.28 blue:0.28 alpha:1.0];

	UILabel *label = (UILabel *)[badge viewWithTag:kFollowLabelTag];
	UIView *bg = [badge viewWithTag:kFollowBgTag];

	label.text = text;
	label.textColor = colored ? color : UIColor.secondaryLabelColor;

	bg.backgroundColor = colored ? [color colorWithAlphaComponent:0.13] : UIColor.clearColor;
	bg.layer.borderWidth = colored ? 1.0 : 0.0;
	bg.layer.borderColor = colored ? [color colorWithAlphaComponent:0.50].CGColor : nil;
}

static void sciResetFollowState(UIViewController *vc) {
	sciRemoveFollowBadge(vc.view);
	sciSetFollowProfilePK(vc, nil);
	sciSetFollowFetchPK(vc, nil);
}

static void sciRenderFollowBadgeNow(UIViewController *vc) {
	UIView *container = sciFollowContainer(vc);
	if (container.window) sciRenderFollowBadge(vc, container);
}

static void sciFetchFollowStatus(UIViewController *vc, NSString *pk) {
	sciSetFollowFetchPK(vc, pk);

	__weak UIViewController *weakVC = vc;
	NSString *requestedPK = pk.copy;
	NSString *path = [NSString stringWithFormat:@"friendships/show/%@/", requestedPK];

	[SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *strongVC = weakVC;
			if (!strongVC) return;

			if (![sciFollowFetchPK(strongVC) isEqualToString:requestedPK]) return;
			sciSetFollowFetchPK(strongVC, nil);

			if (error || ![response isKindOfClass:NSDictionary.class]) return;
			if (![sciFollowProfilePK(strongVC) isEqualToString:requestedPK]) return;

			[sciFollowCache() setObject:@([response[@"followed_by"] boolValue]) forKey:requestedPK];
			sciRenderFollowBadgeNow(strongVC);
		});
	}];
}

static void sciRefreshFollowIndicator(UIViewController *vc) {
	if (!sciFollowEnabled()) {
		sciResetFollowState(vc);
		return;
	}

	NSString *pk = sciProfilePK(vc);
	NSString *myPK = [SCIUtils currentUserPK];

	if (!pk.length || !myPK.length || [pk isEqualToString:myPK]) {
		sciResetFollowState(vc);
		return;
	}

	if (![sciFollowProfilePK(vc) isEqualToString:pk]) {
		sciRemoveFollowBadge(vc.view);
		sciSetFollowProfilePK(vc, pk);
	}

	if ([sciFollowCache() objectForKey:pk]) {
		sciRenderFollowBadgeNow(vc);
		return;
	}

	if (![sciFollowFetchPK(vc) isEqualToString:pk]) {
		sciFetchFollowStatus(vc, pk);
	}
}

%hook IGProfileViewController

- (void)setUser:(id)user {
	%orig;

	dispatch_async(dispatch_get_main_queue(), ^{
		sciRefreshFollowIndicator(self);
	});
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	sciRefreshFollowIndicator(self);
}

%end

%hook _TtC23IGProfileHeaderIdentity38IGProfileHeaderStatButtonContainerView

- (void)layoutSubviews {
	%orig;

	UIView *view = (UIView *)self;
	UIViewController *vc = [SCIUtils nearestViewControllerForView:view];

	if ([vc isKindOfClass:%c(IGProfileViewController)]) {
		sciSetFollowContainer(vc, view);
		sciRenderFollowBadge(vc, view);
	}
}

%end