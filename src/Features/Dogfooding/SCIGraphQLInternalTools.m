#import "SCIGraphQLInternalTools.h"
#import "../../SCIDefaults.h"
#import "../../Utils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

#define GQLLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] GraphQLTools " fmt, ##__VA_ARGS__)

static NSString *const kSCIE2EBypassKey = @"sci_force_e2e_bypass";

void SCIRegisterGraphQLInternalDefaults(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// Populate the canonical registered-defaults dictionary first, then merge
		// this module's key into that same dictionary used by backup/export.
		SCIRegisterDefaultsOnce();
		NSDictionary *extra = @{ kSCIE2EBypassKey: @(NO) };
		[NSUserDefaults.standardUserDefaults registerDefaults:extra];

		NSMutableDictionary *registered =
			[[SCIUtils sciRegisteredDefaults] mutableCopy] ?: [NSMutableDictionary dictionary];
		[registered addEntriesFromDictionary:extra];
		[SCIUtils setSciRegisteredDefaults:registered.copy];
	});
}

__attribute__((constructor))
static void SCIGraphQLInternalDefaultsCtor(void) {
	@autoreleasepool {
		SCIRegisterGraphQLInternalDefaults();
	}
}

static BOOL SCITypeEncodingMatches(Method method, const char *expected) {
	if (!method || !expected) return NO;
	const char *encoding = method_getTypeEncoding(method);
	return encoding && strcmp(encoding, expected) == 0;
}

static Class SCIFOAOverrideClass(void) {
	return objc_getClass("_TtC26FOAPlatformSandboxOverride18FOASandboxOverride")
		?: objc_getClass("FOASandboxOverride");
}

static Class SCIGraphQLProviderClass(void) {
	return objc_getClass(
		"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider"
	) ?: objc_getClass("IGDirectDeidentifiedRequestProvider");
}

static NSString *SCITruncatedDescription(id object, NSUInteger limit) {
	if (!object) return @"nil";
	NSString *description = nil;
	@try {
		description = [object description];
	} @catch (__unused id exception) {
		description = nil;
	}
	if (!description.length) {
		description = NSStringFromClass([object class]) ?: @"unknown object";
	}
	if (description.length <= limit) return description;
	return [[description substringToIndex:limit] stringByAppendingString:@"…"];
}

static NSString *SCIRedactedCredentialSummary(NSString *label, id object) {
	if (!object) return [NSString stringWithFormat:@"%@: nil", label];
	NSString *className = NSStringFromClass([object class]) ?: @"unknown";
	return [NSString stringWithFormat:@"%@: received (%@, contents redacted)", label, className];
}

static void SCIDeliver(SCIGraphQLInternalToolsCompletion completion, NSString *message) {
	if (!completion) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(message ?: @"No result");
	});
}

@implementation SCIGraphQLInternalTools

