#import "SCIIdNameMappingInstaller.h"
#import "../../Localization/SCILocalization.h"
#import "../../SCIFileLog.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kSCIMappingResourceName = @"id_name_mapping_ig439_verified";
static NSString *const kSCIStableMappingURL = @"https://raw.githubusercontent.com/darthplagueiswise/Ryukgram-Fork/experimental3/src/BundleAssets/id_name_mapping_ig439_verified.bin";
static NSString *const kSCIPreviewMappingURL = @"https://raw.githubusercontent.com/darthplagueiswise/Ryukgram-Fork/agent/fix-employee-gate-mapping/src/BundleAssets/id_name_mapping_ig439_verified.bin";

static NSArray<NSString *> *SCIIdNameMappingBaseDirectories(void) {
	NSMutableOrderedSet<NSString *> *roots = [NSMutableOrderedSet orderedSet];
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *home = NSHomeDirectory();
	if (home.length) [roots addObject:home];

	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	if (documents.length) [roots addObject:documents];

	NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	if (support.length) [roots addObject:support];

	// Instagram normally obtains MobileConfig storage from an application-group
	// container. Sideload builds may redirect that call to Documents. Resolve all
	// groups at runtime instead of hard-coding a signing-team-specific identifier.
	Class proxyClass = objc_getClass("LSBundleProxy");
	SEL currentProcessSEL = sel_registerName("bundleProxyForCurrentProcess");
	SEL entitlementsSEL = sel_registerName("entitlements");
	SEL groupURLsSEL = sel_registerName("groupContainerURLs");
	if (proxyClass && [proxyClass respondsToSelector:currentProcessSEL]) {
		id proxy = ((id (*)(id, SEL))objc_msgSend)((id)proxyClass, currentProcessSEL);
		NSDictionary *entitlements = nil;
		NSDictionary *groupURLs = nil;
		if (proxy && [proxy respondsToSelector:entitlementsSEL]) {
			entitlements = ((id (*)(id, SEL))objc_msgSend)(proxy, entitlementsSEL);
		}
		if (proxy && [proxy respondsToSelector:groupURLsSEL]) {
			groupURLs = ((id (*)(id, SEL))objc_msgSend)(proxy, groupURLsSEL);
		}
		NSArray *groups = [entitlements isKindOfClass:NSDictionary.class]
			? entitlements[@"com.apple.security.application-groups"] : nil;
		for (NSString *group in [groups isKindOfClass:NSArray.class] ? groups : @[]) {
			if (![group isKindOfClass:NSString.class] || !group.length) continue;
			NSURL *containerURL = [groupURLs isKindOfClass:NSDictionary.class] ? groupURLs[group] : nil;
			if (![containerURL isKindOfClass:NSURL.class]) {
				containerURL = [fm containerURLForSecurityApplicationGroupIdentifier:group];
			}
			NSString *root = containerURL.path;
			if (!root.length) continue;
			[roots addObject:root];
			[roots addObject:[root stringByAppendingPathComponent:@"Documents"]];
		}
	}
	return roots.array;
}

