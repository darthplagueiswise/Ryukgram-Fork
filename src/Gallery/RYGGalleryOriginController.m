#import "RYGGalleryOriginController.h"
#import "RYGGalleryFile.h"
#import "RYGGallerySaveMetadata.h"
#import "../Utils.h"
#import "../RYGURLOpener.h"
#import "RYGGalleryShim.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSArray<NSString *> *RYGUserKeys(void) {
	static NSArray *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[@"user", @"owner", @"author", @"creator", @"actor", @"profileUser"];
	});
	return keys;
}

static NSArray<NSString *> *RYGNestedKeys(void) {
	static NSArray *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[@"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post"];
	});
	return keys;
}

static id RYGObjectForSelector(id target, NSString *name) {
	if (!target || !name.length) return nil;

	SEL sel = NSSelectorFromString(name);
	if (![target respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(target, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id RYGKVCObject(id target, NSString *key) {
	if (!target || !key.length) return nil;

	@try {
		return [target valueForKey:key];
	} @catch (__unused id e) {
		return nil;
	}
}

static id RYGFieldValue(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	return [RYGUtils fieldCacheValue:obj forKey:key];
}

static id RYGValueForKeyPathLike(id target, NSString *key) {
	if (!target || !key.length) return nil;

	id value = RYGObjectForSelector(target, key);
	if (!value) value = RYGKVCObject(target, key);
	if (!value) value = RYGFieldValue(target, key);

	return value;
}

static NSString *RYGStringValue(id value) {
	if (!value) return nil;

	if ([value isKindOfClass:NSString.class]) {
		return [(NSString *)value length] ? value : nil;
	}

	if ([value respondsToSelector:@selector(stringValue)]) {
		NSString *string = [value stringValue];
		return string.length ? string : nil;
	}

	if ([value respondsToSelector:@selector(description)]) {
		NSString *string = [value description];
		return string.length ? string : nil;
	}

	return nil;
}

static NSString *RYGStringForKey(id target, NSString *key) {
	return RYGStringValue(RYGValueForKeyPathLike(target, key));
}

static NSURL *RYGURLValue(id value) {
	if ([value isKindOfClass:NSURL.class]) return value;

	if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) {
		return [NSURL URLWithString:(NSString *)value];
	}

	return nil;
}

static NSURL *RYGURLForKey(id target, NSString *key) {
	return RYGURLValue(RYGValueForKeyPathLike(target, key));
}

static id RYGFirstObjectIfArray(id value) {
	if ([value isKindOfClass:NSArray.class]) return [(NSArray *)value firstObject];
	return value;
}

static id RYGNestedObjectForKey(id target, NSString *key) {
	return RYGFirstObjectIfArray(RYGValueForKeyPathLike(target, key));
}

static NSString *RYGFieldString(id obj, NSString *key) {
	return RYGStringValue(RYGFieldValue(obj, key));
}

static NSString *RYGStringFromDictionary(id obj, NSString *key) {
	if (![obj isKindOfClass:NSDictionary.class]) return nil;
	return RYGStringValue(((NSDictionary *)obj)[key]);
}

static id RYGUserFromMedia(id media) {
	if (!media) return nil;

	for (NSString *key in RYGUserKeys()) {
		id user = RYGValueForKeyPathLike(media, key);
		if (user) return user;
	}

	for (NSString *key in RYGNestedKeys()) {
		id nested = RYGNestedObjectForKey(media, key);
		if (!nested || nested == media) continue;

		id user = RYGUserFromMedia(nested);
		if (user) return user;
	}

	return nil;
}

static NSString *RYGUsernameFromUser(id user) {
	if (!user) return nil;

	NSString *username = RYGStringForKey(user, @"username");
	if (username.length) return username;

	username = RYGFieldString(user, @"username");
	if (username.length) return username;

	return RYGStringFromDictionary(user, @"username");
}

static NSString *RYGUsernameFromMedia(id media) {
	if (!media) return nil;

	id user = RYGUserFromMedia(media);
	NSString *username = RYGUsernameFromUser(user);
	if (username.length) return username;

	for (NSString *key in RYGNestedKeys()) {
		id nested = RYGNestedObjectForKey(media, key);
		if (!nested || nested == media) continue;

		username = RYGUsernameFromMedia(nested);
		if (username.length) return username;
	}

	return nil;
}

static NSString *RYGRecursiveStringForKeys(id target, NSArray<NSString *> *keys, NSInteger depth) {
	if (!target || depth > 3) return nil;

	for (NSString *key in keys) {
		NSString *value = RYGStringForKey(target, key);
		if (value.length) return value;
	}

	for (NSString *key in RYGNestedKeys()) {
		id nested = RYGNestedObjectForKey(target, key);
		if (!nested || nested == target) continue;

		NSString *value = RYGRecursiveStringForKeys(nested, keys, depth + 1);
		if (value.length) return value;
	}

	return nil;
}

static NSURL *RYGRecursiveURLForKeys(id target, NSArray<NSString *> *keys, NSInteger depth) {
	if (!target || depth > 3) return nil;

	for (NSString *key in keys) {
		NSURL *url = RYGURLForKey(target, key);
		if (url) return url;
	}

	for (NSString *key in RYGNestedKeys()) {
		id nested = RYGNestedObjectForKey(target, key);
		if (!nested || nested == target) continue;

		NSURL *url = RYGRecursiveURLForKeys(nested, keys, depth + 1);
		if (url) return url;
	}

	return nil;
}

static NSString *RYGProfileURLStringForUsername(NSString *username) {
	if (!username.length) return nil;

	NSString *encoded = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
	return encoded.length ? [NSString stringWithFormat:@"instagram://user?username=%@", encoded] : nil;
}

static NSString *RYGMediaURLStringFromMetadata(RYGGallerySaveMetadata *metadata) {
	if (metadata.sourceMediaURLString.length) return metadata.sourceMediaURLString;

	if (metadata.sourceMediaCode.length) {
		NSString *type = metadata.source == RYGGallerySourceReels ? @"reel" : @"p";
		return [NSString stringWithFormat:@"https://www.instagram.com/%@/%@/", type, metadata.sourceMediaCode];
	}

	return nil;
}

static NSString *RYGMediaPKFromMedia(id media) {
	NSString *pk = RYGRecursiveStringForKeys(media, @[@"pk", @"id", @"mediaID", @"mediaId"], 0);
	if (pk.length) return pk;

	return RYGFieldString(media, @"pk") ?: RYGFieldString(media, @"id") ?: RYGFieldString(media, @"strong_id__");
}

static NSString *RYGMediaCodeFromMedia(id media) {
	NSString *code = RYGRecursiveStringForKeys(media, @[@"code", @"shortCode", @"shortcode", @"mediaCode", @"mediaShortcode", @"shortCodeToken"], 0);
	if (code.length) return code;

	return RYGFieldString(media, @"code") ?: RYGFieldString(media, @"shortcode");
}

static NSString *RYGUserPKFromUser(id user) {
	NSString *pk = RYGStringForKey(user, @"pk");
	if (pk.length) return pk;

	pk = RYGStringForKey(user, @"id");
	if (pk.length) return pk;

	return RYGFieldString(user, @"pk") ?: RYGFieldString(user, @"strong_id__") ?: RYGFieldString(user, @"id");
}

static NSURL *RYGProfileURLFromUser(id user, NSString *username) {
	for (NSString *key in @[@"profileURL", @"profileUrl", @"url"]) {
		NSURL *url = RYGURLForKey(user, key);
		if (url) return url;
	}

	NSString *fallback = RYGProfileURLStringForUsername(username);
	return fallback.length ? [NSURL URLWithString:fallback] : nil;
}

static NSURL *RYGMediaURLFromMedia(id media, RYGGallerySaveMetadata *metadata) {
	NSURL *url = RYGRecursiveURLForKeys(media, @[
		@"permalink", @"permaLink", @"shareURL", @"shareUrl",
		@"canonicalURL", @"canonicalUrl", @"permalinkURL",
		@"instagramURL", @"instagramUrl", @"webURL", @"webUrl"
	], 0);

	if (url) return url;

	NSString *generated = RYGMediaURLStringFromMetadata(metadata);
	return generated.length ? [NSURL URLWithString:generated] : nil;
}

@implementation RYGGalleryOriginController

+ (void)populateProfileMetadata:(RYGGallerySaveMetadata *)metadata username:(NSString *)username user:(id)user {
	if (!metadata) return;

	if (username.length) {
		metadata.sourceUsername = username;
		if (!metadata.sourceProfileURLString.length) {
			metadata.sourceProfileURLString = RYGProfileURLStringForUsername(username);
		}
	}

	NSString *userPK = RYGUserPKFromUser(user);
	if (userPK.length) metadata.sourceUserPK = userPK;

	NSURL *profileURL = RYGProfileURLFromUser(user, username);
	if (profileURL) metadata.sourceProfileURLString = profileURL.absoluteString;
}

+ (void)populateMetadata:(RYGGallerySaveMetadata *)metadata fromMedia:(id)media {
	if (!metadata || !media) return;

	id user = RYGUserFromMedia(media);
	NSString *username = RYGUsernameFromMedia(media);

	[self populateProfileMetadata:metadata username:username user:user];

	NSString *mediaPK = RYGMediaPKFromMedia(media);
	if (mediaPK.length) metadata.sourceMediaPK = mediaPK;

	NSString *mediaCode = RYGMediaCodeFromMedia(media);
	if (mediaCode.length) metadata.sourceMediaCode = mediaCode;

	NSURL *mediaURL = RYGMediaURLFromMedia(media, metadata);
	if (mediaURL) metadata.sourceMediaURLString = mediaURL.absoluteString;
}

+ (BOOL)openOriginalPostForGalleryFile:(RYGGalleryFile *)file {
	NSURL *url = file.preferredOriginalMediaURL;
	return url ? [RYGURLOpener openURL:url] : NO;
}

@end