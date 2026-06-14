#import "SCIDateFormatTemplate.h"
#import "../../Utils.h"

static NSString *const kCustomListKey = @"feed_date_custom_templates";

NSArray<NSArray<NSString *> *> *SCIDateFormatTemplateTokens(void) {
	static NSArray *tokens = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		tokens = @[
			@[@"{DD}", @"dd"],
			@[@"{D}", @"d"],
			@[@"{MM}", @"MM"],
			@[@"{M}", @"M"],
			@[@"{MMM}", @"MMM"],
			@[@"{MMMM}", @"MMMM"],
			@[@"{YYYY}", @"yyyy"],
			@[@"{YY}", @"yy"],
			@[@"{HH}", @"HH"],
			@[@"{hh}", @"hh"],
			@[@"{h}", @"h"],
			@[@"{mm}", @"mm"],
			@[@"{ss}", @"ss"],
			@[@"{AMPM}", @"a"],
			@[@"{WD}", @"EEEE"],
			@[@"{WDS}", @"EEE"],
		];
	});
	return tokens;
}

static NSDictionary<NSString *, NSString *> *sciTokenMap(void) {
	static NSDictionary *map = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *m = NSMutableDictionary.dictionary;
		for (NSArray *t in SCIDateFormatTemplateTokens()) m[t[0]] = t[1];
		map = m.copy;
	});
	return map;
}

static void sciFlushLiteral(NSMutableString *pattern, NSMutableString *literal) {
	if (!literal.length) return;
	[pattern appendString:@"'"];
	[pattern appendString:[literal stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
	[pattern appendString:@"'"];
	[literal setString:@""];
}

NSString *SCIDateFormatPatternFromTemplate(NSString *tpl) {
	if (!tpl.length) return nil;

	NSDictionary *map = sciTokenMap();
	NSMutableString *pattern = NSMutableString.string;
	NSMutableString *literal = NSMutableString.string;
	NSUInteger i = 0, len = tpl.length;

	while (i < len) {
		unichar c = [tpl characterAtIndex:i];

		if (c == '{') {
			NSRange close = [tpl rangeOfString:@"}" options:0 range:NSMakeRange(i, len - i)];
			if (close.location != NSNotFound) {
				NSString *field = map[[tpl substringWithRange:NSMakeRange(i, close.location - i + 1)]];
				if (field) {
					sciFlushLiteral(pattern, literal);
					[pattern appendString:field];
					i = close.location + 1;
					continue;
				}
			}
		}

		[literal appendFormat:@"%C", c];
		i++;
	}

	sciFlushLiteral(pattern, literal);

	return pattern.length ? pattern.copy : nil;
}

#pragma mark - Custom template store

static NSArray<NSDictionary *> *sciParseCustomList(NSString *json) {
	if (!json.length) return @[];

	NSArray *arr = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
												   options:0
													 error:nil];
	if (![arr isKindOfClass:NSArray.class]) return @[];

	NSMutableArray *out = NSMutableArray.array;
	for (id entry in arr) {
		if (![entry isKindOfClass:NSDictionary.class]) continue;
		if (![entry[@"id"] isKindOfClass:NSString.class] || ![entry[@"tpl"] isKindOfClass:NSString.class]) continue;
		[out addObject:@{@"id": entry[@"id"], @"tpl": entry[@"tpl"]}];
	}
	return out.copy;
}

NSArray<NSDictionary<NSString *, NSString *> *> *SCIDateFormatCustomList(void) {
	// Hot path (every visible timestamp) — reparse only when the JSON changes.
	static NSString *lastJSON = nil;
	static NSArray *lastList = nil;
	static NSObject *lock = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ lock = NSObject.new; });

	NSString *json = [SCIUtils getStringPref:kCustomListKey] ?: @"";

	@synchronized (lock) {
		if (lastJSON && [json isEqualToString:lastJSON]) return lastList;
		lastList = sciParseCustomList(json);
		lastJSON = json.copy;
		return lastList;
	}
}

void SCIDateFormatCustomSaveList(NSArray<NSDictionary<NSString *, NSString *> *> *list) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:(list ?: @[]) options:0 error:nil];
	NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
	[NSUserDefaults.standardUserDefaults setObject:(json ?: @"") forKey:kCustomListKey];
}

NSString *SCIDateFormatCustomTemplateForKey(NSString *fmtKey) {
	if (![fmtKey hasPrefix:@"custom:"]) return nil;
	NSString *uid = [fmtKey substringFromIndex:7];

	for (NSDictionary *entry in SCIDateFormatCustomList()) {
		if ([entry[@"id"] isEqualToString:uid]) return entry[@"tpl"];
	}
	return nil;
}