static NSArray<NSString *> *SCIIdNameMappingPaths(void) {
	NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
	for (NSString *base in SCIIdNameMappingBaseDirectories()) {
		[paths addObject:[base stringByAppendingPathComponent:@"id_name_mapping.json"]];
		[paths addObject:[base stringByAppendingPathComponent:@"mobileconfig/id_name_mapping.json"]];
	}
	return paths.array;
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
	// build.sh already packages generic .bin assets. The bytes remain JSON; the
	// extension only keeps all existing bundle-copy paths unchanged.
	NSURL *url = [bundle URLForResource:kSCIMappingResourceName withExtension:@"bin"];
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

static NSString *SCIWriteIDNameMappingData(NSData *data, BOOL overwrite, NSString *source) {
	NSError *validationError = nil;
	NSArray *mapping = SCIParseMappingData(data, &validationError);
	if (!mapping) {
		return [NSString stringWithFormat:@"Rejected %@ mapping: %@", source ?: @"unknown", validationError.localizedDescription ?: @"invalid JSON"];
	}

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
		NSError *error = nil;
		if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
			[failures addObject:[NSString stringWithFormat:@"%@: %@", path, error.localizedDescription ?: @"mkdir failed"]];
			continue;
		}
		if ([data writeToFile:path options:NSDataWritingAtomic error:&error]) {
			written++;
		} else {
			[failures addObject:[NSString stringWithFormat:@"%@: %@", path, error.localizedDescription ?: @"write failed"]];
		}
	}

	NSString *suffix = failures.count
		? [NSString stringWithFormat:@" Failures: %@", [failures componentsJoinedByString:@" | "]]
		: @" Restart Instagram so the native MobileConfig factory reconstructs with these names.";
	NSString *result = [NSString stringWithFormat:@"%@ mapping: %lu entries. Written: %lu. Preserved: %lu.%@",
		source ?: @"ID-name", (unsigned long)mapping.count, (unsigned long)written,
		(unsigned long)preserved, suffix];
	if (SCIFileLogIsEnabled()) SCIFLog(@"SCIIdNameMapping", @"%@", result);
	return result;
}

NSString *SCIInstallBundledIDNameMapping(BOOL overwrite) {
	NSError *error = nil;
	NSUInteger count = 0;
	NSData *data = SCIBundledMappingData(&error, &count);
	if (!data) return [NSString stringWithFormat:@"Bundled mapping unavailable: %@", error.localizedDescription ?: @"unknown error"];
	return SCIWriteIDNameMappingData(data, overwrite, @"Bundled IG439");
}

static void SCICompleteMappingDownload(void (^completion)(NSString *), NSString *result) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (completion) completion(result ?: @"Unknown mapping result");
	});
}

static void SCIDownloadMappingCandidate(NSArray<NSString *> *urls, NSUInteger index,
	void (^completion)(NSString *)) {
	if (index >= urls.count) {
		SCICompleteMappingDownload(completion,
			@"No version-pinned mapping endpoint returned a valid JSON array. The bundled verified mapping remains available.");
		return;
	}
	NSURL *url = [NSURL URLWithString:urls[index]];
	if (!url) {
		SCIDownloadMappingCandidate(urls, index + 1, completion);
		return;
	}
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0];
	request.HTTPMethod = @"GET";
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
		completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
				? ((NSHTTPURLResponse *)response).statusCode : 0;
			NSError *validationError = nil;
			NSArray *mapping = (!error && status == 200 && data.length)
				? SCIParseMappingData(data, &validationError) : nil;
			if (!mapping) {
				SCIDownloadMappingCandidate(urls, index + 1, completion);
				return;
			}
			NSString *result = SCIWriteIDNameMappingData(data, YES, @"Downloaded IG439");
			SCICompleteMappingDownload(completion, result);
		}];
	[task resume];
}

void SCIForceDownloadIDNameMapping(void (^completion)(NSString *result)) {
	SCIDownloadMappingCandidate(@[kSCIStableMappingURL, kSCIPreviewMappingURL], 0, completion);
}

NSString *SCIIdNameMappingStatus(void) {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	for (NSString *path in SCIIdNameMappingPaths()) {
		NSUInteger count = 0;
		BOOL valid = SCIExistingMappingIsValid(path, &count);
		if (valid) {
			[parts addObject:[NSString stringWithFormat:@"%@ — valid, %lu entries", path, (unsigned long)count]];
		}
	}
	if (parts.count) return [parts componentsJoinedByString:@"\n"];
	return @"No valid id_name_mapping.json is visible in the app, Documents, Application Support, or resolved application-group MobileConfig roots.";
}

__attribute__((constructor)) static void SCIIdNameMappingEarlyInstall(void) {
	@autoreleasepool {
		// Disk only: never perform network I/O during launch. Preserve a valid user
		// mapping and seed only absent/malformed locations before session creation.
		(void)SCIInstallBundledIDNameMapping(NO);
	}
}
