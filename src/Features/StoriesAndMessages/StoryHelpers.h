// StoryHelpers.h
// Shared light helpers for story / DM visual message features.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

typedef id (*SCIMsgSend0)(id, SEL);
typedef id (*SCIMsgSend1)(id, SEL, id);

static inline id sciCall(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((SCIMsgSend0)objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static inline id sciCall1(id obj, SEL sel, id arg) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((SCIMsgSend1)objc_msgSend)(obj, sel, arg);
	} @catch (__unused id e) {
		return nil;
	}
}

static inline UIViewController *sciFindVC(UIResponder *start, NSString *className) {
	Class cls = NSClassFromString(className);
	if (!cls) return nil;

	UIResponder *r = start;

	while (r) {
		if ([r isKindOfClass:cls]) return (UIViewController *)r;
		r = r.nextResponder;
	}

	return nil;
}

static inline IGMedia *sciExtractMediaFromItem(id item) {
	if (!item) return nil;

	Class mediaClass = NSClassFromString(@"IGMedia");
	if (!mediaClass) return nil;

	if ([item isKindOfClass:mediaClass]) {
		return (IGMedia *)item;
	}

	for (NSString *name in @[@"media", @"mediaItem", @"storyItem", @"item", @"feedItem", @"igMedia", @"model", @"backingModel", @"storyMedia", @"mediaModel"]) {
		id value = sciCall(item, NSSelectorFromString(name));

		if ([value isKindOfClass:mediaClass]) {
			return (IGMedia *)value;
		}
	}

	// No accessor matched — scan ivars so an IG media-getter rename can't blank the surface.
	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList([item class], &count);
	IGMedia *found = nil;
	for (unsigned int i = 0; i < count; i++) {
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!type || type[0] != '@') continue;
		id value = object_getIvar(item, ivars[i]);
		if ([value isKindOfClass:mediaClass]) { found = (IGMedia *)value; break; }
	}
	if (ivars) free(ivars);
	return found;
}
