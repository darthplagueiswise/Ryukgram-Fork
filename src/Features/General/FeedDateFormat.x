// Replaces IG's own timestamps with the user's date format.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGDateFormatEntries.h"
#import "RYGDateFormatRender.h"
#import <substrate.h>

#define rygFormatDate RYGGeneralDateString

#define RYG_HOOK0(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd) { \
		if ([RYGUtils getBoolPref:@PREF]) { \
			NSString *r = rygFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd); \
	}

#define RYG_HOOK1(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1) { \
		if ([RYGUtils getBoolPref:@PREF]) { \
			NSString *r = rygFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1); \
	}

#define RYG_HOOK2(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2) { \
		if ([RYGUtils getBoolPref:@PREF]) { \
			NSString *r = rygFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2); \
	}

#define RYG_HOOK3(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3) { \
		if ([RYGUtils getBoolPref:@PREF]) { \
			NSString *r = rygFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2, a3); \
	}

#define RYG_HOOK4(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3, NSInteger a4) { \
		if ([RYGUtils getBoolPref:@PREF]) { \
			NSString *r = rygFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2, a3, a4); \
	}

#define RYG_EMIT_HOOK(NAME, SEL_, LABEL, ARITY, PREF) RYG_HOOK##ARITY(NAME, SEL_, LABEL, PREF)
RYG_DATE_FORMAT_ENTRIES(RYG_EMIT_HOOK)

#define RYG_INSTALL_HOOK(NAME, SEL_, LABEL, ARITY, PREF) do { \
	SEL s = sel_registerName(SEL_); \
	if ([[NSDate class] instancesRespondToSelector:s]) { \
		MSHookMessageEx([NSDate class], s, (IMP)hook_##NAME, (IMP *)&orig_##NAME); \
	} \
} while (0);

// Active-thread inbox rows ship an empty timestampText, so fill it from the message date.
static NSDictionary *rygInboxTSAttrs = nil;

%hook IGDirectInboxThreadCellViewModel

- (NSAttributedString *)timestampText {
	NSAttributedString *orig = %orig;
	if (![RYGUtils getBoolPref:@"date_fmt_dms"]) return orig;

	if (orig.length > 0) {
		rygInboxTSAttrs = [orig attributesAtIndex:0 effectiveRange:NULL];
		return orig;
	}

	NSDate *date = nil;
	@try { date = [(id)self valueForKey:@"mostRecentMessageActivityDate"]; } @catch (__unused NSException *e) {}
	if (![date isKindOfClass:[NSDate class]]) return orig;

	NSString *formatted = rygFormatDate(date);
	if (!formatted.length) return orig;

	NSDictionary *attrs = rygInboxTSAttrs ?: @{ NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
	                                            NSFontAttributeName: [UIFont systemFontOfSize:13.0] };
	return [[NSAttributedString alloc] initWithString:[@"· " stringByAppendingString:formatted] attributes:attrs];
}

%end

// One story header variant formats through these class methods instead of the NSDate ones.
static NSString *(*orig_storyTimeText)(Class, SEL, NSDate *, long long);
static NSString *hook_storyTimeText(Class self, SEL _cmd, NSDate *date, long long fmt) {
	RYGProbeOnce(@"datefmt.story.sundial", @"storyItemHeaderTimeText:dateFormat:");
	if ([RYGUtils getBoolPref:@"date_fmt_notes_comments_stories"] && [date isKindOfClass:[NSDate class]]) {
		NSString *r = rygFormatDate(date);
		if (r.length) return r;
	}
	return orig_storyTimeText(self, _cmd, date, fmt);
}

static NSString *(*orig_storyTimeTextExp)(Class, SEL, NSDate *, long long, NSDate *);
static NSString *hook_storyTimeTextExp(Class self, SEL _cmd, NSDate *date, long long fmt, NSDate *exp) {
	RYGProbeOnce(@"datefmt.story.sundial_exp", @"storyItemHeaderTimeTextWithExpiration:dateFormat:expiringAtDate:");
	if ([RYGUtils getBoolPref:@"date_fmt_notes_comments_stories"] && [date isKindOfClass:[NSDate class]]) {
		NSString *r = rygFormatDate(date);
		if (r.length) return r;
	}
	return orig_storyTimeTextExp(self, _cmd, date, fmt, exp);
}

static void rygInstallStoryHeaderHooks(void) {
	Class cls = NSClassFromString(@"_TtC33IGStoryFullscreenHeaderViewModels37IGStoryItemHeaderAccessibilityHelpers")
	            ?: NSClassFromString(@"IGStoryItemHeaderAccessibilityHelpers");
	if (!cls) return;
	Class meta = object_getClass(cls);

	SEL s1 = @selector(storyItemHeaderTimeText:dateFormat:);
	if ([cls respondsToSelector:s1])
		MSHookMessageEx(meta, s1, (IMP)hook_storyTimeText, (IMP *)&orig_storyTimeText);

	SEL s2 = @selector(storyItemHeaderTimeTextWithExpiration:dateFormat:expiringAtDate:);
	if ([cls respondsToSelector:s2])
		MSHookMessageEx(meta, s2, (IMP)hook_storyTimeTextExp, (IMP *)&orig_storyTimeTextExp);
}

%ctor {
	RYG_DATE_FORMAT_ENTRIES(RYG_INSTALL_HOOK)
	rygInstallStoryHeaderHooks();
}
