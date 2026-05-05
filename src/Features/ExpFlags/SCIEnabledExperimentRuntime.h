#import <Foundation/Foundation.h>
#import "SCIExpFlags.h"

@interface SCIEnabledExperimentEntry : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *methodName;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) BOOL defaultKnown;
@property (nonatomic, assign) BOOL defaultValue;
@property (nonatomic, assign) NSUInteger hitCount;
@property (nonatomic, assign) SCIExpFlagOverride savedState;
@end

@interface SCIEnabledExperimentRuntime : NSObject
+ (void)install;
+ (NSArray<SCIEnabledExperimentEntry *> *)allEntries;
+ (NSArray<SCIEnabledExperimentEntry *> *)filteredEntriesForQuery:(NSString *)query mode:(NSInteger)mode;
+ (void)setSavedState:(SCIExpFlagOverride)state forEntry:(SCIEnabledExperimentEntry *)entry;
+ (SCIExpFlagOverride)savedStateForEntry:(SCIEnabledExperimentEntry *)entry;
+ (NSString *)stateLabelForEntry:(SCIEnabledExperimentEntry *)entry;
+ (NSString *)defaultLabelForEntry:(SCIEnabledExperimentEntry *)entry;
+ (NSString *)summaryTextForEntry:(SCIEnabledExperimentEntry *)entry;
+ (NSUInteger)installedCount;
@end
