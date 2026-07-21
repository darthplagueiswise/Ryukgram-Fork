#import "SCIIdNameMappingInstaller.h"
#import "../../Localization/SCILocalization.h"
#import "../../SCIFileLog.h"

static NSString *const kSCIMappingResourceName = @"id_name_mapping_ig439_verified";

static NSArray<NSString *> *SCIIdNameMappingPaths(void) {
	NSString *home = NSHomeDirectory();
	if (!home.length) return @[];
	// Android 439's MobileConfigFactoryImpl checks the factory base first and
	// then base/mobileconfig. FBSharedFramework on iOS contains the same file
	// contract; writing both locations keeps the loader path native and avoids an
	// invented HTTP downloader.
	return @[
		[home stringByAppendingPathComponent:@"id_name_mapping.json"],
		[home stringByAppendingPathComponent:@"mobileconfig/id_name_mapping.json"],
	];
}

static NSArray<NSString *> *SCIParseMappingData(NSData *data, NSError **error) {
	if (!data.length) {
		if (error) *error = [NSError errorWithDomain:@"SCIIdNameMapping" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"mapping data is empty"}];
		return nil;
	}
	id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
	if (![object isKindOfClass:NSArray.class]) {
		if (error && !*error) *error = [NSError errorWithDomain:@"SCIIdNameMapping" code:2
			userInfo:@{NSLocalizedDescriptionKey: @"top-level JSON is not an array"}];
		return nil;
	}
	NSArray *array = object;
	if (!array.count) {
		if (error) *error = [NSError errorWithDomain:@"SCIIdNameMapping" code:3
			userInfo:@{NSLocalizedDescriptionKey: @"mapping array is empty"}];
		return nil;
	}
	for (id value in array) {
		if (![value isKindOfClass:NSString.class]) {
			if (error) *error = [NSError errorWithDomain:@"SCIIdNameMapping" code:4
				userInfo:@{NSLocalizedDescriptionKey: @"mapping contains a non-string entry"}];
			return nil;
		}
		NSArray<NSString *> *parts = [(NSString *)value componentsSeparatedByString:@":"];
		if (parts.count < 4 || (parts.count % 2) != 0 || [parts.firstObject longLongValue] <= 0) {
			if (error) *error = [NSError errorWithDomain:@"SCIIdNameMapping" code:5
				userInfo:@{NSLocalizedDescriptionKey: @"mapping contains a malformed colon-delimited entry"}];
			return nil;
		}
	}
	return array;
}

static NSData *SCIBundledMappingData(NSError **error, NSUInteger *count) {
	NSBundle *bundle = SCILocalizationBundle();
	NSURL *url = [bundle URLForResource:kSCIMappingResourceName withExtension:@"json"];
	if (!url) {
		if (error) *error = [NSError errorWithDomain:@"SCIIdNameMapping" code:6
			userInfo:@{NSLocalizedDescriptionKey: @"RyukGram.bundle does not contain the verified IG439 mapping"}];
		return nil;
	}
	NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
	NSArray *array = data ? SCIParseMappingData(data, error) : nil;
	if (!array) return nil;
	if (count) *count = array.count;
	return data;
}

static BOOL SCIExistingMappingIsValid(NSString *path, NSUInteger *count) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	NSError *error = nil;
	NSArray *array = data ? SCIParseMappingData(data, &error) : nil;
	if (count) *count = array.count;
	return array != nil;
}

NSString *SCIInstallBundledIDNameMapping(BOOL overwrite) {
	NSError *error = nil;
	NSUInteger bundledCount = 0;
	NSData *data = SCIBundledMappingData(&error, &bundledCount);
	if (!data) return [NSString stringWithFormat:@"Bundled mapping unavailable: %@", error.localizedDescription ?: @"unknown error"];

	NSFileManager *fm = NSFileManager.defaultManager;
	NSUInteger written = 0;
	NSUInteger preserved = 0;
	NSMutableArray<NSString *> *failures = [NSMutableArray array];

	for (NSString *path in SCIIdNameMappingPaths()) {
		NSUInteger existingCount = 0;
		if (!overwrite && SCIExistingMappingIsValid(path, &existingCount)) {
			preserved++;
			continue;
		}
		NSString *directory = path.stringByDeletingLastPathComponent;
		if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
			[failures addObject:[NSString stringWithFormat:@"%@: %@", path, error.localizedDescription ?: @"mkdir failed"]];
			continue;
		}
		error = nil;
		if ([data writeToFile:path options:NSDataWritingAtomic error:&error]) {
			written++;
		} else {
			[failures addObject:[NSString stringWithFormat:@"%@: %@", path, error.localizedDescription ?: @"write failed"]];
		}
	}

	NSString *result = [NSString stringWithFormat:@"Verified IG439 mapping: %lu entries. Written: %lu. Preserved: %lu.%@",
		(unsigned long)bundledCount, (unsigned long)written, (unsigned long)preserved,
		failures.count ? [NSString stringWithFormat:@" Failures: %@", [failures componentsJoinedByString:@" | "]] : @" Restart Instagram so the native MobileConfig factory reconstructs with these names."];
	if (SCIFileLogIsEnabled()) SCIFLog(@"SCIIdNameMapping", @"%@", result);
	return result;
}

NSString *SCIIdNameMappingStatus(void) {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	for (NSString *path in SCIIdNameMappingPaths()) {
		NSUInteger count = 0;
		BOOL valid = SCIExistingMappingIsValid(path, &count);
		[parts addObject:[NSString stringWithFormat:@"%@ — %@%lu entries",
			path, valid ? @"valid, " : @"missing/invalid, ", (unsigned long)count]];
	}
	return parts.count ? [parts componentsJoinedByString:@"\n"] : @"No writable MobileConfig base path was resolved.";
}

__attribute__((constructor)) static void SCIIdNameMappingEarlyInstall(void) {
	@autoreleasepool {
		// Preserve a user-supplied valid mapping; only seed absent or malformed
		// paths. This runs when the tweak dylib loads, before session construction.
		(void)SCIInstallBundledIDNameMapping(NO);
	}
}
