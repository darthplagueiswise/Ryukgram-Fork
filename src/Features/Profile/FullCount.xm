// Full profile counts — profile header followers/posts as 11,943 instead of 11.9K.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <substrate.h>
#import <objc/runtime.h>

static id rygIvarLookup(id obj, const char *name) {
	if (!obj || !name) return nil;
	for (Class c = [obj class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (iv) {
			@try { return object_getIvar(obj, iv); }
			@catch (__unused id e) { return nil; }
		}
	}
	return nil;
}

static NSString *rygCountText(NSNumber *number) {
	static NSNumberFormatter *formatter;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		formatter = [NSNumberFormatter new];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.usesGroupingSeparator = YES;
	});

	return number ? [formatter stringFromNumber:number] : nil;
}

static NSNumber *rygNum(id value) {
	if ([value isKindOfClass:NSNumber.class]) return value;
	if (![value isKindOfClass:NSString.class]) return nil;

	NSString *text = [(NSString *)value stringByReplacingOccurrencesOfString:@"," withString:@""];
	return text.length ? @(text.longLongValue) : nil;
}

static NSNumber *rygProfileCount(id user, NSDictionary *cache, BOOL posts) {
	return posts
		? (rygNum([user valueForKey:@"mediaCount"]) ?: rygNum([user valueForKey:@"postCount"]) ?: rygNum(cache[@"media_count"]) ?: rygNum(cache[@"post_count"]))
		: (rygNum([user valueForKey:@"followerCount"]) ?: rygNum([user valueForKey:@"followersCount"]) ?: rygNum(cache[@"follower_count"]));
}

static void rygSetText(IGStatButton *button, NSNumber *count) {
	NSString *text = rygCountText(count);
	if (!button || !text.length) return;

	UILabel *label = (UILabel *)rygIvarLookup(button, "_countLabel");
	if (![label isKindOfClass:[UILabel class]]) return;
	label.text = text;
	[label sizeToFit];
}

%hook _TtC23IGProfileHeaderIdentity38IGProfileHeaderStatButtonContainerView
- (void)layoutSubviews {
	%orig;

	BOOL followers = [RYGUtils getBoolPref:@"full_followers_count"];
	BOOL posts = [RYGUtils getBoolPref:@"full_posts_count"];
	if (!followers && !posts) return;

	IGProfileViewController *vc = (IGProfileViewController *)[RYGUtils nearestViewControllerForView:self];
	id user = [vc user];
	NSDictionary *cache = [RYGUtils fieldCacheForObject:user];

	if (followers) {
		id btn = rygIvarLookup(self, "$__lazy_storage_$_followersButton");
		rygSetText((IGStatButton *)btn, rygProfileCount(user, cache, NO));
	}

	if (posts) {
		id btn = rygIvarLookup(self, "postCountButton");
		rygSetText((IGStatButton *)btn, rygProfileCount(user, cache, YES));
	}
}
%end