+ (NSString *)currentFOASandboxOverride {
	Class cls = SCIFOAOverrideClass();
	if (!cls) return @"FOASandboxOverride class not found in this build";

	SEL selector = NSSelectorFromString(@"currentOverride");
	Method method = class_getClassMethod(cls, selector);
	if (!SCITypeEncodingMatches(method, "@16@0:8")) {
		return method
			? [NSString stringWithFormat:@"currentOverride ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"FOASandboxOverride.currentOverride not found";
	}

	@try {
		id current = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
		if (!current) return @"No FOA sandbox override is active";
		return [NSString stringWithFormat:@"Current override (%@):\n%@",
			NSStringFromClass([current class]) ?: @"unknown",
			SCITruncatedDescription(current, 1600)];
	} @catch (id exception) {
		return [NSString stringWithFormat:@"currentOverride threw: %@",
			SCITruncatedDescription(exception, 800)];
	}
}

+ (NSString *)setFOASandboxHostname:(NSString *)hostname reason:(NSString *)reason {
	NSString *trimmed = [hostname stringByTrimmingCharactersInSet:
		NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!trimmed.length) return @"Hostname is empty";
	if ([trimmed containsString:@"://"] ||
		[trimmed containsString:@"/"] ||
		[trimmed containsString:@"?"] ||
		[trimmed containsString:@"#"]) {
		return @"Enter only a hostname, without scheme, path, query or fragment";
	}

	Class cls = SCIFOAOverrideClass();
	if (!cls) return @"FOASandboxOverride class not found in this build";

	SEL selector = NSSelectorFromString(@"setSandboxOverrideWithHostname:reason:");
	Method method = class_getClassMethod(cls, selector);
	if (!SCITypeEncodingMatches(method, "v32@0:8@16@24")) {
		return method
			? [NSString stringWithFormat:@"setSandboxOverride ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"FOASandboxOverride setter not found";
	}

	NSString *effectiveReason = reason.length ? reason : @"RyukGram Dev";
	@try {
		((void (*)(id, SEL, id, id))objc_msgSend)(
			cls, selector, trimmed, effectiveReason
		);
		GQLLOG("FOA sandbox override set to %{public}@", trimmed);
		return [NSString stringWithFormat:
			@"FOA sandbox override set to %@.\nRestart Instagram so every GraphQL surface rebuilds its environment.",
			trimmed];
	} @catch (id exception) {
		return [NSString stringWithFormat:@"setSandboxOverride threw: %@",
			SCITruncatedDescription(exception, 800)];
	}
}

+ (NSString *)resetFOASandboxOverride {
	Class cls = SCIFOAOverrideClass();
	if (!cls) return @"FOASandboxOverride class not found in this build";

	SEL selector = NSSelectorFromString(@"setSandboxOverrideWithHostname:reason:");
	Method method = class_getClassMethod(cls, selector);
	if (!SCITypeEncodingMatches(method, "v32@0:8@16@24")) {
		return method
			? [NSString stringWithFormat:@"setSandboxOverride ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"FOASandboxOverride setter not found";
	}

	@try {
		// The implementation has an explicit nil-hostname branch; this is the
		// native reset path used by the sandbox reset UI.
		((void (*)(id, SEL, id, id))objc_msgSend)(
			cls, selector, nil, @"RyukGram reset"
		);
		GQLLOG("FOA sandbox override reset");
		return @"FOA sandbox override cleared.\nRestart Instagram to rebuild all GraphQL clients.";
	} @catch (id exception) {
		return [NSString stringWithFormat:@"reset sandbox threw: %@",
			SCITruncatedDescription(exception, 800)];
	}
}

+ (id)newGraphQLDebugProviderOrMessage:(NSString * _Nullable * _Nullable)message {
	Class cls = SCIGraphQLProviderClass();
	if (!cls) {
		if (message) *message = @"IGDirectDeidentifiedRequestProvider class not found";
		return nil;
	}

	Method initMethod = class_getInstanceMethod(cls, @selector(init));
	if (!SCITypeEncodingMatches(initMethod, "@16@0:8")) {
		if (message) {
			*message = initMethod
				? [NSString stringWithFormat:@"provider init ABI changed: %s",
				   method_getTypeEncoding(initMethod)]
				: @"provider -init not found";
		}
		return nil;
	}

	@try {
		id provider = [[cls alloc] init];
		if (!provider && message) *message = @"provider init returned nil";
		return provider;
	} @catch (id exception) {
		if (message) {
			*message = [NSString stringWithFormat:@"provider init threw: %@",
				SCITruncatedDescription(exception, 800)];
		}
		return nil;
	}
}

+ (void)warmupGraphQLDebugWithCompletion:(SCIGraphQLInternalToolsCompletion)completion {
	NSString *failure = nil;
	id provider = [self newGraphQLDebugProviderOrMessage:&failure];
	if (!provider) {
		SCIDeliver(completion, failure);
		return;
	}

	SEL selector = NSSelectorFromString(@"warmupForGraphQLDebugWithCompletionHandler:");
	Method method = class_getInstanceMethod([provider class], selector);
	if (!SCITypeEncodingMatches(method, "v24@0:8@?<v@?>16")) {
		SCIDeliver(completion, method
			? [NSString stringWithFormat:@"GraphQL warmup ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"GraphQL warmup selector not found");
		return;
	}

	__block id providerHold = provider;
	void (^callback)(void) = ^{
		providerHold = nil;
		SCIDeliver(completion, @"GraphQL Debug provider warmup completed");
	};

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(provider, selector, callback);
	} @catch (id exception) {
		providerHold = nil;
		SCIDeliver(completion, [NSString stringWithFormat:@"GraphQL warmup threw: %@",
			SCITruncatedDescription(exception, 800)]);
	}
}

+ (void)retrieveGraphQLACSTokenWithCompletion:(SCIGraphQLInternalToolsCompletion)completion {
	NSString *failure = nil;
	id provider = [self newGraphQLDebugProviderOrMessage:&failure];
	if (!provider) {
		SCIDeliver(completion, failure);
		return;
	}

	SEL selector = NSSelectorFromString(
		@"retrieveACSTokenForGraphQLDebugWithCompletionHandler:"
	);
	Method method = class_getInstanceMethod([provider class], selector);
	const char *expected =
		"v24@0:8@?<v@?@\"DeidentifiedRequestACSToken\"@\"NSError\">16";
	if (!SCITypeEncodingMatches(method, expected)) {
		SCIDeliver(completion, method
			? [NSString stringWithFormat:@"ACS callback ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"ACS retrieval selector not found");
		return;
	}

	__block id providerHold = provider;
	void (^callback)(id, NSError *) = ^(id token, NSError *error) {
		providerHold = nil;
		if (error) {
			SCIDeliver(completion, [NSString stringWithFormat:@"ACS retrieval failed:\n%@",
				SCITruncatedDescription(error, 1200)]);
			return;
		}
		SCIDeliver(completion, SCIRedactedCredentialSummary(@"ACS token", token));
	};

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(provider, selector, callback);
	} @catch (id exception) {
		providerHold = nil;
		SCIDeliver(completion, [NSString stringWithFormat:@"ACS retrieval threw: %@",
			SCITruncatedDescription(exception, 800)]);
	}
}

+ (void)retrieveGraphQLACSTokenAndOHAIWithCompletion:(SCIGraphQLInternalToolsCompletion)completion {
	NSString *failure = nil;
	id provider = [self newGraphQLDebugProviderOrMessage:&failure];
	if (!provider) {
		SCIDeliver(completion, failure);
		return;
	}

	SEL selector = NSSelectorFromString(
		@"retrieveACSTokenAndOHAIConfigForGraphQLDebugWithCompletionHandler:"
	);
	Method method = class_getInstanceMethod([provider class], selector);
	const char *expected =
		"v24@0:8@?<v@?@\"DeidentifiedRequestACSToken\"@\"DeidentifiedRequestOHAIConfig\"@\"NSError\">16";
	if (!SCITypeEncodingMatches(method, expected)) {
		SCIDeliver(completion, method
			? [NSString stringWithFormat:@"ACS/OHAI callback ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"ACS/OHAI retrieval selector not found");
		return;
	}

	__block id providerHold = provider;
	void (^callback)(id, id, NSError *) = ^(id token, id config, NSError *error) {
		providerHold = nil;
		if (error) {
			SCIDeliver(completion, [NSString stringWithFormat:@"ACS/OHAI retrieval failed:\n%@",
				SCITruncatedDescription(error, 1200)]);
			return;
		}

		NSString *result = [NSString stringWithFormat:@"%@\n%@",
			SCIRedactedCredentialSummary(@"ACS token", token),
			SCIRedactedCredentialSummary(@"OHAI config", config)];
		SCIDeliver(completion, result);
	};

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(provider, selector, callback);
	} @catch (id exception) {
		providerHold = nil;
		SCIDeliver(completion, [NSString stringWithFormat:@"ACS/OHAI retrieval threw: %@",
			SCITruncatedDescription(exception, 800)]);
	}
}

@end
