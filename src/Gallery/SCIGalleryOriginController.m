#import "SCIGalleryOriginController.h"
#import "SCIGalleryFile.h"
#import "SCIGallerySaveMetadata.h"
#import "../Utils.h"
#import "../SCIURLOpener.h"
#import "SCIGalleryShim.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSArray<NSString *> *SCIUserKeys(void) {
	static NSArray *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[@"user", @"owner", @"author", @"creator", @"actor", @"profileUser"];
	});
	return keys;
}

static NSArray<NSString *> *SCINestedKeys(void) {
	static NSArray *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[@"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post"];
	});
	return keys;
}

static id SCIObjectForSelector(id target, NSString *name) {
	if (!target || !name.length) return nil;

	SEL sel = NSSelectorFromString(name);
	if (![target respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(target, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static id SCIKVCObject(id target, NSString *key) {
	if (!target || !key.length) return nil;

	@try {
		return [target valueForKey:key];
	} @catch (__unused id e) {
		return nil;
	}
}

static id SCIFieldValue(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	return [SCIUtils fieldCacheValue:obj forKey:key];
}

static id SCIValueForKeyPathLike(id target, NSString *key) {
	if (!target || !key.length) return nil;

	id value = SCIObjectForSelector(target, key);
	if (!value) value = SCIKVCObject(target, key);
	if (!value) value = SCIFieldValue(target, key);

	return value;
}

static NSString *SCIStringValue(id value) {
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

static NSString *SCIStringForKey(id target, NSString *key) {
	return SCIStringValue(SCIValueForKeyPathLike(target, key));
}

static NSURL *SCIURLValue(id value) {
	if ([value isKindOfClass:NSURL.class]) return value;

	if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) {
		return [NSURL URLWithString:(NSString *)value];
	}

	return nil;
}

static NSURL *SCIURLForKey(id target, NSString *key) {
	return SCIURLValue(SCIValueForKeyPathLike(target, key));
}

static id SCIFirstObjectIfArray(id value) {
	if ([value isKindOfClass:NSArray.class]) return [(NSArray *)value firstObject];
	return value;
}

static id SCINestedObjectForKey(id target, NSString *key) {
	return SCIFirstObjectIfArray(SCIValueForKeyPathLike(target, key));
}

static NSString *SCIFieldString(id obj, NSString *key) {
	return SCIStringValue(SCIFieldValue(obj, key));
}

static NSString *SCIStringFromDictionary(id obj, NSString *key) {
	if (![obj isKindOfClass:NSDictionary.class]) return nil;
	return SCIStringValue(((NSDictionary *)obj)[key]);
}

static id SCIUserFromMedia(id media) {
	if (!media) return nil;

	for (NSString *key in SCIUserKeys()) {
		id user = SCIValueForKeyPathLike(media, key);
		if (user) return user;
	}

	for (NSString *key in SCINestedKeys()) {
		id nested = SCINestedObjectForKey(media, key);
		if (!nested || nested == media) continue;

		id user = SCIUserFromMedia(nested);
		if (user) return user;
	}

	return nil;
}

static NSString *SCIUsernameFromUser(id user) {
	if (!user) return nil;

	NSString *username = SCIStringForKey(user, @"username");
	if (username.length) return username;

	username = SCIFieldString(user, @"username");
	if (username.length) return username;

	return SCIStringFromDictionary(user, @"username");
}

static NSString *SCIUsernameFromMedia(id media) {
	if (!media) return nil;

	id user = SCIUserFromMedia(media);
	NSString *username = SCIUsernameFromUser(user);
	if (username.length) return username;

	for (NSString *key in SCINestedKeys()) {
		id nested = SCINestedObjectForKey(media, key);
		if (!nested || nested == media) continue;

		username = SCIUsernameFromMedia(nested);
		if (username.length) return username;
	}

	return nil;
}

static NSString *SCIRecursiveStringForKeys(id target, NSArray<NSString *> *keys, NSInteger depth) {
	if (!target || depth > 3) return nil;

	for (NSString *key in keys) {
		NSString *value = SCIStringForKey(target, key);
		if (value.length) return value;
	}

	for (NSString *key in SCINestedKeys()) {
		id nested = SCINestedObjectForKey(target, key);
		if (!nested || nested == target) continue;

		NSString *value = SCIRecursiveStringForKeys(nested, keys, depth + 1);
		if (value.length) return value;
	}

	return nil;
}

static NSURL *SCIRecursiveURLForKeys(id target, NSArray<NSString *> *keys, NSInteger depth) {
	if (!target || depth > 3) return nil;

	for (NSString *key in keys) {
		NSURL *url = SCIURLForKey(target, key);
		if (url) return url;
	}

	for (NSString *key in SCINestedKeys()) {
		id nested = SCINestedObjectForKey(target, key);
		if (!nested || nested == target) continue;

		NSURL *url = SCIRecursiveURLForKeys(nested, keys, depth + 1);
		if (url) return url;
	}

	return nil;
}

static NSString *SCIProfileURLStringForUsername(NSString *username) {
	if (!username.length) return nil;

	NSString *encoded = [username stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
	return encoded.length ? [NSString stringWithFormat:@"instagram://user?username=%@", encoded] : nil;
}

static NSString *SCIMediaURLStringFromMetadata(SCIGallerySaveMetadata *metadata) {
	if (metadata.sourceMediaURLString.length) return metadata.sourceMediaURLString;

	if (metadata.sourceMediaCode.length) {
		NSString *type = metadata.source == SCIGallerySourceReels ? @"reel" : @"p";
		return [NSString stringWithFormat:@"https://www.instagram.com/%@/%@/", type, metadata.sourceMediaCode];
	}

	return nil;
}

static NSString *SCIMediaPKFromMedia(id media) {
	NSString *pk = SCIRecursiveStringForKeys(media, @[@"pk", @"id", @"mediaID", @"mediaId"], 0);
	if (pk.length) return pk;

	return SCIFieldString(media, @"pk") ?: SCIFieldString(media, @"id") ?: SCIFieldString(media, @"strong_id__");
}

static NSString *SCIMediaCodeFromMedia(id media) {
	NSString *code = SCIRecursiveStringForKeys(media, @[@"code", @"shortCode", @"shortcode", @"mediaCode", @"mediaShortcode", @"shortCodeToken"], 0);
	if (code.length) return code;

	return SCIFieldString(media, @"code") ?: SCIFieldString(media, @"shortcode");
}

static NSString *SCIUserPKFromUser(id user) {
	NSString *pk = SCIStringForKey(user, @"pk");
	if (pk.length) return pk;

	pk = SCIStringForKey(user, @"id");
	if (pk.length) return pk;

	return SCIFieldString(user, @"pk") ?: SCIFieldString(user, @"strong_id__") ?: SCIFieldString(user, @"id");
}

static NSURL *SCIProfileURLFromUser(id user, NSString *username) {
	for (NSString *key in @[@"profileURL", @"profileUrl", @"url"]) {
		NSURL *url = SCIURLForKey(user, key);
		if (url) return url;
	}

	NSString *fallback = SCIProfileURLStringForUsername(username);
	return fallback.length ? [NSURL URLWithString:fallback] : nil;
}

static NSURL *SCIMediaURLFromMedia(id media, SCIGallerySaveMetadata *metadata) {
	NSURL *url = SCIRecursiveURLForKeys(media, @[
		@"permalink", @"permaLink", @"shareURL", @"shareUrl",
		@"canonicalURL", @"canonicalUrl", @"permalinkURL",
		@"instagramURL", @"instagramUrl", @"webURL", @"webUrl"
	], 0);

	if (url) return url;

	NSString *generated = SCIMediaURLStringFromMetadata(metadata);
	return generated.length ? [NSURL URLWithString:generated] : nil;
}

@implementation SCIGalleryOriginController

+ (void)populateProfileMetadata:(SCIGallerySaveMetadata *)metadata username:(NSString *)username user:(id)user {
	if (!metadata) return;

	if (username.length) {
		metadata.sourceUsername = username;
		if (!metadata.sourceProfileURLString.length) {
			metadata.sourceProfileURLString = SCIProfileURLStringForUsername(username);
		}
	}

	NSString *userPK = SCIUserPKFromUser(user);
	if (userPK.length) metadata.sourceUserPK = userPK;

	NSURL *profileURL = SCIProfileURLFromUser(user, username);
	if (profileURL) metadata.sourceProfileURLString = profileURL.absoluteString;
}

+ (void)populateMetadata:(SCIGallerySaveMetadata *)metadata fromMedia:(id)media {
	if (!metadata || !media) return;

	id user = SCIUserFromMedia(media);
	NSString *username = SCIUsernameFromMedia(media);

	[self populateProfileMetadata:metadata username:username user:user];

	NSString *mediaPK = SCIMediaPKFromMedia(media);
	if (mediaPK.length) metadata.sourceMediaPK = mediaPK;

	NSString *mediaCode = SCIMediaCodeFromMedia(media);
	if (mediaCode.length) metadata.sourceMediaCode = mediaCode;

	NSURL *mediaURL = SCIMediaURLFromMedia(media, metadata);
	if (mediaURL) metadata.sourceMediaURLString = mediaURL.absoluteString;
}

+ (BOOL)openOriginalPostForGalleryFile:(SCIGalleryFile *)file {
	NSURL *url = file.preferredOriginalMediaURL;
	return url ? [SCIURLOpener openURL:url] : NO;
}

+ (BOOL)openProfileForGalleryFile:(SCIGalleryFile *)file {
	if (file.sourceUsername.length) {
		return [SCIURLOpener openInstagramProfileForUsername:file.sourceUsername];
	}

	NSURL *url = file.preferredProfileURL;
	return url ? [SCIURLOpener openURL:url] : NO;
}

@end