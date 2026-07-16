// SCIGraphQLDebugProviderSafety.x
// =====================================================================
// Prevents the GraphQL Debug actions from calling the provider's deliberately
// unavailable Objective-C -init. The exact Instagram 438.0.564 binary exposes
// -init as @16@0:8, but its IMP is a Swift trap stub ending in BRK #1.
//
// A usable provider owns live pandoService/userDefaults/launcherSet state. It is
// captured from Instagram's dependency-injected preview fetcher or recovered
// from SCIDogfoodObjectRuntime. No synthetic provider or credential is created.
// =====================================================================

#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define GPSLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGraphQLProviderSafety] " fmt, ##__VA_ARGS__)

static __weak id sSCILiveGraphQLDebugProvider;

static Class SCIProviderClass(void) {
	return objc_getClass(
		"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider");
}

static void SCICaptureProvider(id provider, NSString *source) {
	Class providerClass = SCIProviderClass();
	if (!provider || !providerClass || ![provider isKindOfClass:providerClass]) return;

	sSCILiveGraphQLDebugProvider = provider;
	[SCIDogfoodObjectRuntime noteObject:provider
		role:@"graphql-debug-provider"
		source:source ?: @"unknown"];
	GPSLOG("captured live provider %{public}@ from %{public}@",
	       NSStringFromClass([provider class]), source ?: @"unknown");
}

// Instagram injects the live provider here. ABI confirmed in Instagram(29):
// @64@0:8@16@24@32@40@48@56
static id (*orig_SCIReceiverPreviewInit)(
	id, SEL, id, id, id, id, id, id
) = NULL;

static id SCIReceiverPreviewInit(
	id self, SEL _cmd,
	id directRepo,
	id directAggregatedMediaCache,
	id launcherSet,
	id userDefaults,
	id pandoGraphQLService,
	id deidentifiedRequestProvider
) {
	SCICaptureProvider(deidentifiedRequestProvider,
		@"IGDirectReceiverFetchPreviewDataFetcher.init");

	return orig_SCIReceiverPreviewInit
		? orig_SCIReceiverPreviewInit(
			self, _cmd, directRepo, directAggregatedMediaCache,
			launcherSet, userDefaults, pandoGraphQLService,
			deidentifiedRequestProvider)
		: nil;
}

// Capture self when Instagram itself uses the provider, covering flows that do
// not instantiate the preview fetcher before the Dev menu is opened.
static id (*orig_SCIProviderGetStoredOHAI)(id, SEL) = NULL;
static id SCIProviderGetStoredOHAI(id self, SEL _cmd) {
	SCICaptureProvider(self, @"IGDirectDeidentifiedRequestProvider.getStoredOHAIConfig");
	return orig_SCIProviderGetStoredOHAI
		? orig_SCIProviderGetStoredOHAI(self, _cmd)
		: nil;
}

static void (*orig_SCIProviderWarmupReceiver)(id, SEL, id) = NULL;
static void SCIProviderWarmupReceiver(id self, SEL _cmd, id completion) {
	SCICaptureProvider(self, @"IGDirectDeidentifiedRequestProvider.receiver-warmup");
	if (orig_SCIProviderWarmupReceiver) {
		orig_SCIProviderWarmupReceiver(self, _cmd, completion);
	}
}

// Replaces only RyukGram's unsafe private helper. It intentionally does not call
// the original because the original executes [[providerClass alloc] init], whose
// exact IMP is the trap observed in the uploaded crash log.
static id (*orig_SCIDiagnosticsGraphQLDebugProvider)(id, SEL) = NULL;
static id SCIDiagnosticsGraphQLDebugProvider(id self, SEL _cmd) {
	Class providerClass = SCIProviderClass();
	id provider = sSCILiveGraphQLDebugProvider;

	if (provider && (!providerClass || [provider isKindOfClass:providerClass])) {
		return provider;
	}

	if (providerClass) {
		provider = [SCIDogfoodObjectRuntime liveInstanceOfClass:providerClass];
		if (provider) {
			SCICaptureProvider(provider, @"SCIDogfoodObjectRuntime");
			return provider;
		}
	}

	GPSLOG("no live GraphQL Debug provider; refusing unavailable -init");
	return nil;
}

static BOOL SCIEncodingMatches(Method method, const char *expected) {
	if (!method || !expected) return NO;
	const char *encoding = method_getTypeEncoding(method);
	return encoding && strcmp(encoding, expected) == 0;
}

static void SCIInstallGraphQLProviderSafety(void) {
	static BOOL attempted = NO;
	if (attempted) return;
	attempted = YES;

	Class diagnostics = objc_getClass("SCIGraphQLDogfoodDiagnostics");
	SEL providerSelector = NSSelectorFromString(@"graphQLDebugProvider");
	Method providerMethod = diagnostics
		? class_getClassMethod(diagnostics, providerSelector)
		: NULL;
	if (diagnostics && SCIEncodingMatches(providerMethod, "@16@0:8")) {
		MSHookMessageEx(object_getClass(diagnostics), providerSelector,
			(IMP)SCIDiagnosticsGraphQLDebugProvider,
			(IMP *)&orig_SCIDiagnosticsGraphQLDebugProvider);
	}

	Class preview = objc_getClass(
		"_TtC44IGDirectReceiverFetchPreviewDataFetcherSwift39IGDirectReceiverFetchPreviewDataFetcher");
	SEL previewInit = NSSelectorFromString(
		@"initWithDirectRepo:directAggregatedMediaCache:launcherSet:userDefaults:pandoGraphQLService:deidentifiedRequestProvider:");
	Method previewMethod = preview
		? class_getInstanceMethod(preview, previewInit)
		: NULL;
	if (preview && SCIEncodingMatches(previewMethod,
		"@64@0:8@16@24@32@40@48@56")) {
		MSHookMessageEx(preview, previewInit,
			(IMP)SCIReceiverPreviewInit,
			(IMP *)&orig_SCIReceiverPreviewInit);
	}

	Class providerClass = SCIProviderClass();
	SEL storedSelector = NSSelectorFromString(@"getStoredOHAIConfig");
	Method storedMethod = providerClass
		? class_getInstanceMethod(providerClass, storedSelector)
		: NULL;
	if (providerClass && SCIEncodingMatches(storedMethod, "@16@0:8")) {
		MSHookMessageEx(providerClass, storedSelector,
			(IMP)SCIProviderGetStoredOHAI,
			(IMP *)&orig_SCIProviderGetStoredOHAI);
	}

	SEL receiverWarmup = NSSelectorFromString(
		@"warmupForIGDReceiverFetchWithCompletionHandler:");
	Method warmupMethod = providerClass
		? class_getInstanceMethod(providerClass, receiverWarmup)
		: NULL;
	if (providerClass && warmupMethod) {
		MSHookMessageEx(providerClass, receiverWarmup,
			(IMP)SCIProviderWarmupReceiver,
			(IMP *)&orig_SCIProviderWarmupReceiver);
	}

	GPSLOG("installed diagnostics=%d preview=%d stored=%d receiverWarmup=%d",
	       orig_SCIDiagnosticsGraphQLDebugProvider != NULL,
	       orig_SCIReceiverPreviewInit != NULL,
	       orig_SCIProviderGetStoredOHAI != NULL,
	       orig_SCIProviderWarmupReceiver != NULL);
}

%ctor {
	@autoreleasepool {
		// Safety-only hooks: no scan, network call, provider construction or
		// preference mutation occurs here.
		SCIInstallGraphQLProviderSafety();
	}
}
