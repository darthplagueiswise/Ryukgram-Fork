// Increase IG CDN media variant by spoofing iPad Pro 12.9" dimensions/scale
// in the outgoing User-Agent.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static NSString *SCIHighResUserAgentString(NSString *userAgent) {
	if (![userAgent isKindOfClass:NSString.class] || !userAgent.length) return userAgent;

	static NSRegularExpression *dimensionRegex;
	static NSRegularExpression *scaleRegex;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		dimensionRegex = [NSRegularExpression regularExpressionWithPattern:@"\\b\\d{3,4}x\\d{3,4}\\b" options:0 error:nil];
		scaleRegex = [NSRegularExpression regularExpressionWithPattern:@"scale=\\d+(\\.\\d+)?" options:0 error:nil];
	});

	NSString *out = [dimensionRegex stringByReplacingMatchesInString:userAgent
															 options:0
															   range:NSMakeRange(0, userAgent.length)
														withTemplate:@"2064x2752"];

	out = [scaleRegex stringByReplacingMatchesInString:out
											   options:0
												 range:NSMakeRange(0, out.length)
										  withTemplate:@"scale=3.00"];

	return out;
}

static NSString *SCIHighResHeaderValue(NSString *value, NSString *field) {
	if (![field isKindOfClass:NSString.class] || [field caseInsensitiveCompare:@"User-Agent"] != NSOrderedSame) return value;
	return SCIHighResUserAgentString(value);
}

%group SCIEnhancedMediaResolutionGroup

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
	%orig(SCIHighResHeaderValue(value, field), field);
}

- (void)setAllHTTPHeaderFields:(NSDictionary *)headerFields {
	if (![headerFields isKindOfClass:NSDictionary.class] || !headerFields.count) {
		%orig(headerFields);
		return;
	}

	NSMutableDictionary *headers = [headerFields mutableCopy];

	for (NSString *key in headerFields) {
		if (![key isKindOfClass:NSString.class] || [key caseInsensitiveCompare:@"User-Agent"] != NSOrderedSame) continue;

		NSString *value = headerFields[key];
		if ([value isKindOfClass:NSString.class]) {
			headers[key] = SCIHighResUserAgentString(value);
		}
		break;
	}

	%orig(headers);
}

%end

%hook IGURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
	%orig(SCIHighResHeaderValue(value, field), field);
}

%end

%end

%ctor {
	if ([SCIUtils getBoolPref:@"enhanced_media_resolution"]) {
		%init(SCIEnhancedMediaResolutionGroup);
	}
}
