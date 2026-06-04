#import <Foundation/Foundation.h>

@interface SCIDogfooding : NSObject
+ (BOOL)isAvailable;
// Working: Notes dogfooding has its own static funcs that bootstrap config.
+ (void)presentNotesDogfoodingSettings;
// Native MetaLocalExperiment browser (the real experiment list).
+ (void)presentMetaLocalExperimentBrowser;
@end
