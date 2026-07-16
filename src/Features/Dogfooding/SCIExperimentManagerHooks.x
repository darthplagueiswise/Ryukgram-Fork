#import "../../Utils.h"

void SCIInstallUnifiedExperimentManagerHooksIfNeeded(void);
static BOOL SCIUnifiedExperimentOn(void) { return [SCIUtils getBoolPref:@"sci_force_unified_experiment_managers"]; }
static BOOL sSCIUnifiedExperimentInstalled = NO;

%group SCIUnifiedExperimentManagers
%hook FBCCIGExperimentManager
- (BOOL)isFeatureEnabled:(unsigned long long)featureID {
	if (SCIUnifiedExperimentOn()) return YES;
	return %orig(featureID);
}
- (BOOL)isFeatureEnabledWithoutLogging:(unsigned long long)featureID {
	if (SCIUnifiedExperimentOn()) return YES;
	return %orig(featureID);
}
%end

%hook FBCustomExperimentManager
- (BOOL)isFeatureEnabled:(unsigned long long)featureID {
	if (SCIUnifiedExperimentOn()) return YES;
	return %orig(featureID);
}
- (BOOL)isFeatureEnabledWithoutLogging:(unsigned long long)featureID {
	if (SCIUnifiedExperimentOn()) return YES;
	return %orig(featureID);
}
%end
%end

void SCIInstallUnifiedExperimentManagerHooksIfNeeded(void) {
	if (sSCIUnifiedExperimentInstalled || !SCIUnifiedExperimentOn()) return;
	sSCIUnifiedExperimentInstalled = YES;
	%init(SCIUnifiedExperimentManagers);
}

%ctor {
	@autoreleasepool {
		SCIInstallUnifiedExperimentManagerHooksIfNeeded();
	}
}
