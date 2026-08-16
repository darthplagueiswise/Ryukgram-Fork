// Repost date on the "X reposted this reel" modal header.
// Date from IGDirectReplyToAuthorViewController._shareContent._repost_note (IGRepostModel)
// -> _createdAtDate — the repost time, not the media's own date.

#import "../../RYGChrome.h"
#import "../../Utils.h"
#import "../General/RYGDateFormatRender.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static const void *kRepostDateLabelKey = &kRepostDateLabelKey;

static NSString *RYGRepostDateString(NSDate *date) {
	if (!date) return nil;
	NSString *key = [RYGUtils getStringPref:@"repost_date_format"];
	if (!key.length || [key isEqualToString:@"general"]) {
		NSString *s = RYGGeneralDateString(date);
		if (s.length) return s;
		return RYGDateStringForKey(date, @"medium", NO) ?: RYGCompactRelativeDateString(date);
	}
	if ([key isEqualToString:@"relative"]) return RYGCompactRelativeDateString(date);
	if ([key isEqualToString:@"rel_date"] || [key isEqualToString:@"date_rel"]) {
		NSString *rel = RYGCompactRelativeDateString(date);
		NSString *abs = RYGDateStringForKey(date, @"medium", NO);
		if (!abs.length) return rel;
		if (!rel.length) return abs;
		return [key isEqualToString:@"rel_date"]
			? [NSString stringWithFormat:@"%@ – %@", rel, abs]
			: [NSString stringWithFormat:@"%@ (%@)", abs, rel];
	}
	NSString *s = RYGDateStringForKey(date, key, [RYGUtils getBoolPref:@"feed_date_show_seconds"]);
	return s.length ? s : RYGCompactRelativeDateString(date);
}

static id rygIvar(id obj, const char *name) {
	if (!obj) return nil;
	Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
	if (!iv) return nil;
	id v = nil;
	@try { v = object_getIvar(obj, iv); } @catch (__unused id e) {}
	return v;
}

static NSDate *rygRepostDateForTitleView(UIView *titleView) {
	Class replyCls = NSClassFromString(@"IGDirectReplyToAuthorViewController");
	if (!replyCls) return nil;

	id vc = nil;
	for (UIResponder *r = titleView; r; r = r.nextResponder) {
		if ([r isKindOfClass:replyCls]) { vc = r; break; }
	}
	if (!vc) {
		UIViewController *root = titleView.window.rootViewController;
		for (int i = 0; root.presentedViewController && i < 12; i++) root = root.presentedViewController;
		if ([root isKindOfClass:replyCls]) vc = root;
	}
	if (!vc) return nil;

	id note = rygIvar(rygIvar(vc, "_shareContent"), "_repost_note");
	if (![note isKindOfClass:NSClassFromString(@"IGRepostModel")]) return nil;

	id igdate = rygIvar(note, "_createdAtDate");
	Ivar mi = igdate ? class_getInstanceVariable(object_getClass(igdate), "_microseconds") : NULL;
	if (!mi) return nil;
	long long us = *(long long *)((char *)(__bridge void *)igdate + ivar_getOffset(mi));
	if (us <= 0) return nil;
	return [NSDate dateWithTimeIntervalSince1970:(double)us / 1e6];
}

static void (*orig_titleLayout)(id, SEL);
static void new_titleLayout(id self, SEL _cmd) {
	orig_titleLayout(self, _cmd);

	UIView *titleView = (UIView *)self;
	RYGChromeLabel *label = objc_getAssociatedObject(titleView, kRepostDateLabelKey);

	NSDate *date = rygRepostDateForTitleView(titleView);
	NSString *text = RYGRepostDateString(date);
	UIView *titleBtn = rygIvar(titleView, "_titleButton");
	if (!date || !text.length || !titleBtn) {
		if (label) label.hidden = YES;
		return;
	}

	if (!label) {
		label = [[RYGChromeLabel alloc] initWithText:text];
		label.translatesAutoresizingMaskIntoConstraints = YES;
		label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
		label.textColor = [UIColor secondaryLabelColor];
		label.textAlignment = NSTextAlignmentRight;
		[titleView addSubview:label];
		objc_setAssociatedObject(titleView, kRepostDateLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	label.hidden = NO;
	label.text = text;

	CGFloat gap = 8.0;
	CGFloat w = ceil([text sizeWithAttributes:@{ NSFontAttributeName: label.font }].width) + 2.0;
	CGFloat h = CGRectGetHeight(titleBtn.frame) > 0 ? CGRectGetHeight(titleBtn.frame) : 17.0;
	CGFloat bounds = CGRectGetWidth(titleView.bounds);
	CGRect tf = titleBtn.frame;

	// Long title would push the date off-screen -> shrink the title so it tail-truncates
	// and the date stays fully visible; hide only if there's no room even after that.
	if (CGRectGetMaxX(tf) + gap + w > bounds) {
		CGFloat cap = bounds - w - gap - tf.origin.x;
		if (cap < 44.0) { label.hidden = YES; return; }
		tf.size.width = cap;
		titleBtn.frame = tf;
		if ([titleBtn respondsToSelector:@selector(titleLabel)])
			[(UIButton *)titleBtn titleLabel].lineBreakMode = NSLineBreakByTruncatingTail;
	}

	CGFloat x = bounds - w;
	CGFloat y = CGRectGetMidY(titleBtn.frame) - h / 2.0;
	label.frame = CGRectMake(x, y, w, h);
}

%ctor {
	if (![RYGUtils getBoolPref:@"repost_show_date"]) return;

	Class cls = NSClassFromString(@"IGDirectMessageModalTitleView");
	if (!cls) return;
	SEL sel = @selector(layoutSubviews);
	if (!class_getInstanceMethod(cls, sel)) return;
	MSHookMessageEx(cls, sel, (IMP)new_titleLayout, (IMP *)&orig_titleLayout);
}
