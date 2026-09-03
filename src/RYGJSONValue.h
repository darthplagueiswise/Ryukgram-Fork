// Typed reads for stored JSON. Old files and IG payloads carry values that throw when messaged.

#import <Foundation/Foundation.h>

// NSNumber and NSString both answer -xxxValue, so both pass through.
static inline id RYGJSONScalar(id value) {
	return ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) ? value : nil;
}

static inline NSString *RYGJSONString(id value) {
	return [value isKindOfClass:NSString.class] ? value : nil;
}

static inline NSDictionary *RYGJSONDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static inline NSArray *RYGJSONArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : nil;
}
