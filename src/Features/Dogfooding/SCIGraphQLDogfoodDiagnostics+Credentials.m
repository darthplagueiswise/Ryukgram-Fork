#import "SCIGraphQLDogfoodDiagnostics.h"
#import "../../SCIDefaults.h"
#import "../../Utils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static NSString *const kSCIE2EBypassKey = @"sci_force_e2e_bypass";

void SCIRegisterGraphQLDogfoodDevDefaults(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SCIRegisterDefaultsOnce();

		NSDictionary *extra = @{ kSCIE2EBypassKey: @(NO) };
		[NSUserDefaults.standardUserDefaults registerDefaults:extra];

		// Settings backup exports SCIUtils.sciRegisteredDefaults. Merge the key
		// into that canonical runtime dictionary instead of maintaining a second
		// untracked defaults list.
		NSMutableDictionary *registered =
			[[SCIUtils sciRegisteredDefaults] mutableCopy] ?: [NSMutableDictionary dictionary];
		[registered addEntriesFromDictionary:extra];
		[SCIUtils setSciRegisteredDefaults:registered.copy];
	});
}

__attribute__((constructor))
static void SCIGraphQLDogfoodDevDefaultsCtor(void) {
	@autoreleasepool {
		SCIRegisterGraphQLDogfoodDevDefaults();
	}
}

static Class DGCredentialProviderClass(void) {
	return objc_getClass(
		"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider"
	);
}

static BOOL DGCredentialTypeMatches(Method method, const char *expected) {
	if (!method || !expected) return NO;
	const char *actual = method_getTypeEncoding(method);
	return actual && strcmp(actual, expected) == 0;
}

static NSString *DGCredentialClass(id object) {
	return object ? (NSStringFromClass([object class]) ?: @"unknown") : @"nil";
}

static NSString *DGCredentialError(id error) {
	if (!error) return @"unknown error";
	NSString *description = nil;
	@try { description = [error description]; }
	@catch (__unused id exception) {}
	if (!description.length) description = DGCredentialClass(error);
	if (description.length > 1200) {
		description = [[description substringToIndex:1200] stringByAppendingString:@"…"];
	}
	return description;
}

static void DGCredentialDeliver(void (^completion)(NSString *), NSString *message) {
	if (!completion) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(message ?: @"No result");
	});
}

static id DGNewCredentialProvider(NSString **failure) {
	Class cls = DGCredentialProviderClass();
	if (!cls) {
		if (failure) *failure = @"IGDirectDeidentifiedRequestProvider is not loaded.";
		return nil;
	}

	Method initMethod = class_getInstanceMethod(cls, @selector(init));
	if (!DGCredentialTypeMatches(initMethod, "@16@0:8")) {
		if (failure) {
			*failure = initMethod
				? [NSString stringWithFormat:@"Provider init ABI changed: %s",
				   method_getTypeEncoding(initMethod)]
				: @"Provider -init is unavailable.";
		}
		return nil;
	}

	@try {
		id provider = [[cls alloc] init];
		if (!provider && failure) *failure = @"Provider init returned nil.";
		return provider;
	} @catch (id exception) {
		if (failure) {
			*failure = [NSString stringWithFormat:@"Provider init threw: %@",
				DGCredentialError(exception)];
		}
		return nil;
	}
}

@implementation SCIGraphQLDogfoodDiagnostics (Credentials)

+ (void)retrieveGraphQLDebugACSTokenStatusWithCompletion:(void (^)(NSString *result))completion {
	NSString *failure = nil;
	id provider = DGNewCredentialProvider(&failure);
	if (!provider) {
		DGCredentialDeliver(completion, failure);
		return;
	}

	SEL selector = NSSelectorFromString(
		@"retrieveACSTokenForGraphQLDebugWithCompletionHandler:"
	);
	Method method = class_getInstanceMethod([provider class], selector);
	const char *expected =
		"v24@0:8@?<v@?@\"DeidentifiedRequestACSToken\"@\"NSError\">16";
	if (!DGCredentialTypeMatches(method, expected)) {
		DGCredentialDeliver(completion, method
			? [NSString stringWithFormat:@"ACS callback ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"ACS retrieval selector is unavailable.");
		return;
	}

	__block id providerHold = provider;
	void (^handler)(id, NSError *) = ^(id token, NSError *error) {
		providerHold = nil;
		if (error) {
			DGCredentialDeliver(completion,
				[NSString stringWithFormat:@"ACS retrieval failed:\n%@",
				 DGCredentialError(error)]);
			return;
		}
		DGCredentialDeliver(completion,
			[NSString stringWithFormat:
			 @"ACS provider completed.\nToken present: %@\nRuntime class: %@\n\nToken contents were not logged, persisted or displayed.",
			 token ? @"YES" : @"NO", DGCredentialClass(token)]);
	};

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(provider, selector, handler);
	} @catch (id exception) {
		providerHold = nil;
		DGCredentialDeliver(completion,
			[NSString stringWithFormat:@"ACS retrieval threw: %@",
			 DGCredentialError(exception)]);
	}
}

+ (void)retrieveGraphQLDebugACSAndOHAIStatusWithCompletion:(void (^)(NSString *result))completion {
	NSString *failure = nil;
	id provider = DGNewCredentialProvider(&failure);
	if (!provider) {
		DGCredentialDeliver(completion, failure);
		return;
	}

	SEL selector = NSSelectorFromString(
		@"retrieveACSTokenAndOHAIConfigForGraphQLDebugWithCompletionHandler:"
	);
	Method method = class_getInstanceMethod([provider class], selector);
	const char *expected =
		"v24@0:8@?<v@?@\"DeidentifiedRequestACSToken\"@\"DeidentifiedRequestOHAIConfig\"@\"NSError\">16";
	if (!DGCredentialTypeMatches(method, expected)) {
		DGCredentialDeliver(completion, method
			? [NSString stringWithFormat:@"ACS/OHAI callback ABI changed: %s",
			   method_getTypeEncoding(method)]
			: @"ACS/OHAI retrieval selector is unavailable.");
		return;
	}

	__block id providerHold = provider;
	void (^handler)(id, id, NSError *) = ^(id token, id config, NSError *error) {
		providerHold = nil;
		if (error) {
			DGCredentialDeliver(completion,
				[NSString stringWithFormat:@"ACS/OHAI retrieval failed:\n%@",
				 DGCredentialError(error)]);
			return;
		}
		DGCredentialDeliver(completion,
			[NSString stringWithFormat:
			 @"GraphQL Debug provider completed.\nACS present: %@ (%@)\nOHAI present: %@ (%@)\n\nCredential/config contents were not logged, persisted or displayed.",
			 token ? @"YES" : @"NO", DGCredentialClass(token),
			 config ? @"YES" : @"NO", DGCredentialClass(config)]);
	};

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(provider, selector, handler);
	} @catch (id exception) {
		providerHold = nil;
		DGCredentialDeliver(completion,
			[NSString stringWithFormat:@"ACS/OHAI retrieval threw: %@",
			 DGCredentialError(exception)]);
	}
}

@end
