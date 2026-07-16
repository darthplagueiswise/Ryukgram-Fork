#import "SCIGraphQLDogfoodDiagnostics.h"
#import "../../SCIDefaults.h"
#import "../../Utils.h"

static NSString *const kSCIE2EBypassKey = @"sci_force_e2e_bypass";

void SCIRegisterGraphQLDogfoodDevDefaults(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SCIRegisterDefaultsOnce();

		NSDictionary *extra = @{ kSCIE2EBypassKey: @(NO) };
		[NSUserDefaults.standardUserDefaults registerDefaults:extra];

		// Backup exports SCIUtils.sciRegisteredDefaults. Merge this developer
		// preference into that same canonical dictionary, never a side list.
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
